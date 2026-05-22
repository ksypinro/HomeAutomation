import Foundation
import FoundationModels

@Generable
public struct AutomationTriggerResolutionFMOutput: Sendable, Hashable, Codable {
    public let trigger: AutomationTriggerOutput?
    public let unsupportedFragments: [String]
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        trigger: AutomationTriggerOutput?,
        unsupportedFragments: [String] = [],
        confidence: Double
    ) {
        self.trigger = trigger
        self.unsupportedFragments = unsupportedFragments
        self.confidence = confidence
    }
}

enum AutomationTriggerResolutionPromptBuilder {
    static let instructions = """
    Resolve one automation trigger component into a structured automation trigger.

    Return only the trigger. Do not resolve actions, command capabilities, SmartThings JSON, or unrelated conditions.
    For schedule triggers, extract repeatRule and 24-hour time. Use repeatRule "everyDay" for everyday/every day/daily.
    For device triggers, preserve the device condition shape when present, but do not resolve device IDs.
    """

    static func prompt(input: AutomationTriggerResolutionInput, fallback: AutomationTriggerResolutionOutput?) -> String {
        var prompt = """
        Full user command:
        \(input.fullUserText)

        Trigger component:
        id: \(input.component.id)
        rawText: \(input.component.rawText)
        kindHint: \(input.component.kindHint.rawValue)
        timezoneIdentifier: \(input.timezoneIdentifier ?? "nil")
        """
        if let fallback {
            prompt += """

            Deterministic trigger hint:
            \(String(describing: fallback.trigger))
            Verify or correct this hint.
            """
        }
        return prompt
    }
}
