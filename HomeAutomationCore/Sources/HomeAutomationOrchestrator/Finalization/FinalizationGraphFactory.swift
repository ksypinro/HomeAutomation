import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum FinalizationGraphFactory {
    public static func directCommandFinalizationGraph() -> OrchestrationGraph {
        let stages: [AgentID] = [
            .safetyValidation,
            .parameterValidation,
            .confirmationPolicy,
            .executionPlanning,
            .mockExecution
        ]

        return OrchestrationGraph(
            id: "direct-command-finalization-graph",
            goal: .executeDeviceCommand,
            nodes: stages.map { id in
                GraphNode(
                    id: id.rawValue,
                    requirement: .byID(id),
                    executionPolicy: .safetyGate,
                    guardCondition: guardCondition(for: id),
                    interrupt: interrupt(for: id)
                )
            },
            edges: edges(for: stages),
            entryNodeIDs: [AgentID.safetyValidation.rawValue]
        )
    }

    public static func automationFinalizationGraph() -> OrchestrationGraph {
        let stages: [(id: AgentID, policy: NodeExecutionPolicy)] = [
            (.automationValidation, .safetyGate),
            (.smartThingsCompilation, .required),
            (.smartThingsRuleCreation, .required),
            (.automationResultAssembly, .required)
        ]

        return OrchestrationGraph(
            id: "automation-finalization-graph",
            goal: .automationCreation,
            nodes: stages.map { stage in
                GraphNode(
                    id: stage.id.rawValue,
                    requirement: .byID(stage.id),
                    executionPolicy: stage.policy,
                    interrupt: interrupt(for: stage.id)
                )
            },
            edges: edges(for: stages.map(\.id)),
            entryNodeIDs: [AgentID.automationValidation.rawValue]
        )
    }

    private static func edges(for stages: [AgentID]) -> [GraphEdge] {
        zip(stages, stages.dropFirst()).map { GraphEdge(from: $0.rawValue, to: $1.rawValue) }
    }

    private static func guardCondition(for id: AgentID) -> GraphGuard? {
        switch id {
        case .mockExecution:
            return .canExecuteCommand
        default:
            return nil
        }
    }

    private static func interrupt(for id: AgentID) -> GraphInterrupt? {
        switch id {
        case .confirmationPolicy:
            return GraphInterrupt(
                kind: .confirmation,
                reason: "Pause before confirmation policy when a caller requests human approval checkpoints."
            )
        case .smartThingsRuleCreation:
            return GraphInterrupt(
                kind: .externalMutationApproval,
                reason: "Pause before external SmartThings rule creation when a caller requests mutation approval."
            )
        default:
            return nil
        }
    }
}
