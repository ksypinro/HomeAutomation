import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite
struct AutomationDraftAgentTests {
    @Test
    func modelUnavailableModeExtractsSimpleDailySchedule() async throws {
        let worker = AutomationDraftWorkerSession(foundationModelAvailability: { false })

        let output = try await worker.createDraft(
            AutomationDraftInput(text: "Turn on AC everyday at 7 AM")
        )
        let draft = try output.makeRuleDraft()

        #expect(draft.actionDescriptions == ["Turn on AC"])
        #expect(output.unsupportedFragments.isEmpty)
        guard case .schedule(let schedule) = draft.trigger else {
            Issue.record("Expected schedule trigger")
            return
        }
        #expect(schedule.repeatRule == .everyDay)
        #expect(schedule.timeOfDay?.hour == 7)
        #expect(schedule.timeOfDay?.minute == 0)
    }

    @Test
    func parserSeparatesMultipleActions() throws {
        let output = try #require(
            AutomationPatternParser().parse("Turn on AC and turn off bedroom lamp every day at 7 AM")
        )

        #expect(output.actionDescriptions == ["Turn on AC", "Turn off bedroom lamp"])
        let draft = try output.makeRuleDraft()
        #expect(draft.actionDescriptions.count == 2)
    }

    @Test
    func parserRearrangesScheduleTargetSyntaxIntoCommandText() throws {
        let output = try #require(
            AutomationPatternParser().parse("Schedule bedroom AC to turn on daily at 7 AM")
        )

        #expect(output.actionDescriptions == ["Turn on bedroom AC"])
    }

    @Test
    func parserPreservesAndConditionShape() throws {
        let output = try #require(
            AutomationPatternParser().parse(
                "Turn on AC every day at 7 AM if bedroom window is closed and motion is detected"
            )
        )
        let condition = try #require(output.condition)

        #expect(condition.type == .and)
        #expect(condition.children.count == 2)

        let draft = try output.makeRuleDraft()
        guard case .and(let children) = draft.condition else {
            Issue.record("Expected and condition")
            return
        }
        #expect(children.count == 2)
    }

    @Test
    func simpleDailyScheduleDoesNotNeedAutomationRAG() throws {
        let input = AutomationDraftInput(
            text: "Turn on AC every day at 7 AM",
            operation: HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .automationCreation,
                confidence: 0.98,
                reason: "schedule automation"
            )
        )
        let output = try #require(AutomationPatternParser().parse(input.text))

        let decision = AutomationRAGPolicy.decision(for: input, draftOutput: output)

        #expect(!decision.shouldRetrieve)
        #expect(decision.reasons.isEmpty)
    }

    @Test
    func complexConditionNeedsAutomationRAG() throws {
        let input = AutomationDraftInput(
            text: "Turn on AC every day at 7 AM if bedroom window is closed and motion is detected",
            operation: HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: .automationCreation,
                confidence: 0.98,
                reason: "schedule automation"
            )
        )
        let output = try #require(AutomationPatternParser().parse(input.text))

        let decision = AutomationRAGPolicy.decision(for: input, draftOutput: output)
        let query = AutomationRAGPolicy.retrievalQuery(for: input, draftOutput: output)

        #expect(decision.shouldRetrieve)
        #expect(decision.reasons.contains("deviceAttributeCondition"))
        #expect(query.operation == .automationCreation)
        #expect(query.automationConcepts.contains("compoundCondition"))
        #expect(query.conditionOperators.contains("and"))
        #expect(query.repeatHints.contains("everyDay"))
    }

    @Test
    func parserPreservesOrConditionShape() throws {
        let output = try #require(
            AutomationPatternParser().parse(
                "Turn on hallway light every day at 6 AM if front door is open or motion is detected"
            )
        )
        let condition = try #require(output.condition)

        #expect(condition.type == .or)
        #expect(condition.children.count == 2)

        let draft = try output.makeRuleDraft()
        guard case .or(let children) = draft.condition else {
            Issue.record("Expected or condition")
            return
        }
        #expect(children.count == 2)
    }

    @Test
    func weekdayScheduleIsPreservedAndFlaggedAsUnsupportedFragment() throws {
        let output = try #require(
            AutomationPatternParser().parse("Turn on AC every Monday at 7 AM")
        )
        let draft = try output.makeRuleDraft()

        #expect(output.unsupportedFragments == ["every monday"])
        guard case .schedule(let schedule) = draft.trigger else {
            Issue.record("Expected schedule trigger")
            return
        }
        #expect(schedule.repeatRule == .daysOfWeek([.monday]))
    }

    @Test
    func automationDraftAgentUsesInjectedWorkerOutput() async throws {
        let expected = AutomationDraftOutput(
            name: "Injected automation",
            trigger: AutomationTriggerOutput(
                type: .schedule,
                repeatRule: "everyDay",
                time: "07:00"
            ),
            condition: nil,
            actionDescriptions: ["Turn on AC"],
            confidence: 0.99
        )
        let agent = AutomationDraftAgent(
            worker: AutomationDraftWorkerSession(
                draft: { _ in expected },
                foundationModelAvailability: { false }
            )
        )
        let context = ResolutionContext(
            request: CommandRequest(text: "ignored", executeLowRiskCommands: false)
        )

        let output = try await agent.run(
            AutomationDraftInput(text: "Turn on AC everyday at 7 AM"),
            context: context
        )

        #expect(output == expected)
    }
}
