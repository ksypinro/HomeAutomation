import Foundation
import FoundationModels
import HomeAutomationCore

// MARK: - DisputeKind

public enum DisputeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case wrongValue
    case missing
    case extraneous
    case wrongTarget
    case wrongOperation
    case valueOutOfRange
    case wrongGrouping
}

// MARK: - DraftDispute

public struct DraftDispute: Sendable, Hashable, Codable {
    public let fieldID: String
    public let kind: DisputeKind
    public let evidence: String
    public let suggestedValue: String?

    public init(
        fieldID: String,
        kind: DisputeKind,
        evidence: String,
        suggestedValue: String? = nil
    ) {
        self.fieldID = fieldID
        self.kind = kind
        self.evidence = evidence
        self.suggestedValue = suggestedValue
    }
}

// MARK: - DraftVerdict

public struct DraftVerdict: Sendable, Hashable, Codable {
    public let accepted: Bool
    public var disputes: [DraftDispute]
    public let needsClarification: Bool
    public let riskUnderstated: Bool

    public init(
        accepted: Bool,
        disputes: [DraftDispute] = [],
        needsClarification: Bool = false,
        riskUnderstated: Bool = false
    ) {
        self.accepted = accepted
        self.disputes = disputes
        self.needsClarification = needsClarification
        self.riskUnderstated = riskUnderstated
    }

    public static let acceptedVerdict = DraftVerdict(accepted: true)
}

// MARK: - DynamicGenerationSchema builder

public enum DraftVerdictSchema {

    public static func schema(allowedFieldIDs: [String]) throws -> GenerationSchema {
        let disputeKindSchema = DynamicGenerationSchema(
            name: "DisputeKind",
            anyOf: DisputeKind.allCases.map(\.rawValue)
        )
        let fieldIDSchema = allowedFieldIDs.isEmpty
            ? DynamicGenerationSchema(type: String.self)
            : DynamicGenerationSchema(name: "FieldID", anyOf: allowedFieldIDs)

        let disputeSchema = DynamicGenerationSchema(
            name: "DraftDispute",
            properties: [
                .init(
                    name: "fieldID",
                    description: "Dotted-path ID of the disputed field.",
                    schema: fieldIDSchema
                ),
                .init(
                    name: "kind",
                    description: "What kind of problem was found.",
                    schema: disputeKindSchema
                ),
                .init(
                    name: "evidence",
                    description: "One sentence explaining the evidence for the dispute.",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
                .init(
                    name: "suggestedValue",
                    description: "Corrected value, if known.",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: true
                ),
            ]
        )

        let root = DynamicGenerationSchema(
            name: "DraftVerdict",
            properties: [
                .init(
                    name: "accepted",
                    description: "True when the draft is correct and should proceed without changes.",
                    schema: DynamicGenerationSchema(type: Bool.self)
                ),
                .init(
                    name: "disputes",
                    description: "List of fields that appear incorrect. Empty when accepted.",
                    schema: DynamicGenerationSchema(arrayOf: disputeSchema, maximumElements: 6)
                ),
                .init(
                    name: "needsClarification",
                    description: "True when the user's intent is too ambiguous to verify.",
                    schema: DynamicGenerationSchema(type: Bool.self)
                ),
                .init(
                    name: "riskUnderstated",
                    description: "True when the risk level should be higher than assessed.",
                    schema: DynamicGenerationSchema(type: Bool.self)
                ),
            ]
        )

        return try GenerationSchema(root: root, dependencies: [])
    }

    public static func verdict(from content: GeneratedContent) throws -> DraftVerdict {
        let accepted = try content.value(Bool.self, forProperty: "accepted")
        let needsClarification = try content.value(Bool.self, forProperty: "needsClarification")
        let riskUnderstated = try content.value(Bool.self, forProperty: "riskUnderstated")

        let disputeContents: [GeneratedContent]
        do {
            disputeContents = try content.value([GeneratedContent].self, forProperty: "disputes")
        } catch {
            disputeContents = []
        }

        let disputes = disputeContents.compactMap { item -> DraftDispute? in
            guard let fieldID = try? item.value(String.self, forProperty: "fieldID"),
                  let kindRaw = try? item.value(String.self, forProperty: "kind"),
                  let kind = DisputeKind(rawValue: kindRaw),
                  let evidence = try? item.value(String.self, forProperty: "evidence") else {
                return nil
            }
            let suggestedValue = try? item.value(String.self, forProperty: "suggestedValue")
            return DraftDispute(
                fieldID: fieldID,
                kind: kind,
                evidence: evidence,
                suggestedValue: suggestedValue
            )
        }

        return DraftVerdict(
            accepted: accepted,
            disputes: disputes,
            needsClarification: needsClarification,
            riskUnderstated: riskUnderstated
        )
    }
}

// MARK: - Post-constraint helpers

public extension DraftVerdict {

    func constrained(allowedFieldIDs: Set<String>, maxDisputes: Int = 6) -> DraftVerdict {
        var seen = Set<String>()
        var filtered = disputes
            .filter { allowedFieldIDs.contains($0.fieldID) }
            .filter { seen.insert($0.fieldID).inserted }
            .prefix(maxDisputes)
            .map { $0 }

        if riskUnderstated,
           allowedFieldIDs.contains(FieldID.riskLevel.rawValue),
           !seen.contains(FieldID.riskLevel.rawValue),
           filtered.count < maxDisputes {
            filtered.append(
                DraftDispute(
                    fieldID: FieldID.riskLevel.rawValue,
                    kind: .wrongValue,
                    evidence: "Verifier reported understated risk."
                )
            )
        }

        let normalizedAccepted = accepted &&
            filtered.isEmpty &&
            !needsClarification &&
            !riskUnderstated

        return DraftVerdict(
            accepted: normalizedAccepted,
            disputes: normalizedAccepted ? [] : filtered,
            needsClarification: needsClarification,
            riskUnderstated: riskUnderstated
        )
    }
}

// MARK: - VerifierUnavailable

public struct VerifierUnavailable: Error, Sendable, CustomStringConvertible {
    public let reason: String
    public init(reason: String = "Foundation model unavailable") {
        self.reason = reason
    }
    public var description: String { reason }
}
