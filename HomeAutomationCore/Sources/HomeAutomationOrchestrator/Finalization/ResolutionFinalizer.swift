import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public struct FinalizedResolution: Sendable {
    public let result: HomeAutomationResolverResult
    public let context: ResolutionContext
    public let graph: OrchestrationGraph
    public let graphRun: GraphRunMetrics
    public let receipt: ResolutionFinalizationReceipt?

    public init(
        result: HomeAutomationResolverResult,
        context: ResolutionContext,
        graph: OrchestrationGraph,
        graphRun: GraphRunMetrics,
        receipt: ResolutionFinalizationReceipt?
    ) {
        self.result = result
        self.context = context
        self.graph = graph
        self.graphRun = graphRun
        self.receipt = receipt
    }
}

public struct ResolutionFinalizer: Sendable {
    private let registry: AgentRegistry
    private let scheduler: GraphScheduler
    private let policy: OrchestratorPolicyEngine
    private let circuitBreakers: CircuitBreakerRegistry
    private let seedBuilder: FinalizationSeedBuilder

    public init(
        registry: AgentRegistry,
        scheduler: GraphScheduler,
        policy: OrchestratorPolicyEngine,
        circuitBreakers: CircuitBreakerRegistry,
        deviceRegistry: any DeviceRegistryProtocol
    ) {
        self.registry = registry
        self.scheduler = scheduler
        self.policy = policy
        self.circuitBreakers = circuitBreakers
        self.seedBuilder = FinalizationSeedBuilder(deviceRegistry: deviceRegistry)
    }

    public func finalize(
        envelope: DraftEnvelope,
        request: CommandRequest,
        operationHint: HomeOperationDetectionResult?,
        eventBus: AgentEventBus,
        runID: UUID
    ) async -> FinalizedResolution {
        let graph = Self.graph(for: envelope.operation)
        let store = ResolutionContextStore(request: request)

        do {
            try await seedBuilder.seed(
                envelope: envelope,
                into: store,
                operationHint: operationHint
            )
        } catch {
            let context = await store.snapshot()
            let result = Self.unsupportedResult(
                envelope: envelope,
                operationHint: operationHint,
                reason: String(describing: error)
            )
            let graphRun = GraphRunMetrics(
                graphID: graph.id,
                goal: graph.goal,
                finishedAt: Date()
            )
            return FinalizedResolution(
                result: result,
                context: context,
                graph: graph,
                graphRun: graphRun,
                receipt: nil
            )
        }

        let schedulerResult = await scheduler.execute(
            graph,
            registry: registry,
            contextStore: store,
            eventBus: eventBus,
            policy: policy,
            circuitBreakers: circuitBreakers,
            runID: runID
        )
        let context = await store.snapshot()
        let graphRun = Self.enrichedGraphRun(
            schedulerResult.metrics,
            context: context,
            operation: envelope.operation
        )
        let result = Self.result(
            from: context,
            envelope: envelope,
            operationHint: operationHint,
            exit: schedulerResult.exit
        )
        let receipt = Self.receipt(
            graphRun: graphRun,
            operation: envelope.operation,
            resolution: result.resolution
        )
        let guardedResult = Self.failClosedIfActionableWithoutCompletedReceipt(
            result,
            receipt: receipt
        )
        await HomeAutomationTelemetry.shared.log(
            "orchestration.finalizer.completed",
            context: HomeAutomationTelemetryScope.current?.merging(
                graphID: graph.id,
                stage: "resolutionFinalizer"
            ),
            status: receipt?.status.rawValue ?? "not_required",
            payload: [
                "graphID": graph.id,
                "operation": envelope.operation.rawValue,
                "policyVersion": receipt?.policyVersion ?? "",
                "requiredGateIDs": receipt?.requiredGateIDs.joined(separator: ",") ?? "",
                "missingGateIDs": receipt?.missingGateIDs.joined(separator: ",") ?? "",
                "failedGateID": receipt?.failedGateID ?? "",
                "resolution": guardedResult.resolution.displaySummary
            ]
        )

        return FinalizedResolution(
            result: guardedResult,
            context: context,
            graph: graph,
            graphRun: graphRun,
            receipt: receipt
        )
    }

    private static func graph(for operation: HomeAutomationOperationKind) -> OrchestrationGraph {
        switch operation {
        case .automationCreation:
            return FinalizationGraphFactory.automationFinalizationGraph()
        default:
            return FinalizationGraphFactory.directCommandFinalizationGraph()
        }
    }

    private static func result(
        from context: ResolutionContext,
        envelope: DraftEnvelope,
        operationHint: HomeOperationDetectionResult?,
        exit: AgentRunResult?
    ) -> HomeAutomationResolverResult {
        let operation = operationHint ?? HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: envelope.operation,
            confidence: envelope.operationConfidence,
            reason: "finalized from verifier-loop envelope"
        )
        let state = state(
            context.resolutionState ?? HomeResolutionState.forOperation(text: envelope.userText, operation: operation),
            risk: context.risk,
            envelope: envelope
        )
        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: context.retrievedCandidates,
            aggregation: context.aggregation ?? HomeCandidateAggregationResult(
                finalCandidateIDs: context.selectedCandidateIDs,
                needsClarification: false,
                confidence: operation.confidence
            ),
            hydratedCandidates: context.hydratedCandidates,
            draft: context.draft,
            resolution: context.resolution ?? resolution(from: exit)
        )
    }

    private static func unsupportedResult(
        envelope: DraftEnvelope,
        operationHint: HomeOperationDetectionResult?,
        reason: String
    ) -> HomeAutomationResolverResult {
        let operation = operationHint ?? HomeOperationDetectionResult(
            domain: .homeAutomation,
            operation: envelope.operation,
            confidence: envelope.operationConfidence,
            reason: "finalization failed"
        )
        let state = state(
            HomeResolutionState.forOperation(text: envelope.userText, operation: operation),
            risk: nil,
            envelope: envelope
        )
        return HomeAutomationResolverResult(
            state: state,
            retrievedCandidates: [],
            aggregation: HomeCandidateAggregationResult(
                finalCandidateIDs: [],
                needsClarification: false,
                confidence: 0
            ),
            hydratedCandidates: [],
            draft: nil,
            resolution: .unsupported(reason)
        )
    }

    private static func state(
        _ state: HomeResolutionState,
        risk: HomeRiskClassificationResult?,
        envelope: DraftEnvelope
    ) -> HomeResolutionState {
        let finalRisk = risk ?? HomeRiskClassificationResult(
            riskLevel: envelope.risk.level,
            requiresConfirmation: envelope.risk.level == .high || envelope.risk.level == .critical,
            reason: envelope.risk.floorReason,
            confidence: envelope.fieldConfidence[.riskLevel] ?? envelope.operationConfidence
        )
        return HomeResolutionState(
            rawText: state.rawText,
            language: state.language,
            domain: state.domain,
            intent: state.intent,
            deviceType: state.deviceType,
            slots: state.slots,
            risk: finalRisk
        )
    }

    private static func receipt(
        graphRun: GraphRunMetrics,
        operation: HomeAutomationOperationKind,
        resolution: HomeCommandResolution
    ) -> ResolutionFinalizationReceipt? {
        switch operation {
        case .automationCreation:
            return ResolutionFinalizationReceipt.automationCreation(
                graphRun: graphRun,
                resolution: resolution
            )
        case .executeDeviceCommand:
            return ResolutionFinalizationReceipt.directCommand(
                graphRun: graphRun,
                resolution: resolution
            )
        default:
            return nil
        }
    }

    private static func failClosedIfActionableWithoutCompletedReceipt(
        _ result: HomeAutomationResolverResult,
        receipt: ResolutionFinalizationReceipt?
    ) -> HomeAutomationResolverResult {
        guard requiresCompletedReceipt(result.resolution),
              receipt?.status != .completed else {
            return result
        }

        let reason: String
        if let receipt {
            reason = "Finalization receipt was \(receipt.status.rawValue); refusing to emit actionable result."
        } else {
            reason = "Finalization receipt was missing; refusing to emit actionable result."
        }

        return HomeAutomationResolverResult(
            state: result.state,
            retrievedCandidates: result.retrievedCandidates,
            aggregation: result.aggregation,
            hydratedCandidates: result.hydratedCandidates,
            draft: result.draft,
            resolution: .unsupported(reason)
        )
    }

    private static func requiresCompletedReceipt(_ resolution: HomeCommandResolution) -> Bool {
        switch resolution {
        case .readyToExecute,
             .executed,
             .requiresConfirmation,
             .automationDrafted,
             .automationRequiresConfirmation:
            return true
        case .needsClarification, .unsupported:
            return false
        }
    }

    private static func enrichedGraphRun(
        _ graphRun: GraphRunMetrics,
        context: ResolutionContext,
        operation: HomeAutomationOperationKind
    ) -> GraphRunMetrics {
        guard operation == .automationCreation else { return graphRun }
        var output = graphRun

        if let aggregate = context.scopedValue(for: AutomationRuntimeContextKeys.actionResolutionAggregate) {
            for (index, result) in aggregate.results.enumerated() {
                let nodeID = "\(AgentID.automationActionResolution.rawValue):a\(index + 1)"
                output.nodeStatuses[nodeID] = result.isResolved ? .completed : .failed
                output.selectedAgents[nodeID] = AgentID.automationActionResolution.rawValue
            }
            output.subgraphRuns.append(contentsOf: aggregate.subgraphRuns)
        }

        if let records = context.scopedValue(for: AutomationRuntimeContextKeys.conditionOperandResolutionRecords) {
            for record in records {
                let nodeID = "\(AgentID.automationConditionOperandResolution.rawValue):\(record.id)"
                output.nodeStatuses[nodeID] = record.isResolved ? .completed : .failed
                output.selectedAgents[nodeID] = AgentID.automationConditionOperandResolution.rawValue
            }
        }

        return output
    }

    private static func resolution(from exit: AgentRunResult?) -> HomeCommandResolution {
        guard let exit else {
            return .unsupported("No resolution produced")
        }
        switch exit {
        case .clarification(let question):
            return .needsClarification(question)
        case .unsupported(let reason):
            return .unsupported(reason)
        case .terminalFailure(let failure), .retryableFailure(let failure):
            return .unsupported(failure.reason)
        case .success:
            return .unsupported("No resolution produced")
        }
    }
}
