import Foundation
import HomeAutomationCore

public enum NLUWorkerTask: String, Sendable, Hashable, Codable {
    case language
    case domain
    case intentFamily
    case deviceType
    case slotExtraction
    case riskClassification
}

public struct NLUModelCallPolicy: Sendable {
    public let languageThreshold: Double
    public let domainThreshold: Double
    public let intentFamilyThreshold: Double
    public let deviceTypeThreshold: Double
    public let slotExtractionThreshold: Double
    public let riskThreshold: Double

    public init(
        languageThreshold: Double = 0.90,
        domainThreshold: Double = 0.80,
        intentFamilyThreshold: Double = 0.78,
        deviceTypeThreshold: Double = 0.78,
        slotExtractionThreshold: Double = 0.78,
        riskThreshold: Double = 0.85
    ) {
        self.languageThreshold = languageThreshold
        self.domainThreshold = domainThreshold
        self.intentFamilyThreshold = intentFamilyThreshold
        self.deviceTypeThreshold = deviceTypeThreshold
        self.slotExtractionThreshold = slotExtractionThreshold
        self.riskThreshold = riskThreshold
    }

    public static let `default` = NLUModelCallPolicy()

    public func shouldUseModel(task: NLUWorkerTask, deterministicState: HomeResolutionState) -> Bool {
        switch task {
        case .language:
            return deterministicState.language.confidence < languageThreshold
        case .domain:
            return deterministicState.domain.confidence < domainThreshold
        case .intentFamily:
            return deterministicState.intent.confidence < intentFamilyThreshold
        case .deviceType:
            return deterministicState.deviceType.confidence < deviceTypeThreshold
        case .slotExtraction:
            return deterministicState.slots.confidence < slotExtractionThreshold
        case .riskClassification:
            if deterministicState.risk.riskLevel == .high || deterministicState.risk.riskLevel == .critical {
                return false
            }
            return deterministicState.risk.confidence < riskThreshold
        }
    }
}
