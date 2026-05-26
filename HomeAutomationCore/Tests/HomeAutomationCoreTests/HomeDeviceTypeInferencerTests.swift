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

    @Test
    func expandedCategoryNameMapsToRequestedDeviceTypes() {
        let smartLock = HomeDeviceTypeInferencer.infer(
            deviceName: "Front Door",
            capabilities: ["lock", "battery"],
            categoryName: "Smart Lock"
        )
        let printer = HomeDeviceTypeInferencer.infer(
            deviceName: "Workshop Printer",
            capabilities: ["switch", "statusReport"],
            categoryName: "3D Printer"
        )
        let television = HomeDeviceTypeInferencer.infer(
            deviceName: "Media Room TV",
            capabilities: ["switch", "audioVolume", "mediaPlayback", "mediaInputSource"],
            categoryName: "Television"
        )
        let charger = HomeDeviceTypeInferencer.infer(
            deviceName: "Garage EV Charger",
            capabilities: ["powerMeter", "energyMeter", "switch"],
            categoryName: "Electric Vehicle Charger"
        )

        #expect(smartLock.deviceType == "smartLock")
        #expect(printer.deviceType == "printer3D")
        #expect(["television", "tv"].contains(television.deviceType))
        #expect(charger.deviceType == "electricVehicleCharger")
    }

    @Test
    func relatedDeviceTypeFamiliesBridgeLegacyAndExpandedCategories() {
        #expect(HomeDeviceTypeRelations.areRelated("smartLock", "lock"))
        #expect(HomeDeviceTypeRelations.areRelated("smartPlug", "outlet"))
        #expect(HomeDeviceTypeRelations.areRelated("television", "tv"))
        #expect(HomeDeviceTypeRelations.matches("lock", in: ["smart lock"]))
    }
}
