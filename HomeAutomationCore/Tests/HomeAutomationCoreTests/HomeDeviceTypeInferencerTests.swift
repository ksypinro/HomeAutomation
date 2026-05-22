import HomeAutomationCore
import Testing

@Suite
struct HomeDeviceTypeInferencerTests {
    @Test
    func categoryNameMapsToCanonicalDeviceType() {
        let result = HomeDeviceTypeInferencer.infer(
            deviceName: "Bedroom Main",
            capabilities: ["switch"],
            categoryName: "Light"
        )

        #expect(result.deviceType == "light")
        #expect(result.confidence >= 0.8)
    }

    @Test
    func strongCapabilitySignatureMapsAirConditioner() {
        let result = HomeDeviceTypeInferencer.infer(
            deviceName: "Bedroom AC",
            capabilities: [
                "switch",
                "thermostatCoolingSetpoint",
                "airConditionerMode",
                "airConditionerFanMode"
            ]
        )

        #expect(result.deviceType == "airConditioner")
        #expect(result.confidence >= 0.8)
    }

    @Test
    func sensorCapabilityMapsWithoutNameOrCategory() {
        let result = HomeDeviceTypeInferencer.infer(
            deviceName: nil,
            capabilities: ["contactSensor", "battery"]
        )

        #expect(result.deviceType == "contactSensor")
        #expect(result.confidence >= 0.8)
    }

    @Test
    func deviceNameBreaksGenericSwitchTie() {
        let result = HomeDeviceTypeInferencer.infer(
            deviceName: "Kitchen smart plug",
            capabilities: ["switch"]
        )

        #expect(result.deviceType == "outlet")
        #expect(result.confidence >= 0.45)
    }

    @Test
    func genericSwitchFallsBackToSwitch() {
        let result = HomeDeviceTypeInferencer.infer(
            deviceName: "Device 1",
            capabilities: ["switch"]
        )

        #expect(result.deviceType == "switch")
    }
}
