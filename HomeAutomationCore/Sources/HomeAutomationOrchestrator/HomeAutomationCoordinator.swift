import Foundation
import FoundationModels
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG

public protocol HomeAutomationCoordinating: Sendable {
    var deviceCoordinator: DeviceCoordinator { get }
    var graphCoordinator: GraphCoordinator { get }
    var resolutionCoordinator: ResolutionCoordinator { get }
    var automationCoordinator: AutomationCoordinator { get }
    var smartThingsCoordinator: SmartThingsCoordinator { get }
    var ragCoordinator: RAGCoordinator { get }
    var observabilityCoordinator: ObservabilityCoordinator { get }
    var agentCoordinator: AgentCoordinator { get }

    func makeRuntimeDependencies() -> HomeAutomationRuntimeDependencies
    func makeOrchestrator() -> HomeCommandOrchestrator
}

public protocol DeviceCoordinating: Sendable {
    var deviceRegistry: any DeviceRegistryProtocol { get }
}

public protocol GraphCoordinating: Sendable {
    var policy: OrchestratorPolicyEngine { get }
    var graphPlanner: GraphPlanner { get }
    var scheduler: GraphScheduler { get }
    var subgraphRunner: GraphSubgraphRunner { get }
    var circuitBreakers: CircuitBreakerRegistry { get }
}

public protocol ResolutionCoordinating: Sendable {
    var constructionServices: HomeAutomationAgentConstructionServices { get }
}

public protocol AutomationCoordinating: Sendable {
    var componentSegmentationAgent: AutomationComponentSegmentationAgent { get }
    var triggerResolutionAgent: AutomationTriggerResolutionAgent { get }
    var conditionClauseResolutionAgent: AutomationConditionClauseResolutionAgent { get }
    var validationPolicy: AutomationValidationPolicy { get }

    func makeActionResolver(
        agentRegistry: AgentRegistry,
        graphCoordinator: GraphCoordinator,
        deviceRegistry: (any DeviceRegistryProtocol)?
    ) -> AutomationActionResolver

    func makeComponentFanOutRunner(
        agentRegistry: AgentRegistry,
        graphCoordinator: GraphCoordinator,
        deviceRegistry: any DeviceRegistryProtocol
    ) -> AutomationComponentFanOutRunner
}

public protocol SmartThingsCoordinating: Sendable {
    var smartThingsRuleCreator: (any SmartThingsRuleCreating)? { get }
    var ruleCompiler: SmartThingsRuleCompiler { get }
    var restClient: SmartThingsRESTClient? { get }
    var restDeviceRegistry: SmartThingsDeviceRegistry? { get }
}

public protocol RAGCoordinating: Sendable {
    func makeKnowledgeIndexer(cache: VectorIndexCache?) -> KnowledgeIndexer
}

public protocol ObservabilityCoordinating: Sendable {
    var metricsCollector: OrchestratorMetricsCollector { get }
    var conversationMemory: ConversationMemory { get }
}

public protocol AgentCoordinating: Sendable {
    func makeAgentRegistry() -> AgentRegistry
}

public typealias HomeAutomationRootCoordinator = HomeAutomationCoordinator

public struct DeviceCoordinator: DeviceCoordinating {
    public let deviceRegistry: any DeviceRegistryProtocol

    public init(deviceRegistry: (any DeviceRegistryProtocol)? = nil) {
        self.deviceRegistry = deviceRegistry ?? Self.makeMockDeviceRegistry()
    }

    public static func makeMockDeviceRegistry(
        devices: [HomeCandidateRecord]? = nil
    ) -> MockHomeDeviceRegistry {
        if let devices {
            return MockHomeDeviceRegistry(devices: devices)
        }
        return MockHomeDeviceRegistry()
    }
}

public struct GraphCoordinator: GraphCoordinating {
    public let policy: OrchestratorPolicyEngine
    public let graphPlanner: GraphPlanner
    public let scheduler: GraphScheduler
    public let subgraphRunner: GraphSubgraphRunner
    public let circuitBreakers: CircuitBreakerRegistry

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool,
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        scheduler: GraphScheduler? = nil,
        circuitBreakers: CircuitBreakerRegistry? = nil
    ) {
        let policy = OrchestratorPolicyEngine(
            isModelAvailable: foundationModelAvailability,
            modelAvailabilityStatus: foundationModelAvailabilityStatus
        )
        let scheduler = scheduler ?? GraphScheduler()
        self.policy = policy
        self.graphPlanner = GraphPlanner(policy: policy)
        self.scheduler = scheduler
        self.subgraphRunner = GraphSubgraphRunner(scheduler: scheduler)
        self.circuitBreakers = circuitBreakers ?? CircuitBreakerRegistry()
    }

    public init(
        policy: OrchestratorPolicyEngine,
        graphPlanner: GraphPlanner,
        scheduler: GraphScheduler,
        circuitBreakers: CircuitBreakerRegistry
    ) {
        self.policy = policy
        self.graphPlanner = graphPlanner
        self.scheduler = scheduler
        self.subgraphRunner = GraphSubgraphRunner(scheduler: scheduler)
        self.circuitBreakers = circuitBreakers
    }
}

public struct ObservabilityCoordinator: ObservabilityCoordinating {
    public let metricsCollector: OrchestratorMetricsCollector
    public let conversationMemory: ConversationMemory

    public init(
        metricsCollector: OrchestratorMetricsCollector? = nil,
        conversationMemory: ConversationMemory? = nil
    ) {
        self.metricsCollector = metricsCollector ?? OrchestratorMetricsCollector()
        self.conversationMemory = conversationMemory ?? ConversationMemory()
    }
}

public struct SmartThingsCoordinator: SmartThingsCoordinating {
    public let smartThingsRuleCreator: (any SmartThingsRuleCreating)?
    public let ruleCompiler: SmartThingsRuleCompiler
    public let restClient: SmartThingsRESTClient?
    public let restDeviceRegistry: SmartThingsDeviceRegistry?

    public init(
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil,
        ruleCompiler: SmartThingsRuleCompiler = SmartThingsRuleCompiler(),
        restClient: SmartThingsRESTClient? = nil,
        restDeviceRegistry: SmartThingsDeviceRegistry? = nil
    ) {
        self.smartThingsRuleCreator = smartThingsRuleCreator
        self.ruleCompiler = ruleCompiler
        self.restClient = restClient
        self.restDeviceRegistry = restDeviceRegistry
    }
}

public struct RAGCoordinator: RAGCoordinating {
    public init() {}

    public func makeKnowledgeIndexer(cache: VectorIndexCache? = nil) -> KnowledgeIndexer {
        KnowledgeIndexer(
            chunker: DocumentChunker(),
            embeddingProvider: TFIDFEmbeddingProvider(),
            vectorStore: VectorStore(),
            bm25Index: BM25Index(),
            cache: cache
        )
    }
}

/// Dependency package passed to the agent factory.
///
/// This keeps agent construction protocol-driven while avoiding ad-hoc dependency creation
/// inside call sites such as `HomeCommandOrchestrator`.
public struct HomeAutomationAgentFactoryDependencies: Sendable {
    public let deviceRegistry: any DeviceRegistryProtocol
    public let contextRetriever: ContextRetriever?
    public let foundationModelAvailability: @Sendable () -> Bool
    public let policy: OrchestratorPolicyEngine
    public let graphPlanner: GraphPlanner
    public let graphCoordinator: GraphCoordinator
    public let scheduler: GraphScheduler
    public let circuitBreakers: CircuitBreakerRegistry
    public let constructionServices: HomeAutomationAgentConstructionServices
    public let automationCoordinator: AutomationCoordinator
    public let smartThingsCoordinator: SmartThingsCoordinator
    public let smartThingsRuleCreator: (any SmartThingsRuleCreating)?

    public init(
        deviceRegistry: any DeviceRegistryProtocol,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool,
        policy: OrchestratorPolicyEngine,
        graphPlanner: GraphPlanner,
        graphCoordinator: GraphCoordinator,
        scheduler: GraphScheduler,
        circuitBreakers: CircuitBreakerRegistry,
        constructionServices: HomeAutomationAgentConstructionServices,
        automationCoordinator: AutomationCoordinator,
        smartThingsCoordinator: SmartThingsCoordinator,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil
    ) {
        self.deviceRegistry = deviceRegistry
        self.contextRetriever = contextRetriever
        self.foundationModelAvailability = foundationModelAvailability
        self.policy = policy
        self.graphPlanner = graphPlanner
        self.graphCoordinator = graphCoordinator
        self.scheduler = scheduler
        self.circuitBreakers = circuitBreakers
        self.constructionServices = constructionServices
        self.automationCoordinator = automationCoordinator
        self.smartThingsCoordinator = smartThingsCoordinator
        self.smartThingsRuleCreator = smartThingsRuleCreator
    }

    /// Returns a copy of these dependencies with a different automation coordinator.
    public func replacingAutomationCoordinator(
        _ automationCoordinator: AutomationCoordinator
    ) -> HomeAutomationAgentFactoryDependencies {
        HomeAutomationAgentFactoryDependencies(
            deviceRegistry: deviceRegistry,
            contextRetriever: contextRetriever,
            foundationModelAvailability: foundationModelAvailability,
            policy: policy,
            graphPlanner: graphPlanner,
            graphCoordinator: graphCoordinator,
            scheduler: scheduler,
            circuitBreakers: circuitBreakers,
            constructionServices: constructionServices,
            automationCoordinator: automationCoordinator,
            smartThingsCoordinator: smartThingsCoordinator,
            smartThingsRuleCreator: smartThingsRuleCreator
        )
    }
}

/// Coordinator-created collaborators used by the default agent registry factory.
public struct HomeAutomationAgentConstructionServices: Sendable {
    public let candidateResolver: HomeCandidateResolverSupport
    public let toolProvider: AgentToolProvider
    public let instructionFactory: AgentInstructionSetFactory
    public let draftResolver: AgentDraftResolver
    public let commandValidator: AgentCommandValidator
    public let ruleResolver: AgentRuleBasedResolver
    public let bixbyMapper: AgentBixbyFallbackMapper
    public let executor: AgentPlanExecutor

    public init(
        deviceRegistry: any DeviceRegistryProtocol,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool
    ) {
        let adapterProvider = HomeAdapterModelProvider()
        let promptBuilder = CandidateResolutionPromptBuilder(
            budgeter: FoundationModelContextBudgeter()
        )
        self.candidateResolver = HomeCandidateResolverSupport(
            promptBuilder: promptBuilder,
            foundationModelAvailability: foundationModelAvailability
        )
        self.toolProvider = AgentToolProvider(registry: deviceRegistry)
        self.instructionFactory = AgentInstructionSetFactory(
            toolProvider: toolProvider,
            contextRetriever: contextRetriever
        )
        self.draftResolver = AgentDraftResolver(
            adapterProvider: adapterProvider,
            resolver: FoundationHomeCommandDraftResolver(adapterProvider: adapterProvider)
        )
        self.commandValidator = AgentCommandValidator()
        self.bixbyMapper = AgentBixbyFallbackMapper()
        self.executor = AgentPlanExecutor(registry: deviceRegistry)
        self.ruleResolver = AgentRuleBasedResolver(
            registry: deviceRegistry,
            validator: commandValidator,
            executor: executor,
            bixbyFallbackMapper: bixbyMapper,
            contextRetriever: contextRetriever
        )
    }
}

public struct ResolutionCoordinator: ResolutionCoordinating {
    public let constructionServices: HomeAutomationAgentConstructionServices

    public init(
        deviceRegistry: any DeviceRegistryProtocol,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool
    ) {
        self.constructionServices = HomeAutomationAgentConstructionServices(
            deviceRegistry: deviceRegistry,
            contextRetriever: contextRetriever,
            foundationModelAvailability: foundationModelAvailability
        )
    }
}

public struct AutomationCoordinator: AutomationCoordinating {
    public let componentSegmentationAgent: AutomationComponentSegmentationAgent
    public let triggerResolutionAgent: AutomationTriggerResolutionAgent
    public let conditionClauseResolutionAgent: AutomationConditionClauseResolutionAgent
    public let validationPolicy: AutomationValidationPolicy
    private let foundationModelAvailability: @Sendable () -> Bool
    private let contextRetriever: ContextRetriever?
    private let useMiniPipeline: Bool

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool,
        contextRetriever: ContextRetriever? = nil,
        validationPolicy: AutomationValidationPolicy = AutomationValidationPolicy(),
        useMiniPipeline: Bool = false
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.contextRetriever = contextRetriever
        self.useMiniPipeline = useMiniPipeline
        self.componentSegmentationAgent = AutomationComponentSegmentationAgent(
            worker: AutomationComponentSegmentationWorkerSession(
                foundationModelAvailability: foundationModelAvailability
            )
        )
        self.triggerResolutionAgent = AutomationTriggerResolutionAgent(
            worker: AutomationTriggerResolutionWorkerSession(
                foundationModelAvailability: foundationModelAvailability
            )
        )
        self.conditionClauseResolutionAgent = AutomationConditionClauseResolutionAgent(
            worker: AutomationConditionClauseResolutionWorkerSession(
                foundationModelAvailability: foundationModelAvailability
            )
        )
        self.validationPolicy = validationPolicy
    }

    /// Returns a copy of this coordinator with the Tier 1 mini-pipeline flag set.
    public func withMiniPipeline(_ enabled: Bool) -> AutomationCoordinator {
        AutomationCoordinator(
            foundationModelAvailability: foundationModelAvailability,
            contextRetriever: contextRetriever,
            validationPolicy: validationPolicy,
            useMiniPipeline: enabled
        )
    }

    public func makeAutomationDraftAgent() -> AutomationDraftAgent {
        AutomationDraftAgent(
            worker: AutomationDraftWorkerSession(
                foundationModelAvailability: foundationModelAvailability,
                parser: AutomationPatternParser(),
                contextRetriever: contextRetriever
            )
        )
    }

    public func makeDraftExtractionAgent() -> AutomationDraftExtractionAgent {
        AutomationDraftExtractionAgent(draftAgent: makeAutomationDraftAgent())
    }

    public func makeConditionOperandResolver(
        registry: any DeviceRegistryProtocol
    ) -> AutomationConditionOperandResolver {
        AutomationConditionOperandResolver(
            registry: registry,
            foundationModelAvailability: foundationModelAvailability
        )
    }

    public func makeActionResolver(
        agentRegistry: AgentRegistry,
        graphCoordinator: GraphCoordinator,
        deviceRegistry: (any DeviceRegistryProtocol)? = nil
    ) -> AutomationActionResolver {
        let mini: AutomationActionMiniPipeline?
        if useMiniPipeline, let deviceRegistry {
            mini = AutomationActionMiniPipeline(
                registry: deviceRegistry,
                validator: AgentCommandValidator(),
                fragmentNLU: FragmentNLUWorkerSession(
                    foundationModelAvailability: foundationModelAvailability
                ),
                capabilityWorker: CapabilityResolutionWorker(
                    foundationModelAvailability: foundationModelAvailability
                )
            )
        } else {
            mini = nil
        }

        return AutomationActionResolver(
            registry: agentRegistry,
            graphPlanner: graphCoordinator.graphPlanner,
            policy: graphCoordinator.policy,
            scheduler: graphCoordinator.scheduler,
            subgraphRunner: graphCoordinator.subgraphRunner,
            circuitBreakers: graphCoordinator.circuitBreakers,
            miniPipeline: mini
        )
    }

    public func makeComponentFanOutRunner(
        agentRegistry: AgentRegistry,
        graphCoordinator: GraphCoordinator,
        deviceRegistry: any DeviceRegistryProtocol
    ) -> AutomationComponentFanOutRunner {
        AutomationComponentFanOutRunner(
            triggerAgent: triggerResolutionAgent,
            conditionAgent: conditionClauseResolutionAgent,
            actionResolver: makeActionResolver(
                agentRegistry: agentRegistry,
                graphCoordinator: graphCoordinator,
                deviceRegistry: deviceRegistry
            ),
            registry: deviceRegistry
        )
    }
}

public struct AgentCoordinator: AgentCoordinating {
    private let registryFactory: any HomeAutomationAgentRegistryFactory
    private let dependencies: HomeAutomationAgentFactoryDependencies

    public init(
        registryFactory: any HomeAutomationAgentRegistryFactory,
        dependencies: HomeAutomationAgentFactoryDependencies
    ) {
        self.registryFactory = registryFactory
        self.dependencies = dependencies
    }

    public func makeAgentRegistry() -> AgentRegistry {
        registryFactory.makeAgentRegistry(dependencies: dependencies)
    }

    /// Builds a registry whose automation agents use the given coordinator
    /// (e.g. one with the Tier 1 mini-pipeline flag enabled).
    public func makeAgentRegistry(
        automationCoordinator: AutomationCoordinator
    ) -> AgentRegistry {
        registryFactory.makeAgentRegistry(
            dependencies: dependencies.replacingAutomationCoordinator(automationCoordinator)
        )
    }
}

/// Protocol abstraction for building agent registries.
public protocol HomeAutomationAgentRegistryFactory: Sendable {
    func makeAgentRegistry(
        dependencies: HomeAutomationAgentFactoryDependencies
    ) -> AgentRegistry
}

/// Default adapter over the existing static registry factory.
public struct DefaultHomeAutomationAgentRegistryFactory: HomeAutomationAgentRegistryFactory {
    public init() {}

    public func makeAgentRegistry(
        dependencies: HomeAutomationAgentFactoryDependencies
    ) -> AgentRegistry {
        DefaultAgentRegistryFactory.make(
            registry: dependencies.deviceRegistry,
            contextRetriever: dependencies.contextRetriever,
            foundationModelAvailability: dependencies.foundationModelAvailability,
            smartThingsRuleCreator: dependencies.smartThingsRuleCreator,
            graphCoordinator: dependencies.graphCoordinator,
            scheduler: dependencies.scheduler,
            circuitBreakers: dependencies.circuitBreakers,
            constructionServices: dependencies.constructionServices,
            automationCoordinator: dependencies.automationCoordinator,
            smartThingsCoordinator: dependencies.smartThingsCoordinator
        )
    }
}

/// Fully assembled runtime dependencies consumed by `HomeCommandOrchestrator`.
public struct HomeAutomationRuntimeDependencies: Sendable {
    public let agentRegistry: AgentRegistry
    public let graphPlanner: GraphPlanner
    public let policy: OrchestratorPolicyEngine
    public let scheduler: GraphScheduler
    public let metricsCollector: OrchestratorMetricsCollector
    public let conversationMemory: ConversationMemory
    public let circuitBreakers: CircuitBreakerRegistry
    public let deviceRegistry: any DeviceRegistryProtocol
    public let smartThingsRuleCreator: (any SmartThingsRuleCreating)?
    public let orchestrationMode: OrchestrationMode
    public let loopOrchestrator: VerifierLoopOrchestrator?

    public init(
        agentRegistry: AgentRegistry,
        graphPlanner: GraphPlanner,
        policy: OrchestratorPolicyEngine,
        scheduler: GraphScheduler,
        metricsCollector: OrchestratorMetricsCollector,
        conversationMemory: ConversationMemory,
        circuitBreakers: CircuitBreakerRegistry,
        deviceRegistry: any DeviceRegistryProtocol,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil,
        orchestrationMode: OrchestrationMode = .graph,
        loopOrchestrator: VerifierLoopOrchestrator? = nil
    ) {
        self.agentRegistry = agentRegistry
        self.graphPlanner = graphPlanner
        self.policy = policy
        self.scheduler = scheduler
        self.metricsCollector = metricsCollector
        self.conversationMemory = conversationMemory
        self.circuitBreakers = circuitBreakers
        self.deviceRegistry = deviceRegistry
        self.smartThingsRuleCreator = smartThingsRuleCreator
        self.orchestrationMode = orchestrationMode
        self.loopOrchestrator = loopOrchestrator
    }
}

/// Composition root for the home automation runtime.
///
/// The coordinator is intentionally instance-scoped. It is not a singleton and does not own
/// per-run mutable state; it centralizes construction of long-lived services and propagates
/// those dependencies into the orchestrator and agent registry.
public final class HomeAutomationCoordinator: HomeAutomationCoordinating, Sendable {
    public let deviceCoordinator: DeviceCoordinator
    public let graphCoordinator: GraphCoordinator
    public let resolutionCoordinator: ResolutionCoordinator
    public let automationCoordinator: AutomationCoordinator
    public let smartThingsCoordinator: SmartThingsCoordinator
    public let ragCoordinator: RAGCoordinator
    public let observabilityCoordinator: ObservabilityCoordinator
    public let agentCoordinator: AgentCoordinator

    public let contextRetriever: ContextRetriever?
    public let foundationModelAvailability: @Sendable () -> Bool
    public let foundationModelAvailabilityStatus: @Sendable () -> String?

    public var deviceRegistry: any DeviceRegistryProtocol { deviceCoordinator.deviceRegistry }
    public var policy: OrchestratorPolicyEngine { graphCoordinator.policy }
    public var graphPlanner: GraphPlanner { graphCoordinator.graphPlanner }
    public var scheduler: GraphScheduler { graphCoordinator.scheduler }
    public var metricsCollector: OrchestratorMetricsCollector { observabilityCoordinator.metricsCollector }
    public var conversationMemory: ConversationMemory { observabilityCoordinator.conversationMemory }
    public var circuitBreakers: CircuitBreakerRegistry { graphCoordinator.circuitBreakers }
    public var smartThingsRuleCreator: (any SmartThingsRuleCreating)? { smartThingsCoordinator.smartThingsRuleCreator }

    public init(
        deviceRegistry: (any DeviceRegistryProtocol)? = nil,
        contextRetriever: ContextRetriever? = nil,
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        foundationModelAvailabilityStatus: @escaping @Sendable () -> String? = { nil },
        metricsCollector: OrchestratorMetricsCollector? = nil,
        conversationMemory: ConversationMemory? = nil,
        circuitBreakers: CircuitBreakerRegistry? = nil,
        smartThingsRuleCreator: (any SmartThingsRuleCreating)? = nil,
        scheduler: GraphScheduler? = nil,
        agentRegistryFactory: any HomeAutomationAgentRegistryFactory = DefaultHomeAutomationAgentRegistryFactory()
    ) {
        self.contextRetriever = contextRetriever
        self.foundationModelAvailability = foundationModelAvailability
        self.foundationModelAvailabilityStatus = foundationModelAvailabilityStatus

        let deviceCoordinator = DeviceCoordinator(deviceRegistry: deviceRegistry)
        let graphCoordinator = GraphCoordinator(
            foundationModelAvailability: foundationModelAvailability,
            foundationModelAvailabilityStatus: foundationModelAvailabilityStatus,
            scheduler: scheduler,
            circuitBreakers: circuitBreakers
        )
        let resolutionCoordinator = ResolutionCoordinator(
            deviceRegistry: deviceCoordinator.deviceRegistry,
            contextRetriever: contextRetriever,
            foundationModelAvailability: foundationModelAvailability
        )
        let automationCoordinator = AutomationCoordinator(
            foundationModelAvailability: foundationModelAvailability,
            contextRetriever: contextRetriever
        )
        let smartThingsCoordinator = SmartThingsCoordinator(
            smartThingsRuleCreator: smartThingsRuleCreator
        )
        let observabilityCoordinator = ObservabilityCoordinator(
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory
        )
        let ragCoordinator = RAGCoordinator()
        let agentDependencies = HomeAutomationAgentFactoryDependencies(
            deviceRegistry: deviceCoordinator.deviceRegistry,
            contextRetriever: contextRetriever,
            foundationModelAvailability: foundationModelAvailability,
            policy: graphCoordinator.policy,
            graphPlanner: graphCoordinator.graphPlanner,
            graphCoordinator: graphCoordinator,
            scheduler: graphCoordinator.scheduler,
            circuitBreakers: graphCoordinator.circuitBreakers,
            constructionServices: resolutionCoordinator.constructionServices,
            automationCoordinator: automationCoordinator,
            smartThingsCoordinator: smartThingsCoordinator,
            smartThingsRuleCreator: smartThingsCoordinator.smartThingsRuleCreator
        )
        self.deviceCoordinator = deviceCoordinator
        self.graphCoordinator = graphCoordinator
        self.resolutionCoordinator = resolutionCoordinator
        self.automationCoordinator = automationCoordinator
        self.smartThingsCoordinator = smartThingsCoordinator
        self.ragCoordinator = ragCoordinator
        self.observabilityCoordinator = observabilityCoordinator
        self.agentCoordinator = AgentCoordinator(
            registryFactory: agentRegistryFactory,
            dependencies: agentDependencies
        )
    }

    public func makeAgentRegistry() -> AgentRegistry {
        agentCoordinator.makeAgentRegistry()
    }

    public func makeRuntimeDependencies() -> HomeAutomationRuntimeDependencies {
        HomeAutomationRuntimeDependencies(
            agentRegistry: makeAgentRegistry(),
            graphPlanner: graphPlanner,
            policy: policy,
            scheduler: scheduler,
            metricsCollector: metricsCollector,
            conversationMemory: conversationMemory,
            circuitBreakers: circuitBreakers,
            deviceRegistry: deviceRegistry,
            smartThingsRuleCreator: smartThingsRuleCreator
        )
    }

    public func makeRuntimeDependencies(
        orchestrationMode: OrchestrationMode = .graph,
        useMiniPipeline: Bool = false
    ) -> HomeAutomationRuntimeDependencies {
        let agentRegistry: AgentRegistry
        if useMiniPipeline {
            agentRegistry = agentCoordinator.makeAgentRegistry(
                automationCoordinator: automationCoordinator.withMiniPipeline(true)
            )
        } else {
            agentRegistry = makeAgentRegistry()
        }

        return HomeAutomationRuntimeDependencies(
            agentRegistry: agentRegistry,
            graphPlanner: graphPlanner,
            policy: policy,
            scheduler: scheduler,
            metricsCollector: OrchestratorMetricsCollector(),
            conversationMemory: ConversationMemory(),
            circuitBreakers: circuitBreakers,
            deviceRegistry: deviceRegistry,
            smartThingsRuleCreator: smartThingsRuleCreator,
            orchestrationMode: orchestrationMode,
            loopOrchestrator: orchestrationMode == .verifierLoop
                ? makeVerifierLoopOrchestrator()
                : nil
        )
    }

    /// Builds the verifier-loop orchestrator from coordinator-owned dependencies.
    public func makeVerifierLoopOrchestrator(
        policy loopPolicy: VerifierLoopPolicy = VerifierLoopPolicy()
    ) -> VerifierLoopOrchestrator {
        VerifierLoopOrchestrator(
            pipeline: DeterministicDraftPipeline(registry: deviceRegistry),
            verifier: DraftVerifierWorkerSession(
                foundationModelAvailability: foundationModelAvailability
            ),
            promptBuilder: VerifierPromptBuilder(),
            planner: RepairPlanner(),
            specialists: RepairSpecialistRegistry(
                fragmentNLU: FragmentNLUWorkerSession(
                    foundationModelAvailability: foundationModelAvailability
                ),
                targetResolver: ActionTargetResolver(registry: deviceRegistry),
                riskAssessor: AutomationRiskAssessor(),
                capabilityWorker: CapabilityResolutionWorker(
                    foundationModelAvailability: foundationModelAvailability
                ),
                operationDetection: { text in
                    HomeOperationDetectionService().analyzeSemantics(text)
                }
            ),
            policy: loopPolicy
        )
    }

    public func makeOrchestrator() -> HomeCommandOrchestrator {
        HomeCommandOrchestrator(dependencies: makeRuntimeDependencies())
    }

    public func makeAgentConstructionServices() -> HomeAutomationAgentConstructionServices {
        resolutionCoordinator.constructionServices
    }

    public static func makeMockDeviceRegistry(
        devices: [HomeCandidateRecord]? = nil
    ) -> MockHomeDeviceRegistry {
        DeviceCoordinator.makeMockDeviceRegistry(devices: devices)
    }
}
