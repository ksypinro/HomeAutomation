import Foundation
import FoundationModels

@Generable
public struct AutomationComponentPlanFMOutput: Sendable, Hashable, Codable {
    public let triggerRawText: String?
    public let triggerKind: AutomationTriggerKindHint
    public let actionRawTexts: [String]
    public let conditionRawTexts: [String]
    public let conditionConnector: String?
    public let unsupportedFragments: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        triggerRawText: String?,
        triggerKind: AutomationTriggerKindHint,
        actionRawTexts: [String],
        conditionRawTexts: [String],
        conditionConnector: String?,
        unsupportedFragments: [String] = [],
        confidence: Double
    ) {
        self.triggerRawText = triggerRawText
        self.triggerKind = triggerKind
        self.actionRawTexts = actionRawTexts
        self.conditionRawTexts = conditionRawTexts
        self.conditionConnector = conditionConnector
        self.unsupportedFragments = unsupportedFragments
        self.confidence = confidence
    }
}

enum AutomationComponentSegmentationPromptBuilder {
    static let instructions = """
    Segment a smart-home automation creation request into independent trigger, action, and condition components.

    Return raw text spans only. Do not resolve devices, capabilities, commands, SmartThings JSON, or condition operands.
    Use stable ordering from the user text.
    Extract at most one triggerRawText. Schedule phrases such as "every day at 7 AM" are trigger text.
    Extract actionRawTexts as standalone immediate commands, such as "Turn on bedroom AC".
    Extract conditionRawTexts as leaf clauses, such as "living room light is off".
    If conditions are joined by "and" or "or", set conditionConnector to "and" or "or".
    """

    static func prompt(text: String, deterministicHint: AutomationComponentPlan?) -> String {
        var prompt = """
        User automation command:
        \(text)
        """
        if let deterministicHint {
            prompt += """

            Deterministic parser hint:
            - trigger: \(deterministicHint.trigger?.rawText ?? "nil")
            - triggerKind: \(deterministicHint.trigger?.kindHint.rawValue ?? "unknown")
            - actions: \(deterministicHint.actions.map(\.rawText))
            - conditions: \(deterministicHint.conditions.map(\.rawText))
            - conditionLeafIDs: \(deterministicHint.conditionTree?.leafIDs ?? [])
            - unsupportedFragments: \(deterministicHint.unsupportedFragments)
            Verify or correct this hint.
            """
        }
        return prompt
    }
}
