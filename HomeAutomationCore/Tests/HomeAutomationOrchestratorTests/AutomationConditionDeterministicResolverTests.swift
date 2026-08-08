import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite("Automation condition deterministic resolver")
struct AutomationConditionDeterministicResolverTests {
    @Test("Complete explicit lock condition is accepted at production threshold")
    func explicitLockConditionAccepted() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "front door is locked",
                devices: [
                    device(
                        id: "front-lock",
                        name: "Front Door Lock",
                        type: "lock",
                        capabilities: ["lock"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .complete)
        #expect(assessment.confidence >= 0.8)
        #expect(assessment.residualReasons.isEmpty)
        #expect(assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Generic readable capability fallback is not deterministically accepted")
    func genericReadableCapabilityFallbackRejected() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "front sensor above 5",
                devices: [
                    device(
                        id: "front-meter",
                        name: "Front Sensor",
                        type: "sensor",
                        capabilities: ["powerMeter"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .partial)
        #expect(assessment.residualReasons.contains(.capabilityNotExplicit))
        #expect(!assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Tied device scores stay ambiguous")
    func tiedDeviceScoresAreAmbiguous() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "temperature is above 20",
                devices: [
                    device(
                        id: "kitchen-temp",
                        name: "Kitchen Temperature Sensor",
                        type: "temperatureSensor",
                        capabilities: ["temperatureMeasurement"]
                    ),
                    device(
                        id: "living-temp",
                        name: "Living Room Temperature Sensor",
                        type: "temperatureSensor",
                        capabilities: ["temperatureMeasurement"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .ambiguous)
        #expect(assessment.residualReasons.contains(.deviceNotUnique))
        #expect(!assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Unsupported numeric unit stays residual")
    func unsupportedNumericUnitRejected() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "battery above 20 celsius",
                devices: [
                    device(
                        id: "front-battery",
                        name: "Front Battery Sensor",
                        type: "batterySensor",
                        capabilities: ["battery"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .partial)
        #expect(assessment.residualReasons.contains(.unitMismatch))
        #expect(!assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Determiners do not block an explicit door contact match")
    func determinerDoorContactAccepted() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "the front door is closed",
                devices: [
                    device(
                        id: "front-door",
                        name: "Front Door Lock",
                        type: "lock",
                        capabilities: ["lock", "contactSensor"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .complete)
        #expect(assessment.residualReasons.isEmpty)
        #expect(assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Someone home maps to a unique presence sensor")
    func someoneHomePresenceAccepted() {
        let assessment = AutomationConditionDeterministicResolver().assess(
            input: input(
                rawText: "someone is home",
                devices: [
                    device(
                        id: "home-presence",
                        name: "Home Presence Sensor",
                        type: "presenceSensor",
                        capabilities: ["presenceSensor"]
                    )
                ]
            )
        )

        #expect(assessment.completeness == .complete)
        #expect(assessment.residualReasons.isEmpty)
        #expect(assessment.isSafeToAccept(for: AutomationConditionGraphTarget()))
    }

    @Test("Model-unavailable fallback does not return unsafe residual condition")
    func unavailableFallbackDoesNotReturnUnsafeResidual() async throws {
        let worker = AutomationConditionClauseResolutionWorkerSession(
            foundationModelAvailability: { false }
        )

        let result = try await worker.resolve(
            input(
                rawText: "front sensor above 5",
                devices: [
                    device(
                        id: "front-meter",
                        name: "Front Sensor",
                        type: "sensor",
                        capabilities: ["powerMeter"]
                    )
                ]
            )
        )

        #expect(result.condition == nil)
        #expect(result.confidence < 0.8)
    }

    private func input(
        rawText: String,
        devices: [HomeCandidateRecord],
        triggerPolicy: HomeAutomationConditionTriggerPolicy = .never
    ) -> AutomationConditionClauseResolutionInput {
        AutomationConditionClauseResolutionInput(
            component: AutomationConditionComponent(id: "c1", rawText: rawText, order: 0),
            fullUserText: "turn on the lamp if \(rawText)",
            availableDevices: devices,
            triggerPolicy: triggerPolicy
        )
    }

    private func device(
        id: String,
        name: String,
        type: String,
        capabilities: [String]
    ) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: type,
            room: nil,
            capabilities: capabilities,
            supportedCommands: [:]
        )
    }
}
