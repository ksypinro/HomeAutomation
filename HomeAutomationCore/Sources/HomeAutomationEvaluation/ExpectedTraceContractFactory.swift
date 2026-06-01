import Foundation
import HomeAutomationCore

public struct ExpectedTraceContractFactory: Sendable {
    public init() {}

    public func makeContracts(for cases: [GeneratedEvaluationCase]) -> [ExpectedTraceContract] {
        cases.map(makeContract(for:))
    }

    public func makeContract(for testCase: GeneratedEvaluationCase) -> ExpectedTraceContract {
        switch testCase.expected.operation {
        case .automationCreation:
            return automationContract(for: testCase)
        case .unsupported:
            return unsupportedContract(for: testCase)
        default:
            return directCommandContract(for: testCase)
        }
    }

    private func directCommandContract(for testCase: GeneratedEvaluationCase) -> ExpectedTraceContract {
        ExpectedTraceContract(
            id: testCase.traceContractID,
            caseID: testCase.id,
            requiredGraphs: ["root-command-graph"],
            graphPathAlternatives: [["direct-command-graph"], ["direct-command-fallback-graph"]],
            requiredAgents: rootAgents(),
            agentPathAlternatives: [directCommandAgents(), fallbackCommandAgents()],
            requiredTools: optionalDraftTools(callerAgentID: "draftGeneration"),
            allowedSkippedAgents: ["mockExecution", "bixbyFallback", "unsupportedCommand"],
            expectedSelectedDeviceIDs: testCase.expected.expectedDeviceIDs,
            expectedCapability: testCase.expected.capability,
            expectedCommand: testCase.expected.command,
            maxModelCallCount: 24,
            maxToolCallCount: 48
        )
    }

    private func automationContract(for testCase: GeneratedEvaluationCase) -> ExpectedTraceContract {
        let actionCount = max(testCase.expected.actionCount ?? 1, 1)
        let conditionCount = max(testCase.expected.conditionCount ?? 0, 0)
        var components = [ExpectedAutomationComponentContract(
            componentKind: "trigger",
            componentID: "t1"
        )]
        components += (1...actionCount).map { index in
            ExpectedAutomationComponentContract(
                componentKind: "action",
                componentID: "a\(index)",
                expectedDeviceIDs: index == 1 ? testCase.expected.expectedDeviceIDs : [],
                expectedCapability: index == 1 ? testCase.expected.capability : nil,
                expectedCommand: index == 1 ? testCase.expected.command : nil
            )
        }
        if conditionCount > 0 {
            components += (1...conditionCount).map { index in
                ExpectedAutomationComponentContract(componentKind: "condition", componentID: "c\(index)")
            }
        }

        return ExpectedTraceContract(
            id: testCase.traceContractID,
            caseID: testCase.id,
            requiredGraphs: ["root-command-graph", "automation-creation-graph"],
            requiredAgents: rootAgents() + automationAgents(),
            requiredTools: optionalDraftTools(callerAgentID: "draftGeneration"),
            requiredComponents: components,
            allowedSkippedAgents: ["smartThingsRuleCreation"],
            expectedSelectedDeviceIDs: testCase.expected.expectedDeviceIDs,
            expectedCapability: testCase.expected.capability,
            expectedCommand: testCase.expected.command,
            maxModelCallCount: 48,
            maxToolCallCount: 96
        )
    }

    private func unsupportedContract(for testCase: GeneratedEvaluationCase) -> ExpectedTraceContract {
        ExpectedTraceContract(
            id: testCase.traceContractID,
            caseID: testCase.id,
            requiredGraphs: ["root-command-graph", "unsupported-graph"],
            requiredAgents: rootAgents() + [
                ExpectedAgentContract(agentID: "unsupportedCommand", expectedStatus: nil)
            ],
            expectedSelectedDeviceIDs: [],
            maxModelCallCount: 8,
            maxToolCallCount: 16
        )
    }

    private func rootAgents() -> [ExpectedAgentContract] {
        [
            ExpectedAgentContract(agentID: "operationDetection", expectedStatus: nil)
        ]
    }

    private func directCommandAgents() -> [ExpectedAgentContract] {
        [
            "semanticNLU",
            "slotExtraction",
            "riskClassification",
            "candidateRetrieval",
            "retrievalJudge",
            "candidateRanking",
            "candidateHydration",
            "capabilityResolution",
            "instructionComposer",
            "draftGeneration",
            "safetyValidation"
        ].map { ExpectedAgentContract(agentID: $0, expectedStatus: nil) } + [
            ExpectedAgentContract(agentID: "parameterValidation", required: false, expectedStatus: nil),
            ExpectedAgentContract(agentID: "confirmationPolicy", required: false, expectedStatus: nil),
            ExpectedAgentContract(agentID: "executionPlanning", required: false, expectedStatus: nil),
            ExpectedAgentContract(agentID: "mockExecution", required: false, expectedStatus: nil)
        ]
    }

    private func fallbackCommandAgents() -> [ExpectedAgentContract] {
        [
            ExpectedAgentContract(agentID: "ruleFallback", expectedStatus: nil)
        ]
    }

    private func automationAgents() -> [ExpectedAgentContract] {
        [
            "automationComponentSegmentation",
            "automationComponentFanOut",
            "automationDraftAssembly",
            "automationValidation",
            "smartThingsCompilation",
            "automationResultAssembly"
        ].map { ExpectedAgentContract(agentID: $0, expectedStatus: nil) } + [
            ExpectedAgentContract(agentID: "smartThingsRuleCreation", required: false, expectedStatus: nil)
        ]
    }

    private func optionalDraftTools(callerAgentID: String) -> [ExpectedToolContract] {
        [
            "findDeviceCandidates",
            "hydrateCandidates",
            "getCapabilities",
            "getDeviceState",
            "getSupportedModes",
            "validateCommand",
            "inspectCandidateCommand"
        ].map {
            ExpectedToolContract(
                toolID: $0,
                required: false,
                expectedStatus: nil,
                expectedCallerAgentIDs: [callerAgentID]
            )
        }
    }
}
