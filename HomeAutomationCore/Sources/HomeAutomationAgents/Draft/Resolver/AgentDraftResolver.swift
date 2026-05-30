import Foundation
import HomeAutomationCore
import os

/// Retry wrapper around draft generation packages.
///
/// `AgentDraftResolver` tries strategy variants in order:
/// 1. `base/full` — Base model, full prompt
/// 2. `adapter/full` — Adapter model, full prompt, only when configured
/// 3. `base/simplified` — Base model, simplified prompt
/// 4. `adapter/simplified` — Adapter model, simplified prompt, only when configured
///
/// The first attempt exceeding the confidence threshold is returned immediately.
/// If no attempt exceeds the threshold, the highest-confidence result is selected.
public struct AgentDraftResolver: HomeCommandDraftResolving {
    private let resolver: any HomeCommandDraftResolving
    private let adapterProvider: HomeAdapterModelProvider
    private let confidenceThreshold: Double
    private let metrics: AgentDraftResolverMetrics?
    private let logger = Logger(subsystem: "HomeAutomation", category: "Draft.AgentResolver")

    public init(
        adapterProvider: HomeAdapterModelProvider = HomeAdapterModelProvider(),
        confidenceThreshold: Double = 0.70,
        metrics: AgentDraftResolverMetrics? = nil,
        resolver: (any HomeCommandDraftResolving)? = nil
    ) {
        self.adapterProvider = adapterProvider
        self.resolver = resolver ?? FoundationHomeCommandDraftResolver(adapterProvider: adapterProvider)
        self.confidenceThreshold = confidenceThreshold
        self.metrics = metrics
    }

    public func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        let output = try await resolveDraftWithReport(from: package)
        await metrics?.store(output.report)
        return output.draft
    }

    public func resolveDraftWithReport(from package: HomeModelInstructionPackage) async throws -> AgentDraftResolutionOutput {
        var lastError: Error?
        var bestDraft: HomeCommandDraft?
        var bestAttemptIndex: Int?
        var attempts: [AgentDraftAttemptReport] = []
        var adapterAttemptsDisabled = !adapterProvider.hasConfiguredAdapter

        for descriptor in retryDescriptors {
            guard !descriptor.useAdapter || !adapterAttemptsDisabled else { continue }
            let candidate = makeAttempt(
                from: package,
                name: descriptor.name,
                useAdapter: descriptor.useAdapter,
                simplifyPrompt: descriptor.simplifiedPrompt
            )
            
            logger.debug("[resolveDraftWithReport] Attempting strategy: \(candidate.name, privacy: .public)")
            do {
                let draft = try await resolver.resolveDraft(from: candidate.package)
                if draft.confidence >= confidenceThreshold {
                    logger.debug("[resolveDraftWithReport] Strategy \(candidate.name, privacy: .public) succeeded with confidence: \(draft.confidence)")
                    attempts.append(
                        AgentDraftAttemptReport(
                            name: candidate.name,
                            useAdapter: candidate.useAdapter,
                            simplifiedPrompt: candidate.simplifiedPrompt,
                            outcome: "success",
                            confidence: draft.confidence,
                            selected: true,
                            errorDescription: nil
                        )
                    )
                    return AgentDraftResolutionOutput(
                        draft: draft,
                        report: AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: candidate.name)
                    )
                }
                logger.debug("[resolveDraftWithReport] Strategy \(candidate.name, privacy: .public) yielded low confidence: \(draft.confidence)")
                if bestDraft.map({ draft.confidence > $0.confidence }) ?? true {
                    bestDraft = draft
                    bestAttemptIndex = attempts.count
                }
                attempts.append(
                    AgentDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "low-confidence",
                        confidence: draft.confidence,
                        selected: false,
                        errorDescription: nil
                    )
                )
            } catch {
                lastError = error
                let errorKind = FoundationModelDiagnostics.failureKind(for: error)
                logger.error("[resolveDraftWithReport] Strategy \(candidate.name, privacy: .public) failed with error: \(error.localizedDescription, privacy: .public)")
                if candidate.useAdapter, errorKind == .adapterUnavailable {
                    adapterAttemptsDisabled = true
                    logger.info("[resolveDraftWithReport] Disabling adapter attempts due to unavailability.")
                }
                attempts.append(
                    AgentDraftAttemptReport(
                        name: candidate.name,
                        useAdapter: candidate.useAdapter,
                        simplifiedPrompt: candidate.simplifiedPrompt,
                        outcome: "error",
                        confidence: nil,
                        selected: false,
                        errorDescription: error.localizedDescription,
                        errorKind: errorKind
                    )
                )
            }
        }

        if let bestDraft, let bestAttemptIndex {
            attempts[bestAttemptIndex] = attempts[bestAttemptIndex].selecting()
            return AgentDraftResolutionOutput(
                draft: bestDraft,
                report: AgentDraftResolutionReport(
                    attempts: attempts,
                    selectedAttemptName: attempts[bestAttemptIndex].name
                )
            )
        }

        if let fallbackDraft = deterministicFallbackDraft(from: package) {
            let lastErrorKind = lastError.map { FoundationModelDiagnostics.failureKind(for: $0) }
            logger.info("[resolveDraftWithReport] Using deterministic draft fallback after model attempts failed.")
            attempts.append(
                AgentDraftAttemptReport(
                    name: "deterministic/fallback",
                    useAdapter: false,
                    simplifiedPrompt: false,
                    outcome: "fallback",
                    confidence: fallbackDraft.confidence,
                    selected: true,
                    errorDescription: lastError?.localizedDescription,
                    errorKind: lastErrorKind
                )
            )
            return AgentDraftResolutionOutput(
                draft: fallbackDraft,
                report: AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: "deterministic/fallback")
            )
        }

        let report = AgentDraftResolutionReport(attempts: attempts, selectedAttemptName: nil)
        await metrics?.store(report)
        throw lastError ?? FoundationLabCoreError.invalidRequest("Agent draft resolver failed")
    }

    private var retryDescriptors: [AgentDraftAttemptDescriptor] {
        [
            AgentDraftAttemptDescriptor(name: "base/full", useAdapter: false, simplifiedPrompt: false),
            AgentDraftAttemptDescriptor(name: "adapter/full", useAdapter: true, simplifiedPrompt: false),
            AgentDraftAttemptDescriptor(name: "base/simplified", useAdapter: false, simplifiedPrompt: true),
            AgentDraftAttemptDescriptor(name: "adapter/simplified", useAdapter: true, simplifiedPrompt: true)
        ]
    }

    private func makeAttempt(
        from package: HomeModelInstructionPackage,
        name: String,
        useAdapter: Bool,
        simplifyPrompt: Bool
    ) -> AgentDraftPackageAttempt {
        AgentDraftPackageAttempt(
            name: name,
            useAdapter: useAdapter,
            simplifiedPrompt: simplifyPrompt,
            package: HomeModelInstructionPackage(
                instructions: package.instructions,
                instructionText: package.instructionText,
                prompt: simplifyPrompt ? simplifiedPrompt(from: package.prompt) : package.prompt,
                tools: package.tools,
                useAdapter: useAdapter,
                generationMode: package.generationMode,
                contextBudgetReport: package.contextBudgetReport,
                deterministicFallbackInput: package.deterministicFallbackInput
            )
        )
    }

    private func simplifiedPrompt(from prompt: String) -> String {
        """
        Resolve the smart-home command using only the hydrated candidate IDs, capabilities, and commands in this prompt.
        Return a single HomeCommandDraft. If the target or command is ambiguous, set needsClarification true.

        \(prompt)
        """
    }

    private func deterministicFallbackDraft(from package: HomeModelInstructionPackage) -> HomeCommandDraft? {
        guard let input = package.deterministicFallbackInput,
              let decision = input.capabilityDecision,
              let capability = decision.selectedCapability,
              let command = decision.selectedCommand else {
            return nil
        }

        let targetDeviceID = decision.targetDeviceID ?? input.aggregation.finalCandidateIDs.first
        guard let targetDeviceID,
              let device = input.hydratedCandidates.first(where: { $0.id == targetDeviceID }) else {
            return nil
        }

        let supportedCommands = device.supportedCommands[capability, default: HomeCapabilityRegistry.supportedCommands(for: capability)]
        guard device.capabilities.contains(capability),
              supportedCommands.contains(command) else {
            return nil
        }

        let parameters = Self.parameters(for: command, state: input.resolutionState)
        guard HomeParameterValidator.validate(parameters, capability: capability, command: command, device: device) else {
            return nil
        }

        let intent = Self.intent(for: command, state: input.resolutionState)
        let requiresConfirmation = input.resolutionState.risk.requiresConfirmation ||
            HomeRiskPolicy.requiresConfirmation(
                intent: intent,
                capability: capability,
                deviceType: device.deviceType,
                candidateRisk: device.riskLevel,
                command: command
            )

        return HomeCommandDraft(
            intent: intent,
            targetDeviceID: targetDeviceID,
            capability: capability,
            command: command,
            parameters: parameters,
            needsClarification: input.aggregation.needsClarification,
            clarificationQuestion: input.aggregation.clarificationQuestion,
            requiresConfirmation: requiresConfirmation,
            confidence: min(max(decision.confidence, input.aggregation.confidence), 0.95)
        )
    }

    private static func intent(for command: String, state: HomeResolutionState) -> HomeAutomationIntent {
        switch command {
        case "on":
            return .turnOn
        case "off":
            return .turnOff
        case "getStatus", "refresh":
            return .getStatus
        case "open":
            return .open
        case "close":
            return .close
        case "lock":
            return .lock
        case "unlock":
            return .unlock
        case "run":
            return .runRoutine
        case "start", "startStream":
            return .start
        case "stop", "stopStream":
            return .stop
        case "pause":
            return .pause
        case "resume":
            return .resume
        case "increaseValue", "volumeUp", "channelUp":
            return .increaseValue
        case "decreaseValue", "volumeDown", "channelDown":
            return .decreaseValue
        default:
            if state.intent.topFamilies.contains(.statusQuery) {
                return .getStatus
            }
            if command.hasPrefix("set") {
                return .setValue
            }
            return .unsupported
        }
    }

    private static func parameters(for command: String, state: HomeResolutionState) -> [HomeResolvedParameter] {
        guard commandRequiresParameters(command) else { return [] }

        let valueParameters = state.slots.values.map {
            HomeResolvedParameter(
                name: $0.name,
                value: $0.numericValue == nil ? $0.rawValue : nil,
                numericValue: $0.numericValue,
                unit: $0.unit,
                confidence: $0.confidence
            )
        }
        if !valueParameters.isEmpty {
            return valueParameters
        }

        return state.slots.modes.map {
            HomeResolvedParameter(name: "mode", value: $0, confidence: state.slots.confidence)
        }
    }

    private static func commandRequiresParameters(_ command: String) -> Bool {
        switch command {
        case "setLevel", "setColorTemperature", "setHue", "setSaturation",
             "setCoolingSetpoint", "setHeatingSetpoint", "setShadeLevel",
             "setVolume", "setChannel", "setOvenSetpoint", "increaseValue",
             "decreaseValue", "setRotation", "setColor", "setFanMode",
             "setThermostatFanMode", "setThermostatMode", "setAirConditionerMode",
             "setAirPurifierFanMode", "setInputSource", "setWasherMode",
             "setDryerMode", "setOvenMode", "setRobotCleanerCleaningMode",
             "setMode", "setCookMode", "arm", "disarm":
            return true
        default:
            return false
        }
    }
}

private struct AgentDraftPackageAttempt {
    let name: String
    let useAdapter: Bool
    let simplifiedPrompt: Bool
    let package: HomeModelInstructionPackage
}

private struct AgentDraftAttemptDescriptor {
    let name: String
    let useAdapter: Bool
    let simplifiedPrompt: Bool
}
