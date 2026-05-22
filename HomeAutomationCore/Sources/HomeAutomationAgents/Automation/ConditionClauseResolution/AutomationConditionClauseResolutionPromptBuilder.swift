import Foundation
import FoundationModels
import HomeAutomationCore

@Generable
public struct AutomationConditionClauseFMOutput: Sendable, Hashable, Codable {
    public let condition: AutomationConditionOutput?
    public let deviceID: String?
    public let capability: String?
    public let attribute: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        condition: AutomationConditionOutput?,
        deviceID: String?,
        capability: String?,
        attribute: String?,
        confidence: Double
    ) {
        self.condition = condition
        self.deviceID = deviceID
        self.capability = capability
        self.attribute = attribute
        self.confidence = confidence
    }
}

enum AutomationConditionClauseResolutionPromptBuilder {
    static let instructions = """
    Resolve one automation condition leaf into a structured condition.

    Decide the condition operator and operands. Choose deviceID, capability, and attribute from the provided device and capability lists.
    Return one comparison, between, or changes condition when possible.
    Use the requested triggerPolicy. Schedule preconditions use "never"; device-trigger clauses use "always".
    Do not resolve actions or SmartThings JSON.
    """

    static func prompt(
        input: AutomationConditionClauseResolutionInput,
        fallback: HomeAutomationCondition?
    ) -> String {
        let capabilityNames = input.availableDevices.flatMap(\.capabilities)
        return """
        Full user command:
        \(input.fullUserText)

        Condition component:
        id: \(input.component.id)
        rawText: \(input.component.rawText)
        triggerPolicy: \(input.triggerPolicy.rawValue)

        Available devices:
        \(AvailableConditionDevicesTool.promptList(from: input.availableDevices))

        Capability attributes:
        \(CapabilityAttributeCatalogTool.promptList(for: Array(Set(capabilityNames)).sorted()))

        Deterministic hint:
        \(String(describing: fallback))
        Verify or correct this hint.
        """
    }
}
