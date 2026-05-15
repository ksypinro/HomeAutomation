import HomeAutomationAgents
import HomeAutomationCore
import HomeAutomationRAG
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
    func parserTreatsActionIfDeviceStateAsDeviceTrigger() throws {
        let output = try #require(
            AutomationPatternParser().parse("Unlock the front door if bedroom ac is turned on")
        )

        #expect(output.actionDescriptions == ["Unlock the front door"])
        #expect(output.condition == nil)

        let draft = try output.makeRuleDraft()
        guard case .device(let trigger) = draft.trigger else {
            Issue.record("Expected device trigger")
            return
        }
        guard case .comparison(let comparison) = trigger.condition else {
            Issue.record("Expected comparison trigger condition")
            return
        }
        #expect(comparison.left == .deviceAttribute(
            description: "bedroom ac",
            deviceID: nil,
            capability: nil,
            attribute: nil
        ))
        #expect(comparison.operatorName == .equals)
        #expect(comparison.right == .literalString("on"))
        #expect(comparison.triggerPolicy == .always)
    }

    @Test
    func parserExtractsConversationalTemperatureRoutine() throws {
        let output = try #require(
            AutomationPatternParser().parse(
                "Today is quite hot. The temperature sensor is showing 25 Degree celcius. I want you to remember this and always turn on the Bedroom AC in similar situation"
            )
        )

        #expect(output.actionDescriptions == ["Turn on the Bedroom AC"])
        #expect(output.condition == nil)

        let draft = try output.makeRuleDraft()
        guard case .device(let trigger) = draft.trigger else {
            Issue.record("Expected conversational temperature reading to become a device trigger")
            return
        }
        guard case .comparison(let comparison) = trigger.condition else {
            Issue.record("Expected comparison trigger condition")
            return
        }
        #expect(comparison.left == .deviceAttribute(
            description: "temperature sensor",
            deviceID: nil,
            capability: nil,
            attribute: nil
        ))
        #expect(comparison.operatorName == .greaterThanOrEquals)
        #expect(comparison.right == .literalNumber(25, unit: "celsius"))
        #expect(comparison.triggerPolicy == .always)
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
        #expect(AutomationRAGPolicy.retrievalQueries(for: input, draftOutput: output).isEmpty)
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

        let subproblemQueries = AutomationRAGPolicy.retrievalQueries(for: input, draftOutput: output)
        let querySources = Set(subproblemQueries.compactMap { $0.query.metadataFilter?.source })
        #expect(subproblemQueries.map(\.subproblem).contains(.conditionGrammar))
        #expect(subproblemQueries.map(\.subproblem).contains(.compilerSchemaGrounding))
        #expect(querySources.contains(.automationConditionOperator))
        #expect(querySources.contains(.smartThingsRuleSchema))
    }

    @Test
    func automationRAGEvaluationCorpusMatchesRetrievalPolicy() throws {
        let parser = AutomationPatternParser()

        for testCase in AutomationRAGEvaluationCorpus.cases {
            let operation = HomeOperationDetectionResult(
                domain: .homeAutomation,
                operation: testCase.operation,
                confidence: 0.98,
                reason: "evaluation corpus"
            )
            let input = AutomationDraftInput(text: testCase.command, operation: operation)
            let draft = parser.parse(testCase.command)
            let decision = AutomationRAGPolicy.decision(for: input, draftOutput: draft)
            let queries = AutomationRAGPolicy.retrievalQueries(for: input, draftOutput: draft)

            #expect(
                decision.shouldRetrieve == testCase.shouldRetrieve,
                "Unexpected RAG decision for \(testCase.id)"
            )

            let subproblems = Set(queries.map(\.subproblem))
            let sources = Set(queries.compactMap { $0.query.metadataFilter?.source })
            let concepts = Set(queries.flatMap(\.query.automationConcepts))
            let operators = Set(queries.flatMap(\.query.conditionOperators))
            let repeatHints = Set(queries.flatMap(\.query.repeatHints))

            for expected in testCase.expectedSubproblems {
                #expect(subproblems.contains(expected), "\(testCase.id) missing subproblem \(expected.rawValue)")
            }
            for expected in testCase.expectedSources {
                #expect(sources.contains(expected), "\(testCase.id) missing source \(expected.rawValue)")
            }
            for expected in testCase.expectedConcepts {
                #expect(concepts.contains(expected), "\(testCase.id) missing concept \(expected)")
            }
            for expected in testCase.expectedConditionOperators {
                #expect(operators.contains(expected), "\(testCase.id) missing condition operator \(expected)")
            }
            for expected in testCase.expectedRepeatHints {
                #expect(repeatHints.contains(expected), "\(testCase.id) missing repeat hint \(expected)")
            }
        }
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

    @Test
    func automationDraftWorkerRejectsUngroundedModelOutput() async throws {
        let hallucinated = AutomationDraftOutput(
            name: "Hallway light daily",
            trigger: AutomationTriggerOutput(
                type: .schedule,
                repeatRule: "daily",
                time: "07:00"
            ),
            condition: nil,
            actionDescriptions: ["Turn on hallway light"],
            confidence: 1.0
        )
        let worker = AutomationDraftWorkerSession(
            draft: { _ in hallucinated },
            foundationModelAvailability: { false }
        )

        await #expect(throws: Error.self) {
            _ = try await worker.createDraft(
                AutomationDraftInput(text: "Unlock the front door if bedroom ac is turned on")
            )
        }
    }

    @Test
    func highConfidenceConditionalParserBypassesModelWhenAvailable() async throws {
        let worker = AutomationDraftWorkerSession(foundationModelAvailability: { true })

        let output = try await worker.createDraft(
            AutomationDraftInput(text: "Unlock the front door if bedroom ac is turned on")
        )

        #expect(output.actionDescriptions == ["Unlock the front door"])
        guard case .device = try output.makeRuleDraft().trigger else {
            Issue.record("Expected deterministic device trigger output")
            return
        }
    }
}
