import Foundation

public protocol CodexCLICommandParaphraseRunning: Sendable {
    func run(prompt: String, requestedCount: Int) async throws -> [String]
}

public struct CodexCLICommandParaphraseProvider: CommandParaphraseProvider {
    private let runner: any CodexCLICommandParaphraseRunning
    private let maxAttempts: Int
    private let validator: CommandParaphraseValidator

    public init(
        runner: any CodexCLICommandParaphraseRunning = CodexCLICommandParaphraseRunner(),
        maxAttempts: Int = 3,
        validator: CommandParaphraseValidator = CommandParaphraseValidator()
    ) {
        self.runner = runner
        self.maxAttempts = max(1, maxAttempts)
        self.validator = validator
    }

    public func paraphrases(for spec: CanonicalCommandSpec, count: Int) async throws -> [String] {
        guard count > 0 else { return [] }

        var accepted: [String] = []
        var rejectedCount = 0
        var lastError: (any Error)?
        for attempt in 1...maxAttempts where accepted.count < count {
            let requestedCount = max((count - accepted.count) * 2, count + 2)
            do {
                let prompt = Self.prompt(for: spec, requestedCount: requestedCount, attempt: attempt)
                let raw = try await runner.run(prompt: prompt, requestedCount: requestedCount)
                let validated = validator.validatedParaphrases(raw, for: spec)
                rejectedCount += max(0, raw.count - validated.count)
                accepted = stableUnique(accepted + validated)
            } catch let error as CommandParaphraseProviderError {
                lastError = error
                switch error {
                case .codexCLIInvalidOutput, .invalidModelJSON:
                    continue
                default:
                    throw error
                }
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
        Return only one JSON object with this shape: {"commands":["..."]}.

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
        - Preserve the exact target device and numeric suffix. Bulb 1, Bulb2, Bulb 3, Lamp 01, and Light 2 are different devices.
        - Preserve the same action, capability, command, numeric value, schedule, and condition meaning.
        - Do not invent device IDs, room names, capabilities, values, schedules, or extra conditions.
        - Do not include labels, comments, markdown fences, explanations, numbering, or JSON outside the root object.
        - Keep each command under 140 characters.
        - Use varied phrasing, word order, politeness, and spoken-number forms only when safe.
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

public struct CodexCLICommandParaphraseRunner: CodexCLICommandParaphraseRunning {
    private let executablePath: String
    private let model: String?
    private let profile: String?
    private let workingDirectory: String?

    public init(
        executablePath: String? = ProcessInfo.processInfo.environment["HOME_AUTOMATION_EVAL_CODEX_PATH"],
        model: String? = ProcessInfo.processInfo.environment["HOME_AUTOMATION_EVAL_CODEX_MODEL"],
        profile: String? = ProcessInfo.processInfo.environment["HOME_AUTOMATION_EVAL_CODEX_PROFILE"],
        workingDirectory: String? = FileManager.default.currentDirectoryPath
    ) {
        if let executablePath, !executablePath.isEmpty {
            self.executablePath = executablePath
        } else {
            self.executablePath = Self.defaultExecutablePath()
        }
        self.model = model?.isEmpty == false ? model : nil
        self.profile = profile?.isEmpty == false ? profile : nil
        self.workingDirectory = workingDirectory?.isEmpty == false ? workingDirectory : nil
    }

    public func run(prompt: String, requestedCount: Int) async throws -> [String] {
        let executablePath = executablePath
        let model = model
        let profile = profile
        let workingDirectory = workingDirectory
        return try await Task.detached(priority: .utility) {
            try Self.runCodexProcess(
                executablePath: executablePath,
                model: model,
                profile: profile,
                workingDirectory: workingDirectory,
                prompt: prompt,
                requestedCount: requestedCount
            )
        }.value
    }

    private static func defaultExecutablePath() -> String {
        let appBundlePath = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.fileExists(atPath: appBundlePath) {
            return appBundlePath
        }
        return "codex"
    }

    private static func runCodexProcess(
        executablePath: String,
        model: String?,
        profile: String?,
        workingDirectory: String?,
        prompt: String,
        requestedCount: Int
    ) throws -> [String] {
        #if os(macOS)
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("home-automation-codex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let schemaURL = tempDirectory.appendingPathComponent("schema.json")
        let outputURL = tempDirectory.appendingPathComponent("output.json")
        let stdoutURL = tempDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.txt")
        try writeOutputSchema(to: schemaURL, requestedCount: requestedCount)
        _ = fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        _ = fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        var arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--ask-for-approval",
            "never",
            "--color",
            "never",
            "--output-schema",
            schemaURL.path,
            "--output-last-message",
            outputURL.path
        ]
        if let workingDirectory {
            arguments.append(contentsOf: ["--cd", workingDirectory])
        }
        if let model {
            arguments.append(contentsOf: ["--model", model])
        }
        if let profile {
            arguments.append(contentsOf: ["--profile", profile])
        }
        arguments.append(prompt)

        let process = Process()
        if executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments.insert(executablePath, at: 0)
        }
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw CommandParaphraseProviderError.codexCLIUnavailable(
                "\(executablePath): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()

        try? stdoutHandle.close()
        try? stderrHandle.close()
        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            throw CommandParaphraseProviderError.codexCLIExecutionFailed(
                exitCode: process.terminationStatus,
                stderr: stderr.isEmpty ? stdout : stderr
            )
        }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let parseSource = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : output
        return try parseCommands(from: parseSource)
        #else
        throw CommandParaphraseProviderError.codexCLIUnavailable("Codex CLI is only supported on macOS.")
        #endif
    }

    private static func writeOutputSchema(to url: URL, requestedCount: Int) throws {
        let count = max(1, requestedCount)
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["commands"],
            "properties": [
                "commands": [
                    "type": "array",
                    "minItems": count,
                    "maxItems": count,
                    "items": [
                        "type": "string",
                        "minLength": 1,
                        "maxLength": 220
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func parseCommands(from text: String) throws -> [String] {
        let candidates = [
            text,
            stripMarkdownFence(text),
            extractJSONObject(from: text) ?? ""
        ]
        for candidate in candidates {
            guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard let data = candidate.data(using: .utf8) else {
                continue
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let commands = object["commands"] as? [String],
               !commands.isEmpty {
                return commands
            }
            if let commands = try? JSONSerialization.jsonObject(with: data) as? [String],
               !commands.isEmpty {
                return commands
            }
        }
        throw CommandParaphraseProviderError.codexCLIInvalidOutput(
            "Codex output did not contain a JSON object with a non-empty commands array."
        )
    }

    private static func stripMarkdownFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var inString = false
        var escaped = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
