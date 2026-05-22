import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct AutomationConditionOperandResolverTests {
    @Test
    func resolverMapsContactConditionToReadableAttribute() async throws {
        let resolver = AutomationConditionOperandResolver(registry: MockHomeDeviceRegistry())
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "entry contact sensor",
                    deviceID: nil,
                    capability: nil,
                    attribute: nil
                ),
                operatorName: .equals,
                right: .literalString("closed")
            )
        )

        let resolved = await resolver.resolve(condition)

        guard case .comparison(let comparison) = resolved else {
            Issue.record("Expected comparison condition")
            return
        }
        guard case .deviceAttribute(_, let deviceID, let capability, let attribute) = comparison.left else {
            Issue.record("Expected device attribute operand")
            return
        }
        #expect(deviceID == "entry_contact_sensor")
        #expect(capability == "contactSensor")
        #expect(attribute == "contact")
    }

    @Test
    func strongDeterministicConditionMatchStillChecksFoundationModelAvailability() async throws {
        let availabilitySpy = FoundationModelAvailabilitySpy()
        let resolver = AutomationConditionOperandResolver(
            registry: MockHomeDeviceRegistry(),
            foundationModelAvailability: {
                availabilitySpy.record()
                return false
            }
        )
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "living room ceiling light",
                    deviceID: nil,
                    capability: nil,
                    attribute: nil
                ),
                operatorName: .equals,
                right: .literalString("off")
            )
        )

        let resolved = await resolver.resolve(condition)

        guard case .comparison(let comparison) = resolved,
              case .deviceAttribute(_, let deviceID, let capability, let attribute) = comparison.left else {
            Issue.record("Expected resolved device attribute operand")
            return
        }
        #expect(deviceID == "living_room_ceiling_light")
        #expect(capability == "switch")
        #expect(attribute == "switch")
        #expect(availabilitySpy.wasCalled() == true)
    }

    @Test
    func ambiguousConditionRemainsUnresolvedForValidationClarification() async throws {
        let registry = MockHomeDeviceRegistry(devices: [
            windowSensor("left_bedroom_window", "Left Bedroom Window"),
            windowSensor("right_bedroom_window", "Right Bedroom Window")
        ])
        let resolver = AutomationConditionOperandResolver(
            registry: registry,
            foundationModelAvailability: { false }
        )
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(
                    description: "bedroom window",
                    deviceID: nil,
                    capability: nil,
                    attribute: nil
                ),
                operatorName: .equals,
                right: .literalString("closed")
            )
        )

        let resolved = await resolver.resolve(condition)

        guard case .comparison(let comparison) = resolved else {
            Issue.record("Expected comparison condition")
            return
        }
        guard case .deviceAttribute(_, let deviceID, let capability, let attribute) = comparison.left else {
            Issue.record("Expected device attribute operand")
            return
        }
        #expect(deviceID == nil)
        #expect(capability == nil)
        #expect(attribute == nil)
    }

    @Test
    func endToEndAmbiguousConditionAsksForClarification() async throws {
        let registry = MockHomeDeviceRegistry(devices: [
            HomeCandidateRecord(
                id: "bedroom_lamp",
                displayName: "Bedroom Lamp",
                deviceType: "light",
                room: "bedroom",
                capabilities: ["switch"],
                supportedCommands: ["switch": ["on", "off"]],
                currentState: ["switch": "off"]
            ),
            windowSensor("left_bedroom_window", "Left Bedroom Window"),
            windowSensor("right_bedroom_window", "Right Bedroom Window")
        ])
        let orchestrator = HomeCommandOrchestrator(
            deviceRegistry: registry,
            foundationModelAvailability: { false }
        )

        let result = try await orchestrator.resolve(
            "Turn on bedroom lamp every day at 7 AM if bedroom window is closed",
            executeLowRiskCommands: true
        )

        guard case .needsClarification(let question) = result.resolution else {
            Issue.record("Expected clarification, got \(result.resolution.displaySummary)")
            return
        }
        #expect(question.contains("bedroom window"))
    }

    private func windowSensor(
        _ id: String,
        _ name: String
    ) -> HomeCandidateRecord {
        HomeCandidateRecord(
            id: id,
            displayName: name,
            deviceType: "contactSensor",
            room: "bedroom",
            capabilities: ["contactSensor"],
            supportedCommands: ["contactSensor": []],
            currentState: ["contact": "closed"]
        )
    }
}

private final class FoundationModelAvailabilitySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false

    func record() {
        lock.lock()
        defer { lock.unlock() }
        called = true
    }

    func wasCalled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return called
    }
}
