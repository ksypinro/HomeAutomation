import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

/// Coordinates the end-to-end automation creation flow:
/// draft extraction → action resolution → condition resolution → validation → compilation.
///
/// This service takes a user command that has already been classified as `automationCreation`
/// and produces a `HomeAutomationResolverResult` containing the full automation plan, resolved
/// actions, and optionally compiled SmartThings JSON.
///
/// ## Flow
///
/// ```text
/// text → AutomationDraftAgent → action descriptions + trigger + conditions
///      → AutomationActionResolver (per action, reuses direct-command pipeline)
///      → AutomationConditionOperandResolver (resolves device attributes)
///      → SmartThingsRuleCompiler (deterministic JSON compilation)
///      → HomeAutomationResolverResult
/// ```
public struct AutomationCreationResolver: Sendable {
    private let logger = Logger(subsystem: "com.homeautomation.orchestrator", category: "AutomationCreationResolver")
    private let automationDraftAgent: AutomationDraftAgent
    private let actionResolver: AutomationActionResolver
    private let conditionOperandResolver: AutomationConditionOperandResolver
    private let automationValidationAgent: AutomationValidationAgent
    private let smartThingsCompiler: SmartThingsRuleCompiler
    private let smartThingsRuleCreator: (any SmartThingsRuleCreating)?

    public init(
        automationDraftAgent: AutomationDraftAgent,
        actionResolver: AutomationActionResolver,
        conditionOperandResolver: AutomationConditionOperandResolver,
        automationValidationAgent: AutomationValidationAgent,
        smartThingsCompiler: SmartThingsRuleCompiler,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) {
        self.automationDraftAgent = automationDraftAgent
        self.actionResolver = actionResolver
        self.conditionOperandResolver = conditionOperandResolver
        self.automationValidationAgent = automationValidationAgent
        self.smartThingsCompiler = smartThingsCompiler
        self.smartThingsRuleCreator = smartThingsRuleCreator
    }

    /// Resolves an automation creation request end-to-end.
    ///
    /// - Parameters:
    ///   - text: The full user command (e.g., "Turn on AC everyday at 7 AM").
    ///   - operation: The operation detection result that classified this as automation.
    ///   - eventBus: Event bus for publishing pipeline progress.
    ///   - runID: The run identifier for tracing.
    /// - Returns: A `HomeAutomationResolverResult` with the automation plan.
    public func resolve(
        text: String,
        operation: HomeOperationDetectionResult,
        creationOptions: SmartThingsRuleCreationOptions = .dryRun,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> HomeAutomationResolverResult {
        let state = HomeResolutionState.forOperation(text: text, operation: operation)

        // Step 1: Extract automation draft (trigger, conditions, action descriptions).
        let ruleDraft: HomeAutomationRuleDraft
        do {
            ruleDraft = try await extractDraft(text: text, operation: operation, eventBus: eventBus, runID: runID)
        } catch {
            logger.error("Draft extraction failed: \(error.localizedDescription, privacy: .public)")
            return Self.unsupportedResult(state: state, operation: operation, reason: error.localizedDescription)
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationDraft",
                agentID: "automationDraft",
                status: .completed,
                detail: "\(ruleDraft.actionDescriptions.count) action(s), trigger=\(ruleDraft.trigger?.displayString ?? "none")"
            )
        )

        // Step 2: Resolve condition operands to device attributes.
        let conditionOutput = await conditionOperandResolver.resolveDraft(ruleDraft)
        let resolvedRuleDraft = conditionOutput.ruleDraft
        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationConditionOperandResolution",
                agentID: "automationConditionOperandResolution",
                status: .completed,
                detail: "\(conditionOutput.records.count) condition operand(s), \(Self.conditionCount(resolvedRuleDraft.condition)) condition node(s)"
            )
        )

        // Step 3: Resolve each action description through the direct-command pipeline.
        let actionResults = await actionResolver.resolveAll(
            resolvedRuleDraft.actionDescriptions,
            eventBus: eventBus,
            runID: runID
        )

        // Step 4: Assemble resolved actions, checking for failures.
        let assemblyResult = assembleActions(
            actionResults: actionResults,
            state: state,
            operation: operation
        )

        switch assemblyResult {
        case .failure(let result):
            return result
        case .success(let assembly):
            // Step 5: Validate automation semantics before compilation.
            let validation = await validateAutomation(
                ruleDraft: resolvedRuleDraft,
                resolvedActions: assembly.resolvedActions,
                eventBus: eventBus,
                runID: runID
            )

            switch validation.status {
            case .needsClarification:
                return Self.validationClarificationResult(
                    state: state,
                    validation: validation,
                    retrievedCandidates: assembly.retrievedCandidates,
                    hydratedCandidates: assembly.hydratedCandidates,
                    selectedIDs: assembly.selectedIDs,
                    draft: assembly.firstDraft
                )
            case .unsupported:
                return Self.validationUnsupportedResult(
                    state: state,
                    operation: operation,
                    validation: validation
                )
            case .valid, .requiresConfirmation:
                break
            }

            // Step 6: Compile to SmartThings JSON and return final result.
            return await compileAndFinalize(
                ruleDraft: resolvedRuleDraft,
                resolvedActions: assembly.resolvedActions,
                retrievedCandidates: assembly.retrievedCandidates,
                hydratedCandidates: assembly.hydratedCandidates,
                selectedIDs: assembly.selectedIDs,
                firstDraft: assembly.firstDraft,
                requiresConfirmation: assembly.requiresConfirmation || validation.requiresConfirmation,
                validation: validation,
                state: state,
                operation: operation,
                creationOptions: creationOptions,
                eventBus: eventBus,
                runID: runID
            )
        }
    }

    // MARK: - Step 1: Draft Extraction

    private func extractDraft(
        text: String,
        operation: HomeOperationDetectionResult,
        eventBus: AgentEventBus,
        runID: UUID
    ) async throws -> HomeAutomationRuleDraft {
        let draftOutput = try await automationDraftAgent.run(
            AutomationDraftInput(text: text, operation: operation),
            context: ResolutionContext(
                request: CommandRequest(text: text, executeLowRiskCommands: false)
            )
        )
        return try draftOutput.makeRuleDraft()
    }

    // MARK: - Step 4: Action Assembly

    private struct ActionAssembly {
        let resolvedActions: [HomeAutomationResolvedAction]
        let retrievedCandidates: [HomeCandidateRecord]
        let hydratedCandidates: [HomeCandidateRecord]
        let selectedIDs: [String]
        let firstDraft: HomeCommandDraft?
        let requiresConfirmation: Bool
    }

    private enum AssemblyOutcome {
        case success(ActionAssembly)
        case failure(HomeAutomationResolverResult)
    }

    private func assembleActions(
        actionResults: [AutomationActionResolutionResult],
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult
    ) -> AssemblyOutcome {
        var resolvedActions: [HomeAutomationResolvedAction] = []
        var retrievedCandidates: [HomeCandidateRecord] = []
        var hydratedCandidates: [HomeCandidateRecord] = []
        var selectedIDs: [String] = []
        var firstDraft: HomeCommandDraft?
        var requiresConfirmation = false

        for (index, actionResult) in actionResults.enumerated() {
            retrievedCandidates.append(contentsOf: actionResult.retrievedCandidates)
            hydratedCandidates.append(contentsOf: actionResult.hydratedCandidates)
            selectedIDs.append(contentsOf: actionResult.selectedCandidateIDs)
            firstDraft = firstDraft ?? actionResult.draft

            if actionResult.needsClarification {
                if case .needsClarification(let question) = actionResult.resolution {
                    return .failure(Self.clarificationResult(
                        state: state,
                        operation: operation,
                        index: index,
                        question: question,
                        retrievedCandidates: retrievedCandidates,
                        hydratedCandidates: hydratedCandidates,
                        selectedIDs: selectedIDs,
                        draft: firstDraft,
                        aggregation: actionResult.aggregation
                    ))
                }
            }

            if actionResult.isUnsupported {
                if case .unsupported(let reason) = actionResult.resolution {
                    return .failure(Self.unsupportedActionResult(
                        state: state,
                        operation: operation,
                        index: index,
                        reason: reason,
                        retrievedCandidates: retrievedCandidates,
                        hydratedCandidates: hydratedCandidates,
                        selectedIDs: selectedIDs,
                        draft: firstDraft,
                        aggregation: actionResult.aggregation
                    ))
                }
            }

            guard let resolvedAction = actionResult.resolvedAction else {
                return .failure(Self.unsupportedActionResult(
                    state: state,
                    operation: operation,
                    index: index,
                    reason: "no command draft was produced",
                    retrievedCandidates: retrievedCandidates,
                    hydratedCandidates: hydratedCandidates,
                    selectedIDs: selectedIDs,
                    draft: firstDraft,
                    aggregation: actionResult.aggregation
                ))
            }

            if actionResult.requiresConfirmation {
                requiresConfirmation = true
            }

            resolvedActions.append(resolvedAction)
        }

        return .success(ActionAssembly(
            resolvedActions: resolvedActions,
            retrievedCandidates: retrievedCandidates,
            hydratedCandidates: hydratedCandidates,
            selectedIDs: selectedIDs,
            firstDraft: firstDraft,
            requiresConfirmation: requiresConfirmation
        ))
    }

    // MARK: - Step 5: Validate

    private func validateAutomation(
        ruleDraft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction],
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> AutomationValidationResult {
        let validation = (try? await automationValidationAgent.run(
            AutomationValidationInput(
                ruleDraft: ruleDraft,
                resolvedActions: resolvedActions
            ),
            context: ResolutionContext(
                request: CommandRequest(text: ruleDraft.name, executeLowRiskCommands: false)
            )
        )) ?? AutomationValidationResult(
            issues: [
                AutomationValidationIssue(
                    code: "automation.validation.failed",
                    message: "Automation validation failed.",
                    severity: .error
                )
            ],
            status: .unsupported
        )

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationValidation",
                agentID: "automationValidation",
                status: validation.isValid ? .completed : .failed,
                detail: "\(validation.status.rawValue), issues=\(validation.issues.count), requiresConfirmation=\(validation.requiresConfirmation)"
            )
        )

        return validation
    }

    // MARK: - Step 6: Compile and Finalize

    private func compileAndFinalize(
        ruleDraft: HomeAutomationRuleDraft,
        resolvedActions: [HomeAutomationResolvedAction],
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedIDs: [String],
        firstDraft: HomeCommandDraft?,
        requiresConfirmation: Bool,
        validation: AutomationValidationResult,
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult,
        creationOptions: SmartThingsRuleCreationOptions,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> HomeAutomationResolverResult {
        var plan = HomeAutomationCreationPlan(
            name: ruleDraft.name,
            ruleDraft: ruleDraft,
            resolvedActions: resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: requiresConfirmation,
            unsupportedCompilationReason: validation.unsupportedCompilationReason
        )

        let compileDetail: String
        let compiledDocument: SmartThingsRuleDocument?
        do {
            let document = try smartThingsCompiler.compile(plan)
            compiledDocument = document
            plan = HomeAutomationCreationPlan(
                name: plan.name,
                ruleDraft: plan.ruleDraft,
                resolvedActions: plan.resolvedActions,
                smartThingsRuleJSON: document.jsonString,
                requiresConfirmation: plan.requiresConfirmation,
                unsupportedCompilationReason: validation.unsupportedCompilationReason
            )
            compileDetail = "compiled"
            logger.info("SmartThings rule compiled successfully.")
        } catch {
            compiledDocument = nil
            plan = HomeAutomationCreationPlan(
                name: plan.name,
                ruleDraft: plan.ruleDraft,
                resolvedActions: plan.resolvedActions,
                smartThingsRuleJSON: nil,
                requiresConfirmation: plan.requiresConfirmation,
                unsupportedCompilationReason: validation.unsupportedCompilationReason ?? error.localizedDescription
            )
            compileDetail = error.localizedDescription
            logger.warning("SmartThings compilation failed: \(error.localizedDescription, privacy: .public)")
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "smartThingsCompilation",
                agentID: "smartThingsCompilation",
                status: plan.smartThingsRuleJSON == nil ? .skipped : .completed,
                detail: compileDetail
            )
        )

        if creationOptions.mode == .create {
            plan = await createSmartThingsRuleIfRequested(
                plan: plan,
                document: compiledDocument,
                validation: validation,
                creationOptions: creationOptions,
                eventBus: eventBus,
                runID: runID
            )
        }

        let aggregation = HomeCandidateAggregationResult(
            finalCandidateIDs: selectedIDs.stableUnique(),
            needsClarification: false,
            confidence: resolvedActions.map(\.confidence).min() ?? ruleDraft.confidence
        )

        let resolution: HomeCommandResolution = plan.requiresConfirmation
            ? .automationRequiresConfirmation(plan)
            : .automationDrafted(plan)

        let result = HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: retrievedCandidates.stableUnique(),
            aggregation: aggregation,
            hydratedCandidates: hydratedCandidates.stableUnique(),
            draft: firstDraft,
            resolution: resolution
        )

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "automationResultAssembly",
                agentID: "automationResultAssembly",
                status: .completed,
                detail: result.resolution.displaySummary
            )
        )

        return result
    }

    private func createSmartThingsRuleIfRequested(
        plan: HomeAutomationCreationPlan,
        document: SmartThingsRuleDocument?,
        validation: AutomationValidationResult,
        creationOptions: SmartThingsRuleCreationOptions,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> HomeAutomationCreationPlan {
        let output: SmartThingsRuleCreationOutput
        do {
            output = try await SmartThingsRuleCreationAgent(creator: smartThingsRuleCreator).run(
                SmartThingsRuleCreationInput(
                    plan: plan,
                    document: document,
                    validation: validation,
                    options: creationOptions
                ),
                context: ResolutionContext(
                    request: CommandRequest(
                        text: plan.name,
                        executeLowRiskCommands: false,
                        automationCreationOptions: creationOptions
                    )
                )
            )
        } catch {
            let receipt = SmartThingsRuleCreationReceipt(
                status: .failed,
                locationID: creationOptions.locationID,
                message: error.localizedDescription
            )
            output = SmartThingsRuleCreationOutput(
                plan: HomeAutomationCreationPlan(
                    name: plan.name,
                    ruleDraft: plan.ruleDraft,
                    resolvedActions: plan.resolvedActions,
                    smartThingsRuleJSON: plan.smartThingsRuleJSON,
                    requiresConfirmation: plan.requiresConfirmation,
                    unsupportedCompilationReason: plan.unsupportedCompilationReason,
                    backendResponse: receipt
                ),
                receipt: receipt,
                detail: receipt.message
            )
        }

        await eventBus.publish(
            OrchestratorPipelineEvent(
                runID: runID,
                stage: "smartThingsRuleCreation",
                agentID: "smartThingsRuleCreation",
                status: output.receipt?.status == .created ? .completed : .skipped,
                detail: output.detail
            )
        )
        return output.plan
    }

    // MARK: - Result Helpers

    private static func unsupportedResult(
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult,
        reason: String
    ) -> HomeAutomationResolverResult {
        HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: operation.confidence
            ),
            hydratedCandidates: [],
            draft: nil,
            resolution: .unsupported(reason)
        )
    }

    private static func validationClarificationResult(
        state: HomeResolutionState,
        validation: AutomationValidationResult,
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedIDs: [String],
        draft: HomeCommandDraft?
    ) -> HomeAutomationResolverResult {
        let question = validation.clarificationQuestion ??
            validation.blockingMessage ??
            "I need more information before creating this automation."
        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: retrievedCandidates,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: selectedIDs,
                needsClarification: true,
                clarificationQuestion: question,
                confidence: 0
            ),
            hydratedCandidates: hydratedCandidates,
            draft: draft,
            resolution: .needsClarification(question)
        )
    }

    private static func validationUnsupportedResult(
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult,
        validation: AutomationValidationResult
    ) -> HomeAutomationResolverResult {
        unsupportedResult(
            state: state,
            operation: operation,
            reason: validation.blockingMessage ?? "Automation is not valid."
        )
    }

    private static func clarificationResult(
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult,
        index: Int,
        question: String,
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedIDs: [String],
        draft: HomeCommandDraft?,
        aggregation: HomeCandidateAggregationResult
    ) -> HomeAutomationResolverResult {
        HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: retrievedCandidates,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: selectedIDs,
                needsClarification: true,
                clarificationQuestion: question,
                confidence: aggregation.confidence
            ),
            hydratedCandidates: hydratedCandidates,
            draft: draft,
            resolution: .needsClarification("For automation action \(index + 1): \(question)")
        )
    }

    private static func unsupportedActionResult(
        state: HomeResolutionState,
        operation: HomeOperationDetectionResult,
        index: Int,
        reason: String,
        retrievedCandidates: [HomeCandidateRecord],
        hydratedCandidates: [HomeCandidateRecord],
        selectedIDs: [String],
        draft: HomeCommandDraft?,
        aggregation: HomeCandidateAggregationResult
    ) -> HomeAutomationResolverResult {
        HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: retrievedCandidates,
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: selectedIDs,
                needsClarification: false,
                confidence: aggregation.confidence
            ),
            hydratedCandidates: hydratedCandidates,
            draft: draft,
            resolution: .unsupported("For automation action \(index + 1): \(reason)")
        )
    }



    private static func conditionCount(_ condition: HomeAutomationCondition?) -> Int {
        guard let condition else { return 0 }
        switch condition {
        case .and(let children), .or(let children):
            return children.map(conditionCount).reduce(1, +)
        case .not(let child):
            return 1 + conditionCount(child)
        case .changes(let child):
            return 1 + conditionCount(child)
        case .comparison:
            return 1
        }
    }
}
