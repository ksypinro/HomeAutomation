import Foundation
import FoundationModels

@Generable
public struct HomeResolvedParameter: Sendable, Hashable, Codable {
    @Guide(description: "Canonical parameter name such as value, mode, duration, color, attribute, or delta.")
    public let name: String
    @Guide(description: "String parameter value when not numeric.")
    public let value: String?
    public let numericValue: Double?
    @Guide(description: "Short unit such as percent, degree, minute, hour, celsius, or fahrenheit.")
    public let unit: String?
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        name: String,
        value: String? = nil,
        numericValue: Double? = nil,
        unit: String? = nil,
        confidence: Double
    ) {
        self.name = name
        self.value = value
        self.numericValue = numericValue
        self.unit = unit
        self.confidence = confidence
    }
}

@Generable
public struct HomeCommandDraft: Sendable, Hashable, Codable {
    public let intent: HomeAutomationIntent

    @Guide(description: "Selected device ID from the hydrated candidates only.")
    public let targetDeviceID: String?

    @Guide(description: "Selected group or room ID if the command targets a group.")
    public let targetGroupID: String?

    @Guide(description: "Capability name from hydrated candidates or canonical registry context only.")
    public let capability: String?
    @Guide(description: "Command name valid for the selected capability only.")
    public let command: String?
    @Guide(description: "Resolved parameters required by the selected command.", .maximumCount(6))
    public let parameters: [HomeResolvedParameter]
    public let needsClarification: Bool
    @Guide(description: "One concise user-facing question when clarification is needed.")
    public let clarificationQuestion: String?
    public let requiresConfirmation: Bool
    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    public let confidence: Double

    public init(
        intent: HomeAutomationIntent,
        targetDeviceID: String? = nil,
        targetGroupID: String? = nil,
        capability: String? = nil,
        command: String? = nil,
        parameters: [HomeResolvedParameter] = [],
        needsClarification: Bool,
        clarificationQuestion: String? = nil,
        requiresConfirmation: Bool,
        confidence: Double
    ) {
        self.intent = intent
        self.targetDeviceID = targetDeviceID
        self.targetGroupID = targetGroupID
        self.capability = capability
        self.command = command
        self.parameters = parameters
        self.needsClarification = needsClarification
        self.clarificationQuestion = clarificationQuestion
        self.requiresConfirmation = requiresConfirmation
        self.confidence = confidence
    }
}
