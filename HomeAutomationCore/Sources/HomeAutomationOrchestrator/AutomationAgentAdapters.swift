import Foundation
import HomeAutomationAgents
import HomeAutomationCore

extension DefaultAgentRegistryFactory {
    internal static func automationConditionPatch(
        _ output: AutomationConditionResolutionOutput
    ) -> ResolutionContextPatch {
        var scopedUpdates: [ContextScope: [String: AnySendableValue]] = [
            .root: [
                ContextArtifactKeys.automationRuleDraft().name: AnySendableValue(output.ruleDraft),
                AutomationRuntimeContextKeys.conditionOperandResolutionRecords.name: AnySendableValue(output.records)
            ]
        ]

        for record in output.records {
            let scope = ContextScope.condition(record.id)
            scopedUpdates[scope] = [
                AutomationRuntimeContextKeys.conditionOperandResolution(in: scope).name: AnySendableValue(record)
            ]
        }

        return ResolutionContextPatch(
            agentID: .automationConditionOperandResolution,
            scopedUpdates: scopedUpdates
        )
    }

    internal static func automationActionPatch(
        _ output: AutomationActionResolutionAggregate,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var scopedUpdates: [ContextScope: [String: AnySendableValue]] = [
            .root: [
                AutomationRuntimeContextKeys.actionResolutionAggregate.name: AnySendableValue(output),
                ResolutionContextPatchKey.automationResolvedActions.rawValue: AnySendableValue(output.resolvedActions)
            ]
        ]

        for (index, result) in output.results.enumerated() {
            let scope = ContextScope.action("a\(index + 1)")
            var values: [String: AnySendableValue] = [
                "resolution": AnySendableValue(result.resolution)
            ]
            if let draft = result.draft {
                values[ContextArtifactKeys.commandDraft(in: scope).name] = AnySendableValue(draft)
            }
            if let resolvedAction = result.resolvedAction {
                values[ContextArtifactKeys.resolvedAction(in: scope).name] = AnySendableValue(resolvedAction)
            }
            scopedUpdates[scope] = values
        }

        return ResolutionContextPatch(
            agentID: .automationActionResolution,
            scopedUpdates: scopedUpdates
        )
    }

    internal static func smartThingsCompilationPatch(
        _ output: SmartThingsCompilationOutput,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var backendValues: [String: AnySendableValue] = [
            AutomationRuntimeContextKeys.smartThingsCompilation.name: AnySendableValue(output)
        ]
        if let document = output.document {
            backendValues[ContextArtifactKeys.smartThingsRule().name] = AnySendableValue(document)
        }

        return ResolutionContextPatch(
            agentID: .smartThingsCompilation,
            scopedUpdates: [
                .root: [
                    ContextArtifactKeys.automationPlan().name: AnySendableValue(output.plan)
                ],
                .backend("smartthings"): backendValues
            ]
        )
    }

    internal static func smartThingsRuleCreationPatch(
        _ output: SmartThingsRuleCreationOutput,
        _ context: ResolutionContext
    ) -> ResolutionContextPatch {
        var backendValues: [String: AnySendableValue] = [
            AutomationRuntimeContextKeys.smartThingsRuleCreation.name: AnySendableValue(output)
        ]
        if let receipt = output.receipt {
            backendValues[ContextArtifactKeys.smartThingsRuleCreation().name] = AnySendableValue(receipt)
        }

        return ResolutionContextPatch(
            agentID: .smartThingsRuleCreation,
            scopedUpdates: [
                .root: [
                    ContextArtifactKeys.automationPlan().name: AnySendableValue(output.plan)
                ],
                .backend("smartthings"): backendValues
            ]
        )
    }
}
