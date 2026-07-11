import Foundation
import HomeAutomationCore
import Testing

/// A-4 — the shared parenthesized-condition renderer used by both the verifier
/// prompt and the confirmation summary so the committed boolean-precedence
/// reading is always user-visible.
@Suite("ConditionReadingRenderer")
struct ConditionReadingRendererTests {

    private func leaf(_ description: String, value: String) -> HomeAutomationCondition {
        .comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(description: description, deviceID: nil, capability: nil, attribute: nil),
                operatorName: .equals,
                right: .literalString(value)
            )
        )
    }

    @Test("single comparison renders without parentheses")
    func singleComparison() {
        let condition = leaf("Light is on", value: "on")
        #expect(condition.parenthesizedDescription() == "Light is on")
    }

    @Test("nested AND-over-OR precedence parenthesizes the inner group only")
    func nestedPrecedence() {
        let condition = HomeAutomationCondition.or([
            .and([leaf("Light is on", value: "on"), leaf("Fan is off", value: "off")]),
            leaf("TV is off", value: "off"),
        ])
        #expect(condition.parenthesizedDescription() == "(Light is on AND Fan is off) OR TV is off")
    }

    @Test("NOT prefixes and parenthesizes a nested group")
    func notGroup() {
        let condition = HomeAutomationCondition.not(
            .or([leaf("Light is on", value: "on"), leaf("Fan is on", value: "on")])
        )
        #expect(condition.parenthesizedDescription() == "NOT (Light is on OR Fan is on)")
    }

    @Test("device names substitute for resolved IDs with operator/value phrasing")
    func deviceNameSubstitution() {
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(description: "", deviceID: "d1", capability: "switch", attribute: "switch"),
                operatorName: .equals,
                right: .literalString("on")
            )
        )
        #expect(condition.parenthesizedDescription(deviceNames: ["d1": "Kitchen Light"]) == "Kitchen Light is on")
    }

    @Test("numeric comparison renders the operator phrase")
    func numericComparison() {
        let condition = HomeAutomationCondition.comparison(
            HomeAutomationComparisonCondition(
                left: .deviceAttribute(description: "temperature", deviceID: "t1", capability: "temperatureMeasurement", attribute: "temperature"),
                operatorName: .greaterThanOrEquals,
                right: .literalNumber(25, unit: "C")
            )
        )
        #expect(condition.parenthesizedDescription(deviceNames: ["t1": "Sensor"]) == "Sensor is at least 25 C")
    }
}
