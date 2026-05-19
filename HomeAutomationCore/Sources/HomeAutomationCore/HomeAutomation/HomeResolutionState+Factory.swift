import Foundation

extension HomeResolutionState {
    public static func forOperation(
        text: String,
        operation: HomeOperationDetectionResult
    ) -> HomeResolutionState {
        HomeResolutionState(
            rawText: text,
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.75,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(
                domain: operation.domain,
                confidence: operation.confidence
            ),
            intent: HomeIntentFamilyResult(
                topFamilies: operation.operation == .automationCreation ? [.createAutomation] : [.unsupported],
                confidence: operation.confidence
            ),
            deviceType: HomeDeviceTypeResult(deviceTypes: [], confidence: 0.4),
            slots: HomeSlotExtractionResult(
                rooms: [],
                deviceNicknames: [],
                values: [],
                modes: [],
                confidence: 0.4
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: .low,
                requiresConfirmation: false,
                reason: operation.reason,
                confidence: operation.confidence
            )
        )
    }
}
