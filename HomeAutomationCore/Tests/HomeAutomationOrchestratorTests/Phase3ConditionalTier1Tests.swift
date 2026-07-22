import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite("Phase 3 — Conditional Tier-1 eligibility")
struct Phase3ConditionalTier1Tests {

    // MARK: - Fixtures

    private func lockDevices() -> [HomeCandidateRecord] {
        [
            HomeCandidateRecord(
                id: "front_door_lock",
                displayName: "Front Door Lock",
                deviceType: "lock",
                room: "entry",
                capabilities: ["lock"],
                supportedCommands: ["lock": ["lock", "unlock"]],
                currentState: ["lock": "locked"]
            ),
            HomeCandidateRecord(
                id: "bedroom_lamp",
                displayName: "Bedroom Lamp",
                deviceType: "light",
                room: "bedroom",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]],
                currentState: ["switch": "off"]
            ),
        ]
    }

    private func features(
        operation: HomeAutomationOperationKind = .automationCreation,
        actionCount: Int = 1,
        conditionCount: Int = 1,
        risk: HomeAutomationRiskLevel = .low,
        memory: Bool = false,
        precedence: Bool = false,
        ood: PortfolioOODSignal = .inDomain,
        opConfidence: Double = 0.9,
        minFieldConfidence: Double = 0.7,
        unsupportedFragments: Int = 0
    ) -> PortfolioFeatureSnapshot {
        PortfolioFeatureSnapshot(
            operation: .present(operation, source: .deterministicParser),
            operationConfidence: .present(opConfidence, source: .deterministicParser),
            languageOODSignal: .present(ood, source: .deterministicParser),
            textSizeBucket: .present(.short, source: .deterministicParser),
            actionCount: .present(actionCount, source: .deterministicDraftPipeline),
            conditionCount: .present(conditionCount, source: .deterministicDraftPipeline),
            minimumFieldConfidence: .present(minFieldConfidence, source: .deterministicDraftPipeline),
            p50FieldConfidence: .present(0.8, source: .deterministicDraftPipeline),
            p90FieldConfidence: .present(0.9, source: .deterministicDraftPipeline),
            candidateCount: .present(1, source: .registrySnapshot),
            candidateTopTwoMargin: .present(0.5, source: .registrySnapshot),
            unsupportedFragmentCount: .present(unsupportedFragments, source: .deterministicDraftPipeline),
            precedenceAmbiguity: .present(precedence, source: .deterministicDraftPipeline),
            riskFloor: .present(risk, source: .deterministicDraftPipeline),
            memoryReference: .present(memory, source: .memoryDetector),
            exactTemplateMatch: .present(false, source: .deterministicParser),
            foundationModelAvailability: .present(.available, source: .runtimeAvailability),
            ragAvailability: .present(.available, source: .runtimeAvailability),
            gateDepth: .present(.none, source: .runtimeAvailability),
            warmStateHint: .present(.unknown, source: .runtimeAvailability),
            extractionDurationMs: 1.0
        )
    }

    private func prepared(
        features: PortfolioFeatureSnapshot,
        triggerType: TriggerDraft.TriggerDraftType = .schedule,
        conditionLeaves: [ConditionLeafDraft],
        conditionTree: ConditionTreeDraft?,
        actionCount: Int = 1,
        devices: [HomeCandidateRecord]? = nil,
        text: String = "lock the front door at 10 pm but only if the front door is locked"
    ) -> PreparedOrchestrationRequest {
        let actions = (0..<max(0, actionCount)).map { i in
            ActionDraft(
                rawText: "action \(i)",
                order: i,
                command: CommandDraftSection(
                    targetDeviceID: "front_door_lock",
                    capability: "lock",
                    commandName: "lock",
                    room: "entry"
                )
            )
        }
        let automation = AutomationDraftSection(
            trigger: TriggerDraft(type: triggerType, confidence: 0.9),
            conditionTree: conditionTree,
            conditionLeaves: conditionLeaves,
            actions: actions
        )
        let envelope = DraftEnvelope(
            userText: text,
            operation: features.operation.value ?? .automationCreation,
            operationConfidence: features.operationConfidence.value ?? 0.9,
            automation: automation,
            risk: RiskSection(level: features.riskFloor.value ?? .low, floorReason: "test")
        )
        return PreparedOrchestrationRequest(
            request: PreparedCommandRequestMetadata(
                request: CommandRequest(text: text, executeLowRiskCommands: false)
            ),
            featureSnapshot: features,
            deterministicEnvelope: envelope,
            deviceSnapshot: PreparedDeviceSnapshot(devices: devices ?? lockDevices()),
            memoryReferenceDetected: features.memoryReference.value ?? false,
            memoryHints: [],
            resolutionState: Self.emptyResolutionState(text: text),
            candidateIDs: []
        )
    }

    private static func emptyResolutionState(text: String) -> HomeResolutionState {
        HomeResolutionState(
            rawText: text,
            language: HomeLanguageDetectionResult(
                languageCode: "en",
                isMixedLanguage: false,
                confidence: 0.9,
                unsupportedLanguageLikely: false
            ),
            domain: HomeDomainClassificationResult(domain: .unsupported, confidence: 0.9),
            intent: HomeIntentFamilyResult(topFamilies: [.unsupported], confidence: 0.9),
            deviceType: HomeDeviceTypeResult(deviceTypes: [], confidence: 0.9),
            slots: HomeSlotExtractionResult(
                rooms: [],
                deviceNicknames: [],
                values: [],
                modes: [],
                confidence: 0.9
            ),
            risk: HomeRiskClassificationResult(
                riskLevel: .low,
                requiresConfirmation: false,
                reason: "test fixture",
                confidence: 0.9
            )
        )
    }

    private func completeLeaf() -> ConditionLeafDraft {
        ConditionLeafDraft(
            id: "cond_1",
            rawText: "front door is locked",
            target: "front door",
            capability: "lock",
            attribute: "lock",
            operatorName: .equals,
            value: "locked",
            confidence: 0.84
        )
    }

    // MARK: - Feature flag

    @Test("Flag OFF: eligible-looking conditional is rejected and routes to graph")
    func flagOffRoutesToGraph() {
        let policy = PortfolioEligibilityPolicy() // conditionalTier1Enabled defaults to false
        let request = prepared(
            features: features(),
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1")
        )

        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.featureDisabled))

        let decision = StaticPortfolioRouter(policy: policy).decide(request)
        #expect(decision.selectedArm == .graph)
        #expect(decision.ruleID != "static.automation.conditionalSchedule.tier1")
    }

    @Test("Flag ON: eligible conditional schedule selects Tier-1")
    func flagOnRoutesToTier1() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(),
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1")
        )

        let assessment = policy.conditionalTier1Assessment(request)
        #expect(assessment.isEligible)
        #expect(assessment.rejectionReasons.isEmpty)

        let decision = StaticPortfolioRouter(policy: policy).decide(request)
        #expect(decision.selectedArm == .graphWithTier1)
        #expect(decision.ruleID == "static.automation.conditionalSchedule.tier1")
        #expect(decision.selectedArmIsEligible)
    }

    // MARK: - Stay-on-Graph cohort (flag ON)

    @Test("High risk conditional stays on graph")
    func highRiskStaysGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(risk: .high),
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1")
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.highRisk))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    @Test("Device trigger stays on graph")
    func deviceTriggerStaysGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(),
            triggerType: .device,
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1")
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.notScheduleTrigger))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    @Test("Two condition leaves stay on graph")
    func twoLeavesStayGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let secondLeaf = ConditionLeafDraft(id: "cond_2", rawText: "bedroom lamp is on", confidence: 0.7)
        let request = prepared(
            features: features(conditionCount: 2),
            conditionLeaves: [completeLeaf(), secondLeaf],
            conditionTree: .and([.leaf("cond_1"), .leaf("cond_2")])
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.notExactlyOneConditionLeaf))
        #expect(assessment.rejectionReasons.contains(.conditionTreeNotSingleLeaf))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    @Test("Incomplete condition leaf stays on graph")
    func incompleteLeafStaysGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let vague = ConditionLeafDraft(id: "cond_1", rawText: "the vibe is immaculate", confidence: 0.3)
        let request = prepared(
            features: features(),
            conditionLeaves: [vague],
            conditionTree: .leaf("cond_1")
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.conditionLeafIncomplete))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    @Test("Out-of-range action count stays on graph")
    func tooManyActionsStayGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(actionCount: 5),
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1"),
            actionCount: 5
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.actionCountOutOfRange))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    @Test("Memory reference stays on graph")
    func memoryStaysGraph() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(memory: true),
            conditionLeaves: [completeLeaf()],
            conditionTree: .leaf("cond_1")
        )
        let assessment = policy.conditionalTier1Assessment(request)
        #expect(!assessment.isEligible)
        #expect(assessment.rejectionReasons.contains(.memoryReference))
        #expect(StaticPortfolioRouter(policy: policy).decide(request).selectedArm == .graph)
    }

    // MARK: - No-condition regression

    @Test("No-condition simple schedule still selects Tier-1 with flag on")
    func noConditionStillTier1() {
        let policy = PortfolioEligibilityPolicy(conditionalTier1Enabled: true)
        let request = prepared(
            features: features(conditionCount: 0),
            conditionLeaves: [],
            conditionTree: nil
        )
        let decision = StaticPortfolioRouter(policy: policy).decide(request)
        #expect(decision.selectedArm == .graphWithTier1)
        #expect(decision.ruleID == "static.automation.simpleSchedule.tier1")
    }
}
