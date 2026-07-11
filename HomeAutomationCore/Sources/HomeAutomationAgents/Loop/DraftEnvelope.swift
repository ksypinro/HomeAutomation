import Foundation
import HomeAutomationCore

// MARK: - FieldID

public struct FieldID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

public extension FieldID {
    enum Command {
        case targetDeviceID
        case capability
        case commandName
        case room
        case parameters

        var segment: String {
            switch self {
            case .targetDeviceID: return "targetDeviceID"
            case .capability: return "capability"
            case .commandName: return "commandName"
            case .room: return "room"
            case .parameters: return "parameters"
            }
        }
    }

    static func command(_ field: Command) -> FieldID {
        FieldID(rawValue: "command.\(field.segment)")
    }

    static func action(_ index: Int, _ field: Command) -> FieldID {
        FieldID(rawValue: "automation.actions[\(index)].\(field.segment)")
    }

    static func conditionLeaf(_ index: Int, _ aspect: ConditionLeafAspect) -> FieldID {
        FieldID(rawValue: "automation.conditionLeaves[\(index)].\(aspect.segment)")
    }

    static func conditionTreeGroup(_ index: Int) -> FieldID {
        FieldID(rawValue: "automation.conditionTree.group[\(index)]")
    }

    static let operation = FieldID(rawValue: "operation")
    static let triggerType = FieldID(rawValue: "automation.trigger.type")
    static let triggerTime = FieldID(rawValue: "automation.trigger.time")
    static let triggerRepeat = FieldID(rawValue: "automation.trigger.repeat")
    static let riskLevel = FieldID(rawValue: "risk.level")

    enum ConditionLeafAspect {
        case target
        case capability
        case attribute
        case operatorName
        case value

        var segment: String {
            switch self {
            case .target: return "target"
            case .capability: return "capability"
            case .attribute: return "attribute"
            case .operatorName: return "operator"
            case .value: return "value"
            }
        }
    }
}

// MARK: - FieldProvenance

public enum FieldProvenance: Sendable, Hashable, Codable {
    case rules
    case model
    case repaired(iteration: Int)
}

// MARK: - CompactCandidate

public struct CompactCandidate: Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let room: String?
    public let deviceType: String

    public init(id: String, name: String, room: String?, deviceType: String) {
        self.id = id
        self.name = name
        self.room = room
        self.deviceType = deviceType
    }

    public init(from record: HomeCandidateRecord) {
        self.id = record.id
        self.name = record.displayName
        self.room = record.room
        self.deviceType = record.deviceType
    }
}

// MARK: - CommandDraftSection

public struct CommandDraftSection: Sendable, Hashable, Codable {
    public let targetDeviceID: String?
    public let candidateTable: [CompactCandidate]
    public let capability: String?
    public let commandName: String?
    public let parameters: [HomeResolvedParameter]
    public let room: String?

    public init(
        targetDeviceID: String?,
        candidateTable: [CompactCandidate] = [],
        capability: String?,
        commandName: String?,
        parameters: [HomeResolvedParameter] = [],
        room: String?
    ) {
        self.targetDeviceID = targetDeviceID
        self.candidateTable = candidateTable
        self.capability = capability
        self.commandName = commandName
        self.parameters = parameters
        self.room = room
    }
}

// MARK: - ClarificationSection

public struct ClarificationSection: Sendable, Hashable, Codable {
    public let question: String
    public let ambiguousFieldIDs: [FieldID]

    public init(question: String, ambiguousFieldIDs: [FieldID]) {
        self.question = question
        self.ambiguousFieldIDs = ambiguousFieldIDs
    }
}

// MARK: - RiskSection

public struct RiskSection: Sendable, Hashable, Codable {
    public private(set) var level: HomeAutomationRiskLevel
    public private(set) var floorReason: String

    public init(level: HomeAutomationRiskLevel, floorReason: String) {
        self.level = level
        self.floorReason = floorReason
    }

    public mutating func raise(to newLevel: HomeAutomationRiskLevel, reason: String) {
        guard newLevel.numericOrder > level.numericOrder else { return }
        level = newLevel
        floorReason = reason
    }
}

extension HomeAutomationRiskLevel {
    var numericOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

// MARK: - TriggerDraft

public struct TriggerDraft: Sendable, Hashable, Codable {
    public let type: TriggerDraftType
    public let time: HomeAutomationTimeOfDay?
    public let repeatRule: HomeAutomationRepeatRule?
    public let timezoneIdentifier: String?
    public let deviceDescription: String?
    /// The trigger fragment as segmented from the user text. Kept so any repair
    /// specialist can re-parse the trigger without re-segmenting the whole
    /// command (see `RepairSpecialistRegistry`'s `.trigger` handler).
    public let rawText: String?
    /// The structured device-trigger condition for `type == .device`, resolved
    /// to a compilable `HomeAutomationCondition` (device id + capability +
    /// attribute + operator + value). `nil` for schedule triggers, or when the
    /// deterministic parser could not resolve the device — in which case the
    /// `.trigger` repair specialist fills it in.
    public let deviceCondition: HomeAutomationCondition?
    public let confidence: Double

    public init(
        type: TriggerDraftType,
        time: HomeAutomationTimeOfDay? = nil,
        repeatRule: HomeAutomationRepeatRule? = nil,
        timezoneIdentifier: String? = nil,
        deviceDescription: String? = nil,
        rawText: String? = nil,
        deviceCondition: HomeAutomationCondition? = nil,
        confidence: Double
    ) {
        self.type = type
        self.time = time
        self.repeatRule = repeatRule
        self.timezoneIdentifier = timezoneIdentifier
        self.deviceDescription = deviceDescription
        self.rawText = rawText
        self.deviceCondition = deviceCondition
        self.confidence = confidence
    }

    public enum TriggerDraftType: String, Sendable, Hashable, Codable {
        case schedule
        case device
    }
}

// MARK: - ConditionLeafDraft

public struct ConditionLeafDraft: Sendable, Hashable, Codable {
    public let id: String
    public let rawText: String
    public let target: String?
    public let candidateTable: [CompactCandidate]
    public let capability: String?
    public let attribute: String?
    public let operatorName: HomeAutomationComparisonOperator?
    public let value: String?
    public let confidence: Double

    public init(
        id: String,
        rawText: String,
        target: String? = nil,
        candidateTable: [CompactCandidate] = [],
        capability: String? = nil,
        attribute: String? = nil,
        operatorName: HomeAutomationComparisonOperator? = nil,
        value: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.rawText = rawText
        self.target = target
        self.candidateTable = candidateTable
        self.capability = capability
        self.attribute = attribute
        self.operatorName = operatorName
        self.value = value
        self.confidence = confidence
    }
}

// MARK: - ConditionTreeDraft

public indirect enum ConditionTreeDraft: Sendable, Hashable, Codable {
    case leaf(String)
    case and([ConditionTreeDraft])
    case or([ConditionTreeDraft])
    case not(ConditionTreeDraft)

    public var leafIDs: [String] {
        switch self {
        case .leaf(let id):
            return [id]
        case .and(let children), .or(let children):
            return children.flatMap(\.leafIDs)
        case .not(let child):
            return child.leafIDs
        }
    }

    public init(from descriptor: AutomationConditionTreeDescriptor) {
        switch descriptor {
        case .leaf(let id):
            self = .leaf(id)
        case .and(let children):
            self = .and(children.map { ConditionTreeDraft(from: $0) })
        case .or(let children):
            self = .or(children.map { ConditionTreeDraft(from: $0) })
        case .not(let child):
            self = .not(ConditionTreeDraft(from: child))
        }
    }

    public func toDescriptor() -> AutomationConditionTreeDescriptor {
        switch self {
        case .leaf(let id):
            return .leaf(id)
        case .and(let children):
            return .and(children.map { $0.toDescriptor() })
        case .or(let children):
            return .or(children.map { $0.toDescriptor() })
        case .not(let child):
            return .not(child.toDescriptor())
        }
    }
}

// MARK: - ActionDraft

public struct ActionDraft: Sendable, Hashable, Codable {
    public let rawText: String
    public let order: Int
    public let command: CommandDraftSection

    public init(rawText: String, order: Int, command: CommandDraftSection) {
        self.rawText = rawText
        self.order = order
        self.command = command
    }
}

// MARK: - AutomationDraftSection

public struct AutomationDraftSection: Sendable, Hashable, Codable {
    public let trigger: TriggerDraft?
    public let conditionTree: ConditionTreeDraft?
    public let conditionLeaves: [ConditionLeafDraft]
    public let actions: [ActionDraft]
    public let unsupportedFragments: [String]
    public let precedenceAmbiguous: Bool

    public init(
        trigger: TriggerDraft? = nil,
        conditionTree: ConditionTreeDraft? = nil,
        conditionLeaves: [ConditionLeafDraft] = [],
        actions: [ActionDraft] = [],
        unsupportedFragments: [String] = [],
        precedenceAmbiguous: Bool = false
    ) {
        self.trigger = trigger
        self.conditionTree = conditionTree
        self.conditionLeaves = conditionLeaves
        self.actions = actions
        self.unsupportedFragments = unsupportedFragments
        self.precedenceAmbiguous = precedenceAmbiguous
    }
}

// MARK: - DraftEnvelope

public struct DraftEnvelope: Sendable, Hashable, Codable {
    public static let currentVersion = 1

    public let version: Int
    public let userText: String
    public let operation: HomeAutomationOperationKind
    public let operationConfidence: Double
    public let command: CommandDraftSection?
    public let automation: AutomationDraftSection?
    public let risk: RiskSection
    public let clarification: ClarificationSection?
    public let provenance: [FieldID: FieldProvenance]
    public let fieldConfidence: [FieldID: Double]

    public init(
        userText: String,
        operation: HomeAutomationOperationKind,
        operationConfidence: Double,
        command: CommandDraftSection? = nil,
        automation: AutomationDraftSection? = nil,
        risk: RiskSection,
        clarification: ClarificationSection? = nil,
        provenance: [FieldID: FieldProvenance] = [:],
        fieldConfidence: [FieldID: Double] = [:]
    ) {
        self.version = Self.currentVersion
        self.userText = userText
        self.operation = operation
        self.operationConfidence = operationConfidence
        self.command = command
        self.automation = automation
        self.risk = risk
        self.clarification = clarification
        self.provenance = provenance
        self.fieldConfidence = fieldConfidence
    }

    public func disputableFieldIDs() -> [FieldID] {
        var ids: [FieldID] = [.operation]

        if command != nil {
            ids.append(contentsOf: [
                .command(.targetDeviceID),
                .command(.capability),
                .command(.commandName),
                .command(.room),
                .command(.parameters),
            ])
        }

        if let automation {
            if automation.trigger != nil {
                ids.append(contentsOf: [.triggerType, .triggerTime, .triggerRepeat])
            }

            for (i, _) in automation.actions.enumerated() {
                ids.append(contentsOf: [
                    .action(i, .targetDeviceID),
                    .action(i, .capability),
                    .action(i, .commandName),
                    .action(i, .parameters),
                ])
            }

            for (i, _) in automation.conditionLeaves.enumerated() {
                ids.append(contentsOf: [
                    .conditionLeaf(i, .target),
                    .conditionLeaf(i, .capability),
                    .conditionLeaf(i, .attribute),
                    .conditionLeaf(i, .operatorName),
                    .conditionLeaf(i, .value),
                ])
            }

            if automation.conditionTree != nil {
                let groupCount = countTreeGroups(automation.conditionTree!)
                for i in 0..<groupCount {
                    ids.append(.conditionTreeGroup(i))
                }
            }
        }

        ids.append(.riskLevel)
        return ids
    }

    public func lowConfidenceFieldIDs(threshold: Double = 0.5) -> [FieldID] {
        fieldConfidence.filter { $0.value < threshold }.map(\.key)
            .sorted { $0.rawValue < $1.rawValue }
    }

    public func withUpdatedProvenance(
        _ updates: [FieldID: FieldProvenance]
    ) -> DraftEnvelope {
        var merged = provenance
        for (key, value) in updates { merged[key] = value }
        return DraftEnvelope(
            userText: userText,
            operation: operation,
            operationConfidence: operationConfidence,
            command: command,
            automation: automation,
            risk: risk,
            clarification: clarification,
            provenance: merged,
            fieldConfidence: fieldConfidence
        )
    }

    public func withUpdatedConfidence(
        _ updates: [FieldID: Double]
    ) -> DraftEnvelope {
        var merged = fieldConfidence
        for (key, value) in updates { merged[key] = value }
        return DraftEnvelope(
            userText: userText,
            operation: operation,
            operationConfidence: operationConfidence,
            command: command,
            automation: automation,
            risk: risk,
            clarification: clarification,
            provenance: provenance,
            fieldConfidence: merged
        )
    }
}

// MARK: - Private helpers

private func countTreeGroups(_ tree: ConditionTreeDraft) -> Int {
    switch tree {
    case .leaf:
        return 0
    case .and(let children), .or(let children):
        return 1 + children.map { countTreeGroups($0) }.reduce(0, +)
    case .not(let child):
        return countTreeGroups(child)
    }
}
