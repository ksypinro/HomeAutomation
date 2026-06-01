import Foundation
import FoundationModels
import HomeAutomationCore

public protocol FoundationModelCommandParaphraseResponding: Sendable {
    func generateParaphrases(prompt: String, requestedCount: Int) async throws -> [String]
}

public struct FoundationModelCommandParaphraseProvider: CommandParaphraseProvider {
    private let responder: any FoundationModelCommandParaphraseResponding
    private let foundationModelAvailability: @Sendable () -> Bool
    private let maxAttempts: Int
    private let validator: CommandParaphraseValidator

    public init(
        responder: any FoundationModelCommandParaphraseResponding = LiveFoundationModelCommandParaphraseResponder(),
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        maxAttempts: Int = 3,
        validator: CommandParaphraseValidator = CommandParaphraseValidator()
    ) {
        self.responder = responder
        self.foundationModelAvailability = foundationModelAvailability
        self.maxAttempts = max(1, maxAttempts)
        self.validator = validator
    }

    public func paraphrases(for spec: CanonicalCommandSpec, count: Int) async throws -> [String] {
        guard count > 0 else { return [] }
        guard foundationModelAvailability() else {
            throw CommandParaphraseProviderError.liveModelUnavailable(FoundationModelDiagnostics.availabilityStatus())
        }

        var accepted: [String] = []
        var rejectedCount = 0
        var lastError: (any Error)?
        for attempt in 1...maxAttempts where accepted.count < count {
            let requestedCount = max((count - accepted.count) * 2, count + 2)
            do {
                let prompt = Self.prompt(for: spec, requestedCount: requestedCount, attempt: attempt)
                let raw = try await responder.generateParaphrases(
                    prompt: prompt,
                    requestedCount: requestedCount
                )
                let validated = validator.validatedParaphrases(raw, for: spec)
                rejectedCount += max(0, raw.count - validated.count)
                accepted = stableUnique(accepted + validated)
            } catch let error as CommandParaphraseProviderError {
                lastError = error
                if case .invalidModelJSON = error {
                    continue
                }
                throw error
            } catch {
                lastError = error
                continue
            }
        }

        guard !accepted.isEmpty else {
            if rejectedCount > 0 {
                throw CommandParaphraseProviderError.semanticDriftRejected(
                    specID: spec.id,
                    rejectedCount: rejectedCount
                )
            }
            if let lastError {
                throw CommandParaphraseProviderError.modelGenerationFailed(lastError.localizedDescription)
            }
            throw CommandParaphraseProviderError.insufficientValidParaphrases(
                specID: spec.id,
                requested: count,
                accepted: 0
            )
        }
        guard accepted.count >= count else {
            throw CommandParaphraseProviderError.insufficientValidParaphrases(
                specID: spec.id,
                requested: count,
                accepted: accepted.count
            )
        }
        return Array(accepted.prefix(count))
    }

    private static func prompt(
        for spec: CanonicalCommandSpec,
        requestedCount: Int,
        attempt: Int
    ) -> String {
        """
        Generate exactly \(requestedCount) diverse natural-language smart-home commands.
        Return only the structured `commands` array requested by the schema.

        Canonical command:
        \(spec.canonicalUtterance)

        Required semantics:
        - category: \(spec.category.rawValue)
        - target device display name: \(spec.deviceDisplayName ?? "none")
        - room: \(spec.room ?? "none")
        - operation: \(spec.expected.operation?.rawValue ?? "none")
        - allowed outcome: \(spec.expected.allowedOutcome.rawValue)
        - expected device IDs: \(spec.expected.expectedDeviceIDs.joined(separator: ","))
        - capability: \(spec.expected.capability ?? "none")
        - command: \(spec.expected.command ?? "none")
        - parameters: \(spec.expected.parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))
        - action count: \(spec.expected.actionCount.map(String.init) ?? "none")
        - condition count: \(spec.expected.conditionCount.map(String.init) ?? "none")

        Rules:
        - Preserve the same target device and numeric suffix. For example, Bulb 1, Bulb2, Bulb 3, and Lamp 01 are different devices.
        - Preserve the same action, capability, numeric value, schedule, and condition meaning.
        - Do not invent device IDs, room names, capabilities, values, or extra conditions.
        - Do not include labels, JSON keys, explanations, markdown, or numbering inside each command string.
        - Keep each command under 140 characters.
        - Use varied phrasing, word order, politeness, and spoken-number forms when safe.
        - Attempt \(attempt): avoid repeating earlier wording and stay semantically exact.
        """
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value.lowercased()).inserted {
            result.append(value)
        }
        return result
    }
}

public struct LiveFoundationModelCommandParaphraseResponder: FoundationModelCommandParaphraseResponding {
    public init() {}

    public func generateParaphrases(prompt: String, requestedCount: Int) async throws -> [String] {
        let instructions = """
        You generate concise smart-home command paraphrases for an evaluation dataset.
        You must preserve the exact semantics described by the prompt.
        Return only the requested structured output.
        """
        let session = LanguageModelSession(instructions: Instructions(instructions))
        return try await FoundationModelCallRecorder.record(
            agentID: "evaluationCommandParaphrase",
            policyMode: "dataset-generation",
            modelAvailability: FoundationModelDiagnostics.availabilityStatus(),
            promptCharacterCount: instructions.count + prompt.count,
            outputCharacterCount: { $0.joined(separator: "\n").count }
        ) {
            do {
                let response = try await session.respond(
                    to: Prompt(prompt),
                    schema: try Self.schema(maximumElements: requestedCount)
                )
                return try Self.paraphrases(from: response.content)
            } catch let error as CommandParaphraseProviderError {
                throw error
            } catch {
                throw CommandParaphraseProviderError.invalidModelJSON(error.localizedDescription)
            }
        }
    }

    private static func schema(maximumElements: Int) throws -> GenerationSchema {
        let commandSchema = DynamicGenerationSchema(type: String.self)
        let root = DynamicGenerationSchema(
            name: "CommandParaphrases",
            properties: [
                .init(
                    name: "commands",
                    description: "Natural-language command strings only.",
                    schema: DynamicGenerationSchema(
                        arrayOf: commandSchema,
                        minimumElements: max(1, maximumElements),
                        maximumElements: max(1, maximumElements)
                    )
                )
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func paraphrases(from content: GeneratedContent) throws -> [String] {
        let commands = try content.value([String].self, forProperty: "commands")
        guard !commands.isEmpty else {
            throw CommandParaphraseProviderError.invalidModelJSON("The model returned an empty commands array.")
        }
        return commands
    }
}
