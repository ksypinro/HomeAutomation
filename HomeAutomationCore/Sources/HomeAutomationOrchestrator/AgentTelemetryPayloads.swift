import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension ContextualHomeAgent {
    internal static func evaluationPayload(for output: Agent.Output) -> [String: String] {
        if let decision = output as? HomeCapabilityDecision {
            var payload: [String: String] = [
                "selectedCapability": decision.selectedCapability ?? "",
                "selectedCommand": decision.selectedCommand ?? "",
                "targetDeviceID": decision.targetDeviceID ?? "",
                "confidence": String(decision.confidence),
                "alternativeCount": String(decision.alternatives.count)
            ]
            payload["evidence"] = decision.evidence.joined(separator: " | ")
            return payload
        }
        if let routing = output as? HomeOperationRoutingResult {
            return [
                "producedFields": "operation,language,domain",
                "mergedAgentIDs": "operationDetection,language,domain",
                "operation": routing.operation.operation.rawValue,
                "operationConfidence": String(routing.operation.confidence),
                "languageCode": routing.language.languageCode,
                "languageConfidence": String(routing.language.confidence),
                "domain": String(describing: routing.domain.domain),
                "domainConfidence": String(routing.domain.confidence)
            ]
        }
        if let semantic = output as? HomeSemanticNLUResult {
            return [
                "producedFields": "intent,deviceType",
                "mergedAgentIDs": "intentFamily,deviceType",
                "intentFamilies": semantic.intent.topFamilies.map(String.init(describing:)).joined(separator: ","),
                "intentConfidence": String(semantic.intent.confidence),
                "deviceTypes": semantic.deviceType.deviceTypes.joined(separator: ","),
                "deviceTypeConfidence": String(semantic.deviceType.confidence)
            ]
        }
        if let aggregation = output as? HomeCandidateAggregationResult {
            return [
                "selectedCandidateIDs": aggregation.finalCandidateIDs.joined(separator: ","),
                "needsClarification": String(aggregation.needsClarification),
                "confidence": String(aggregation.confidence)
            ]
        }
        if let validation = output as? AutomationValidationResult {
            return [
                "validationResult": validation.status.rawValue,
                "requiresConfirmation": String(validation.requiresConfirmation),
                "issueCount": String(validation.issues.count)
            ]
        }
        if let resolution = output as? HomeCommandResolution {
            return [
                "finalOutcome": resolution.displaySummary
            ]
        }
        if let creation = output as? SmartThingsRuleCreationOutput {
            let status = creation.receipt?.status.rawValue ?? (creation.plan.requiresConfirmation ? "confirmationRequired" : "skipped")
            return [
                "validationResult": status,
                "requiresConfirmation": String(creation.plan.requiresConfirmation),
                "finalOutcome": status
            ]
        }
        return [:]
    }

    internal static func patchEvaluationPayload(for patch: ResolutionContextPatch) -> [String: String] {
        var payload: [String: String] = [:]
        if let aggregation = patch.updates[ResolutionContextPatchKey.aggregation.rawValue]?.get(HomeCandidateAggregationResult.self) {
            payload["selectedCandidateIDs"] = aggregation.finalCandidateIDs.joined(separator: ",")
        }
        if let decision = patch.updates[ResolutionContextPatchKey.capabilityDecision.rawValue]?.get(HomeCapabilityDecision.self) {
            payload["selectedCapability"] = decision.selectedCapability ?? ""
            payload["selectedCommand"] = decision.selectedCommand ?? ""
            payload["targetDeviceID"] = decision.targetDeviceID ?? ""
        }
        if let resolution = patch.updates[ResolutionContextPatchKey.resolution.rawValue]?.get(HomeCommandResolution.self) {
            payload["finalOutcome"] = resolution.displaySummary
        }
        if let validation = patch.scopedUpdates[.root]?[ResolutionContextPatchKey.automationValidation.rawValue]?.get(AutomationValidationResult.self) {
            payload["validationResult"] = validation.status.rawValue
        }
        if let transition = patch.transitionRequest {
            payload["graphTransitionKind"] = transition.kind
            payload["graphTransitionReason"] = transition.reason
        }
        if patch.updates[ResolutionContextPatchKey.operation.rawValue]?.get(HomeOperationDetectionResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.language.rawValue]?.get(HomeLanguageDetectionResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.domain.rawValue]?.get(HomeDomainClassificationResult.self) != nil {
            payload["producedFields"] = "operation,language,domain"
            payload["mergedAgentIDs"] = "operationDetection,language,domain"
        }
        if patch.updates[ResolutionContextPatchKey.intent.rawValue]?.get(HomeIntentFamilyResult.self) != nil,
           patch.updates[ResolutionContextPatchKey.deviceType.rawValue]?.get(HomeDeviceTypeResult.self) != nil {
            payload["producedFields"] = "intent,deviceType"
            payload["mergedAgentIDs"] = "intentFamily,deviceType"
        }
        return payload
    }
}
