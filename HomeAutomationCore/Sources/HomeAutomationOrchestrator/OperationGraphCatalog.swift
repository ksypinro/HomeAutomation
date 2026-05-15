import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public protocol OperationGraphProvider: Sendable {
    var operation: HomeAutomationOperationKind { get }
    func makePlan(context: ResolutionContext) -> GraphExecutionPlan
}

public struct OperationGraphCatalog: Sendable {
    private let providers: [HomeAutomationOperationKind: any OperationGraphProvider]
    private let unsupportedProvider: any OperationGraphProvider

    public init(providers: [any OperationGraphProvider]) {
        var indexed: [HomeAutomationOperationKind: any OperationGraphProvider] = [:]
        for provider in providers {
            indexed[provider.operation] = provider
        }
        let fallbackUnsupported = UnsupportedGraphProvider()
        self.providers = indexed
        self.unsupportedProvider = indexed[.unsupported] ?? fallbackUnsupported
    }

    public static func defaultCatalog(
        policy: OrchestratorPolicyEngine
    ) -> OperationGraphCatalog {
        OperationGraphCatalog(
            providers: [
                DirectCommandGraphProvider(policy: policy),
                AutomationCreationGraphProvider(),
                UnsupportedGraphProvider()
            ]
        )
    }

    public func plan(
        for operation: HomeAutomationOperationKind,
        context: ResolutionContext
    ) -> GraphExecutionPlan {
        (providers[operation] ?? unsupportedProvider).makePlan(context: context)
    }
}

public struct DirectCommandGraphProvider: OperationGraphProvider {
    public let operation = HomeAutomationOperationKind.executeDeviceCommand
    private let policy: OrchestratorPolicyEngine

    public init(policy: OrchestratorPolicyEngine) {
        self.policy = policy
    }

    public func makePlan(context: ResolutionContext) -> GraphExecutionPlan {
        guard policy.shouldUseModels() else {
            return GraphExecutionPlan(
                graph: GraphPlanner.fallbackGraph(),
                isFallbackOnly: true
            )
        }
        return GraphExecutionPlan(graph: GraphPlanner.directCommandGraph())
    }
}

public struct AutomationCreationGraphProvider: OperationGraphProvider {
    public let operation = HomeAutomationOperationKind.automationCreation

    public init() {}

    public func makePlan(context: ResolutionContext) -> GraphExecutionPlan {
        GraphExecutionPlan(graph: GraphPlanner.automationCreationGraph())
    }
}

public struct UnsupportedGraphProvider: OperationGraphProvider {
    public let operation = HomeAutomationOperationKind.unsupported

    public init() {}

    public func makePlan(context: ResolutionContext) -> GraphExecutionPlan {
        GraphExecutionPlan(graph: GraphPlanner.unsupportedGraph())
    }
}
