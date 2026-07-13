import Foundation
import FoundationModels
import HomeAutomationCore

@Generable
public struct BatchedConditionClauseFMOutput: Sendable, Hashable, Codable {
    @Guide(description: "One result per input clause. Each item must echo the input itemID.")
    public let items: [BatchedConditionClauseItemOutput]

    public init(items: [BatchedConditionClauseItemOutput]) {
        self.items = items
    }
}

@Generable
public struct BatchedConditionClauseItemOutput: Sendable, Hashable, Codable {
    @Guide(description: "Stable item identifier copied exactly from the matching input clause.")
    public let itemID: String
    public let condition: AutomationConditionOutput?
    public let deviceID: String?
    public let capability: String?
    public let attribute: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        itemID: String,
        condition: AutomationConditionOutput?,
        deviceID: String?,
        capability: String?,
        attribute: String?,
        confidence: Double
    ) {
        self.itemID = itemID
        self.condition = condition
        self.deviceID = deviceID
        self.capability = capability
        self.attribute = attribute
        self.confidence = confidence
    }
}
