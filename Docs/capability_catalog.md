# HomeAutomation Core Capability & Device Type Catalog

> [!NOTE]
> **Schema Version:** `2026-05-03.v1` | **Generated:** `2026-05-03`
> **System Summary:** Supports `60` unified capabilities and `174` device types.
>
> This catalog is a standardized ontology for home automation devices and capabilities, normalized from major smart home ecosystems. It is used by the `HomeAutomationKnowledgeBase` and agent natural-language parsing layers.

## Ecosystem Normalization Source platforms

The capability model is normalized across multiple ecosystems. Below is the source documentation and mapping rules:

- **Apple Home / HomeKit** ([Documentation](https://developer.apple.com/documentation/homekit/accessory-category-types), [Documentation](https://developer.apple.com/documentation/homekit/accessory-service-types), [Documentation](https://developer.apple.com/documentation/homekit/characteristic-types)): HomeKit models physical accessory categories separately from services and characteristics. This catalog maps both categories and service/characteristic concepts into normalized device types and capabilities.
- **SmartThings** ([Documentation](https://developer.smartthings.com/docs/devices/capabilities/), [Documentation](https://developer.smartthings.com/docs/devices/capabilities/capabilities-reference), [Documentation](https://developer.smartthings.com/docs/home-api/home-api-reference)): SmartThings capabilities are the main abstraction. They contain attributes for state and commands for control; monitoring-only capabilities may have no commands.
- **Google Home** ([Documentation](https://developers.home.google.com/cloud-to-cloud/supported-devices), [Documentation](https://developers.home.google.com/cloud-to-cloud/traits)): Google Home Cloud-to-cloud defines device types and traits. Traits drive natural-language support and may be required or recommended per device type.
- **Amazon Alexa Smart Home** ([Documentation](https://developer.amazon.com/docs/device-apis/list-of-interfaces.html), [Documentation](https://www.developer.amazon.com/en-US/docs/alexa/device-apis/alexa-discovery.html), [Documentation](https://developer.amazon.com/en-US/docs/alexa/smarthome/supported-matter-device-categories.html)): Alexa discovery uses display categories for app grouping and capability interfaces for controllable or reportable behavior.

### Normalization Notes

- Device types are normalized across Apple Home/HomeKit categories and services, SmartThings capabilities, Google Home device types and traits, and Alexa display categories/interfaces.
- Capability names use internal Swift-friendly identifiers while preserving platform mappings for later adapter or bridge work.
- This file intentionally includes both command capabilities and read-only measurement capabilities because natural-language users ask both control and status questions.

---

## Table of Contents

1. [Capabilities Reference](#1-capabilities-reference)
   - [Lighting & Power](#lighting-power)
   - [Climate & HVAC](#climate-hvac)
   - [Safety & Sensors](#safety-sensors)
   - [Security & Access](#security-access)
   - [Openings & Motorized](#openings-motorized)
   - [Water & Gardening](#water-gardening)
   - [Appliances & Cooking](#appliances-cooking)
   - [Media & Entertainment](#media-entertainment)
   - [Networking & System](#networking-system)
   - [Routines & Scenes](#routines-scenes)
2. [Device Types Reference](#2-device-types-reference)
   - [Air Quality](#air-quality)
   - [Appliance](#appliance)
   - [Bed Bath](#bed-bath)
   - [Climate](#climate)
   - [Cooking](#cooking)
   - [Electronics](#electronics)
   - [General](#general)
   - [Health](#health)
   - [Lighting](#lighting)
   - [Media](#media)
   - [Network](#network)
   - [Openings](#openings)
   - [Outdoor](#outdoor)
   - [Pet](#pet)
   - [Power](#power)
   - [Routine](#routine)
   - [Safety](#safety)
   - [Security](#security)
   - [Sensor](#sensor)
   - [Water](#water)

---

## 1. Capabilities Reference

Capabilities represent standard device states, read-only metrics, and control interfaces. They define the commands, value ranges, and security risk levels.

### Lighting & Power

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `battery` | Battery | `getStatus` | `numeric` (0–100) | 🟢 Low Risk |
| `colorControl` | Color | `setColor`, `setHue`, `setSaturation` | `string` | 🟢 Low Risk |
| `colorTemperature` | Color Temperature | `setColorTemperature`, `increaseValue`, `decreaseValue` | `numeric` (2000–9000) | 🟢 Low Risk |
| `energyMeter` | Energy Meter | `getStatus` | `number` | 🟢 Low Risk |
| `powerMeter` | Power Meter | `getStatus` | `number` | 🟢 Low Risk |
| `switch` | Switch | `on`, `off` | `enum` ("on", "off") | 🟢 Low Risk |
| `switchLevel` | Brightness / Level | `setLevel`, `increaseValue`, `decreaseValue` | `numeric` (0–100) | 🟢 Low Risk |


### Climate & HVAC

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `airConditionerMode` | Air Conditioner Mode | `setAirConditionerMode` | `enum` ("auto", "cool", "dry", "fanOnly", "heat") | 🟢 Low Risk |
| `airQualitySensor` | Air Quality | `getStatus` | `enum` ("good", "moderate", "poor", "veryPoor") | 🟢 Low Risk |
| `carbonDioxideMeasurement` | Carbon Dioxide Measurement | `getStatus` | `number` | 🟢 Low Risk |
| `fanSpeed` | Fan Speed | `setFanMode`, `increaseValue`, `decreaseValue` | `enum` ("auto", "low", "medium", "high", "turbo") | 🟢 Low Risk |
| `filterStatus` | Filter Status | `getStatus` | `enum` ("normal", "replace") | 🟢 Low Risk |
| `relativeHumidityMeasurement` | Humidity Measurement | `getStatus` | `numeric` (0–100) | 🟢 Low Risk |
| `temperatureMeasurement` | Temperature Measurement | `getStatus` | `number` | 🟢 Low Risk |
| `thermostatCoolingSetpoint` | Cooling Setpoint | `setCoolingSetpoint`, `increaseValue`, `decreaseValue` | `numeric` (16–30) | 🟢 Low Risk |
| `thermostatFanMode` | Thermostat Fan Mode | `setThermostatFanMode` | `enum` ("auto", "circulate", "on") | 🟢 Low Risk |
| `thermostatHeatingSetpoint` | Heating Setpoint | `setHeatingSetpoint`, `increaseValue`, `decreaseValue` | `numeric` (10–30) | 🟢 Low Risk |
| `thermostatMode` | Thermostat Mode | `setThermostatMode` | `enum` ("off", "heat", "cool", "auto", "eco") | 🟢 Low Risk |


### Safety & Sensors

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `carbonMonoxideDetector` | Carbon Monoxide Detector | `getStatus` | `enum` ("clear", "detected", "tested") | 🟢 Low Risk |
| `contactSensor` | Contact Sensor | `getStatus` | `enum` ("open", "closed") | 🟢 Low Risk |
| `illuminanceMeasurement` | Light Level | `getStatus` | `number` | 🟢 Low Risk |
| `motionSensor` | Motion Sensor | `getStatus` | `enum` ("active", "inactive") | 🟢 Low Risk |
| `occupancySensor` | Occupancy Sensor | `getStatus` | `enum` ("occupied", "unoccupied") | 🟢 Low Risk |
| `smokeDetector` | Smoke Detector | `getStatus` | `enum` ("clear", "detected", "tested") | 🟢 Low Risk |
| `soundDetection` | Sound Detection | `getStatus` | `enum` ("detected", "notDetected") | 🟡 **Medium Risk** |
| `tamperAlert` | Tamper Alert | `getStatus` | `enum` ("clear", "detected") | 🟡 **Medium Risk** |
| `waterSensor` | Water / Leak Sensor | `getStatus` | `enum` ("dry", "wet") | 🟢 Low Risk |


### Security & Access

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `doorControl` | Door Control | `open`, `close`, `getStatus` | `enum` ("open", "closed", "opening", "closing") | 🔴 **High Risk** |
| `garageDoorControl` | Garage Door Control | `open`, `close`, `getStatus` | `enum` ("open", "closed", "opening", "closing") | 🔴 **High Risk** |
| `lock` | Lock | `lock`, `unlock`, `getStatus` | `enum` ("locked", "unlocked", "jammed") | 🔴 **High Risk** |
| `lockCodes` | Lock Codes | `setCode`, `deleteCode`, `requestCode` | `string` | 🔴 **High Risk** |
| `securitySystem` | Security System | `arm`, `disarm`, `setMode`, `getStatus` | `enum` ("disarmed", "armedStay", "armedAway", "triggered") | 🔴 **High Risk** |


### Openings & Motorized

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `rotation` | Rotation | `setRotation`, `increaseValue`, `decreaseValue` | `numeric` (0–180) | 🟢 Low Risk |
| `valve` | Valve | `open`, `close`, `getStatus` | `enum` ("open", "closed") | 🔴 **High Risk** |
| `windowShade` | Window Covering | `open`, `close`, `pause`, `getStatus` | `enum` ("open", "closed", "partially open") | 🟡 **Medium Risk** |
| `windowShadeLevel` | Window Covering Level | `setShadeLevel`, `increaseValue`, `decreaseValue` | `numeric` (0–100) | 🟡 **Medium Risk** |


### Water & Gardening

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `dispense` | Dispense | `dispense` | `string` | 🟡 **Medium Risk** |
| `fill` | Fill | `fill`, `drain`, `setLevel` | `numeric` (0–100) | 🟡 **Medium Risk** |
| `sprinkler` | Sprinkler | `start`, `stop`, `setDuration` | `number` | 🟡 **Medium Risk** |


### Appliances & Cooking

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `cook` | Cook | `start`, `stop`, `setCookMode` | `enum` ("bake", "broil", "roast", "airFry", "warm") | 🔴 **High Risk** |
| `locator` | Locator | `locate` | `none` | 🟢 Low Risk |
| `mode` | Mode | `setMode` | `enum` ("auto", "normal", "eco", "sleep", "quick", "heavyDuty", "delicates") | 🟢 Low Risk |
| `ovenSetpoint` | Oven Temperature | `setOvenSetpoint`, `increaseValue`, `decreaseValue` | `numeric` (75–260) | 🔴 **High Risk** |
| `robotCleanerMovement` | Robot Cleaner Movement | `start`, `pause`, `stop`, `returnToHome` | `enum` ("idle", "cleaning", "paused", "homing") | 🟡 **Medium Risk** |
| `runCycle` | Run Cycle | `getStatus` | `string` | 🟢 Low Risk |
| `startStop` | Start / Stop | `start`, `stop`, `pause`, `resume` | `enum` ("ready", "running", "paused", "finished") | 🟡 **Medium Risk** |
| `timer` | Timer | `setTimer`, `pauseTimer`, `resumeTimer`, `cancelTimer`, `getStatus` | `string` | 🟢 Low Risk |
| `toggle` | Toggle | `setToggle` | `enum` ("on", "off") | 🟢 Low Risk |


### Media & Entertainment

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `appSelector` | App Selector | `launchApp` | `string` | 🟢 Low Risk |
| `audioVolume` | Volume | `setVolume`, `volumeUp`, `volumeDown`, `mute`, `unmute` | `numeric` (0–100) | 🟢 Low Risk |
| `cameraStream` | Camera Stream | `startStream`, `stopStream`, `getStatus` | `enum` ("idle", "streaming") | 🔴 **High Risk** |
| `channel` | Channel | `setChannel`, `channelUp`, `channelDown` | `number` | 🟢 Low Risk |
| `imageCapture` | Image Capture | `take` | `none` | 🔴 **High Risk** |
| `mediaInputSource` | Input Source | `setInputSource` | `enum` ("HDMI1", "HDMI2", "TV", "USB", "AV") | 🟢 Low Risk |
| `mediaPlayback` | Media Playback | `play`, `pause`, `stop`, `fastForward`, `rewind` | `enum` ("playing", "paused", "stopped") | 🟢 Low Risk |
| `remoteButton` | Remote Button | `press` | `string` | 🟢 Low Risk |


### Networking & System

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `reboot` | Reboot | `reboot` | `none` | 🟡 **Medium Risk** |
| `softwareUpdate` | Software Update | `getStatus`, `installUpdate` | `enum` ("available", "upToDate", "installing") | 🟡 **Medium Risk** |
| `statusReport` | Status Report | `getStatus` | `string` | 🟢 Low Risk |


### Routines & Scenes

| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `scene` | Scene / Routine | `run` | `none` | 🟢 Low Risk |



---

## 2. Device Types Reference

Device types categorize physical or virtual equipment, mapping them to required capabilities, recommended capabilities, and optional capabilities.

> [!WARNING]
> **High Risk Device Types Enabled:** control of certain equipment carries higher safety/security risk levels. Actions on these devices (e.g. unlocking a door, opening a valve, or turning on an oven) require extra agent verification and safety checks.
> High Risk Devices: `Arc Fault Circuit Interrupter`, `Camera`, `Circuit Breaker`, `Cooktop`, `Door`, `Door Lock`, `Doorbell`, `Fryer`, `Garage Door`, `Gate`, `Grill`, `Ground Fault Circuit Interrupter`, `Microwave`, `Oven`, `Security System`, `Smart Lock`, `Valve`, `Water Valve`, `Window`

### Air Quality

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `airFreshener` | Air Freshener | `switch` | `mode`, `toggle` | 🟢 Low Risk |
| `airPurifier` | Air Purifier | `switch` | `fanSpeed`, `airQualitySensor`, `filterStatus`, `mode` | 🟢 Low Risk |


### Appliance

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `clothesWasherDryer` | Clothes Washer Dryer | `startStop` | `switch`, `mode`, `runCycle` | 🟡 **Medium Risk** |
| `coffeeMachine` | Coffee Machine | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `cookerHood` | Cooker Hood | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `dishwasher` | Dishwasher | `startStop` | `switch`, `mode`, `runCycle` | 🟡 **Medium Risk** |
| `dryer` | Dryer | `startStop` | `switch`, `mode`, `runCycle`, `toggle` | 🟡 **Medium Risk** |
| `dryerLaundry` | Dryer Laundry | `startStop` | `switch`, `mode`, `runCycle` | 🟡 **Medium Risk** |
| `freezer` | Freezer | `temperatureMeasurement` | `thermostatCoolingSetpoint`, `mode` | 🟡 **Medium Risk** |
| `grinder` | Grinder | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `iceMachine` | Ice Machine | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `microwaveOven` | Microwave Oven | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `mop` | Robot Mop | `robotCleanerMovement` | `mode`, `battery`, `locator` | 🟡 **Medium Risk** |
| `portableStove` | Portable Stove | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `pump` | Pump | `switch` | `startStop`, `powerMeter` | 🟡 **Medium Risk** |
| `range` | Range | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `refrigerator` | Refrigerator | `temperatureMeasurement` | `thermostatCoolingSetpoint`, `filterStatus`, `mode` | 🟡 **Medium Risk** |
| `robotCleaner` | Robot Cleaner | `robotCleanerMovement` | `switch`, `mode`, `battery` | 🟢 Low Risk |
| `steamCloset` | Steam Closet | `startStop` | `switch`, `mode`, `runCycle` | 🟡 **Medium Risk** |
| `vacuum` | Robot Vacuum | `robotCleanerMovement` | `switch`, `mode`, `runCycle`, `battery`, `locator` | 🟡 **Medium Risk** |
| `vendingMachine` | Vending Machine | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `washer` | Washer | `startStop` | `switch`, `mode`, `runCycle`, `toggle` | 🟡 **Medium Risk** |
| `washerLaundry` | Washer Laundry | `startStop` | `switch`, `mode`, `runCycle` | 🟡 **Medium Risk** |
| `waterDispenser` | Water Dispenser | `switch` | `startStop`, `mode` | 🟡 **Medium Risk** |
| `waterValve` | Water Valve | `valve` | `waterSensor` | 🔴 **High Risk** |


### Bed Bath

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `bed` | Bed | `mode` | `scene` | 🟢 Low Risk |
| `blanket` | Blanket | `switch` | `mode`, `toggle`, `temperatureMeasurement` | 🟡 **Medium Risk** |


### Climate

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `airCompressor` | Air Compressor | `switch` | `fanSpeed` | 🟡 **Medium Risk** |
| `airConditioner` | Air Conditioner | `switch`, `thermostatCoolingSetpoint` | `airConditionerMode`, `fanSpeed`, `temperatureMeasurement`, `relativeHumidityMeasurement` | 🟡 **Medium Risk** |
| `airCooler` | Air Cooler | `switch`, `fanSpeed` | `thermostatCoolingSetpoint`, `relativeHumidityMeasurement`, `mode` | 🟡 **Medium Risk** |
| `airQualityMonitor` | Air Quality Monitor | `airQualitySensor` | `temperatureMeasurement`, `relativeHumidityMeasurement` | 🟢 Low Risk |
| `airer` | Airer | `switch` | `fanSpeed` | 🟡 **Medium Risk** |
| `boiler` | Boiler | `switch` | `thermostatHeatingSetpoint`, `temperatureMeasurement` | 🟡 **Medium Risk** |
| `condenser` | Condenser | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `condensingUnit` | Condensing Unit | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `dehumidifier` | Dehumidifier | `switch` | `relativeHumidityMeasurement`, `fanSpeed`, `mode`, `startStop` | 🟢 Low Risk |
| `fan` | Fan | `switch`, `fanSpeed` | `mode`, `toggle` | 🟢 Low Risk |
| `fireplace` | Fireplace | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `furnace` | Furnace | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `heater` | Heater | `switch`, `thermostatHeatingSetpoint` | `fanSpeed`, `temperatureMeasurement` | 🟡 **Medium Risk** |
| `humidifier` | Humidifier | `switch` | `relativeHumidityMeasurement`, `fanSpeed`, `mode`, `startStop` | 🟢 Low Risk |
| `hvac` | HVAC | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `portableHVAC` | Portable HVAC | `switch` | `temperatureMeasurement`, `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint`, `fanSpeed` | 🟡 **Medium Risk** |
| `thermostat` | Thermostat | `thermostatMode`, `thermostatCoolingSetpoint`, `thermostatHeatingSetpoint` | `thermostatFanMode`, `temperatureMeasurement`, `relativeHumidityMeasurement`, `battery` | 🟡 **Medium Risk** |


### Cooking

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `blender` | Blender | `switch` | `startStop`, `mode`, `timer` | 🟡 **Medium Risk** |
| `coffeeMaker` | Coffee Maker | `switch` | `cook`, `temperatureMeasurement`, `timer` | 🟡 **Medium Risk** |
| `cooktop` | Cooktop | `switch` | `cook`, `timer` | 🔴 **High Risk** |
| `dehydrator` | Dehydrator | `switch` | `cook`, `startStop`, `timer` | 🟡 **Medium Risk** |
| `fryer` | Fryer | `switch` | `cook`, `startStop`, `timer` | 🔴 **High Risk** |
| `grill` | Grill | `startStop` | `cook`, `timer`, `temperatureMeasurement` | 🔴 **High Risk** |
| `hood` | Range Hood | `switch` | `fanSpeed`, `switchLevel` | 🟢 Low Risk |
| `kettle` | Kettle | `switch` | `temperatureMeasurement` | 🟡 **Medium Risk** |
| `microwave` | Microwave | `startStop` | `cook`, `timer`, `mode` | 🔴 **High Risk** |
| `oven` | Oven | `cook` | `ovenSetpoint`, `timer`, `temperatureMeasurement`, `switch` | 🔴 **High Risk** |
| `yogurtMaker` | Yogurt Maker | `switch` | `cook`, `startStop`, `timer` | 🟡 **Medium Risk** |


### Electronics

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `businessEquipment` | Business Equipment | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `computer` | Computer | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `dataStorageUnit` | Data Storage Unit | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `desktopPC` | Desktop PC | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `electronics` | Electronics | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `networkingEquipment` | Networking Equipment | `statusReport` | `reboot`, `softwareUpdate` | 🟢 Low Risk |
| `notebookPC` | Notebook PC | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `portableElectronics` | Portable Electronics | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `printer` | Printer | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `printer3D` | 3D Printer | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `printerMultiFunction` | Printer Multi-Function | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `scanner` | Scanner | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |
| `server` | Server | `switch` | `statusReport`, `softwareUpdate` | 🟢 Low Risk |


### General

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `bathroomGeneral` | Bathroom General | `statusReport` | `battery` | 🟢 Low Risk |
| `bodyThermometer` | Body Thermometer | `temperatureMeasurement` | `battery` | 🟢 Low Risk |
| `foodProbe` | Food Probe | `temperatureMeasurement` | `battery` | 🟢 Low Risk |
| `genericSensor` | Generic Sensor | `statusReport` | `battery` | 🟢 Low Risk |
| `indoorGarden` | Indoor Garden | `statusReport` | `battery` | 🟢 Low Risk |
| `mattress` | Mattress | `statusReport` | `battery` | 🟢 Low Risk |
| `opticalAugmentedRFIDReader` | Optical Augmented RFID Reader | `statusReport` | `battery` | 🟢 Low Risk |
| `securityPanel` | Security Panel | `statusReport` | `battery` | 🟢 Low Risk |


### Health

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `activityTracker` | Activity Tracker | `statusReport` | `battery` | 🟢 Low Risk |
| `bloodPressureMonitor` | Blood Pressure Monitor | `statusReport` | `battery` | 🟢 Low Risk |
| `bodyCompositionAnalyser` | Body Composition Analyser | `statusReport` | `battery` | 🟢 Low Risk |
| `bodyScale` | Body Scale | `statusReport` | `battery` | 🟢 Low Risk |
| `continuousGlucoseMeter` | Continuous Glucose Meter | `statusReport` | `battery` | 🟢 Low Risk |
| `cyclingCadenceSensor` | Cycling Cadence Sensor | `statusReport` | `battery` | 🟢 Low Risk |
| `cyclingPowerMeter` | Cycling Power Meter | `statusReport` | `battery` | 🟢 Low Risk |
| `cyclingSpeedSensor` | Cycling Speed Sensor | `statusReport` | `battery` | 🟢 Low Risk |
| `exerciseMachine` | Exercise Machine | `statusReport` | `battery` | 🟢 Low Risk |
| `fitnessDevice` | Fitness Device | `statusReport` | `battery` | 🟢 Low Risk |
| `glucoseMeter` | Glucose Meter | `statusReport` | `battery` | 🟢 Low Risk |
| `heartRateMonitor` | Heart Rate Monitor | `statusReport` | `battery` | 🟢 Low Risk |
| `medicalDevice` | Medical Device | `statusReport` | `battery` | 🟢 Low Risk |
| `muscleOxygenMonitor` | Muscle Oxygen Monitor | `statusReport` | `battery` | 🟢 Low Risk |
| `personalHealthDevice` | Personal Health Device | `statusReport` | `battery` | 🟢 Low Risk |
| `pulseOximeter` | Pulse Oximeter | `statusReport` | `battery` | 🟢 Low Risk |
| `sleepMonitor` | Sleep Monitor | `statusReport` | `battery` | 🟢 Low Risk |


### Lighting

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `decorativeLighting` | Decorative Lighting | `switch` | `switchLevel` | 🟢 Low Risk |
| `emergencyLighting` | Emergency Lighting | `switch` | `switchLevel` | 🟢 Low Risk |
| `light` | Light | `switch` | `switchLevel`, `colorControl`, `colorTemperature` | 🟢 Low Risk |
| `lightingControls` | Lighting Controls | `switch` | `switchLevel` | 🟢 Low Risk |
| `switch` | Switch | `switch` | `switchLevel` | 🟢 Low Risk |


### Media

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `activeSpeaker` | Active Speaker | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `audioSystem` | Audio System | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `audioVideoReceiver` | AV Receiver | `switch`, `audioVolume`, `mediaInputSource`, `mediaPlayback` | `appSelector` | 🟢 Low Risk |
| `avPlayer` | AV Player | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `display` | Display | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `gameConsole` | Game Console | `switch`, `mediaPlayback`, `appSelector` | `mediaInputSource`, `audioVolume` | 🟢 Low Risk |
| `handset` | Handset | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `musicalInstrument` | Musical Instrument | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `receiver` | Receiver | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `remote` | Remote | `remoteButton` | `battery` | 🟢 Low Risk |
| `setTopBox` | Set Top Box | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `soundbar` | Soundbar | `switch`, `audioVolume`, `mediaPlayback`, `mediaInputSource` | *None* | 🟢 Low Risk |
| `speaker` | Speaker | `switch`, `audioVolume`, `mediaPlayback` | `appSelector` | 🟢 Low Risk |
| `streamingBox` | Streaming Box | `switch`, `mediaPlayback`, `appSelector` | `mediaInputSource`, `audioVolume` | 🟢 Low Risk |
| `streamingStick` | Streaming Stick | `switch`, `mediaPlayback`, `appSelector` | `mediaInputSource`, `audioVolume` | 🟢 Low Risk |
| `telephony` | Telephony | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `television` | Television | `switch` | `audioVolume`, `mediaPlayback` | 🟢 Low Risk |
| `tv` | Television | `switch`, `audioVolume`, `mediaPlayback`, `mediaInputSource` | `channel`, `appSelector` | 🟢 Low Risk |


### Network

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `bridge` | Bridge | `statusReport` | `softwareUpdate` | 🟢 Low Risk |
| `networkHardware` | Network Hardware | `reboot` | `softwareUpdate`, `statusReport` | 🟡 **Medium Risk** |
| `router` | Router | `reboot` | `softwareUpdate`, `statusReport` | 🟡 **Medium Risk** |


### Openings

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `awning` | Awning | `windowShade` | `windowShadeLevel` | 🟡 **Medium Risk** |
| `blind` | Blind | `windowShade` | `windowShadeLevel`, `rotation`, `battery` | 🟡 **Medium Risk** |
| `closet` | Closet | `doorControl` | `contactSensor` | 🟢 Low Risk |
| `curtain` | Curtain | `windowShade` | `windowShadeLevel` | 🟡 **Medium Risk** |
| `drawer` | Drawer | `doorControl` | `contactSensor` | 🟢 Low Risk |
| `shutter` | Shutter | `windowShade` | `windowShadeLevel`, `rotation` | 🟡 **Medium Risk** |
| `window` | Window | `doorControl` | `lock`, `contactSensor` | 🔴 **High Risk** |


### Outdoor

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `mower` | Robot Mower | `robotCleanerMovement` | `mode`, `battery`, `locator` | 🟡 **Medium Risk** |


### Pet

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `petFeeder` | Pet Feeder | `dispense` | `timer`, `battery` | 🟡 **Medium Risk** |


### Power

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `arcFaultCircuitInterrupter` | Arc Fault Circuit Interrupter | `switch` | `powerMeter`, `energyMeter` | 🔴 **High Risk** |
| `battery` | Battery | `battery` | `statusReport` | 🟢 Low Risk |
| `batteryCharger` | Battery Charger | `battery` | `statusReport` | 🟢 Low Risk |
| `charger` | Charger | `battery` | `switch`, `energyMeter` | 🟢 Low Risk |
| `circuitBreaker` | Circuit Breaker | `switch` | `powerMeter`, `energyMeter` | 🔴 **High Risk** |
| `electricMeter` | Electric Meter | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `electricVehicleCharger` | Electric Vehicle Charger | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `energyGenerator` | Energy Generator | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `energyMonitor` | Energy Monitor | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `groundFaultCircuitInterrupter` | Ground Fault Circuit Interrupter | `switch` | `powerMeter`, `energyMeter` | 🔴 **High Risk** |
| `inverter` | Inverter | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `outlet` | Outlet | `switch` | `powerMeter`, `energyMeter` | 🟢 Low Risk |
| `pvArraySystem` | PV Array System | `powerMeter` | `energyMeter`, `statusReport` | 🟢 Low Risk |
| `smartPlug` | Smart Plug | `switch` | `powerMeter`, `energyMeter` | 🟢 Low Risk |


### Routine

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `routine` | Routine | `routine` | *None* | 🟢 Low Risk |
| `scene` | Scene | `scene` | *None* | 🟢 Low Risk |


### Safety

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `carbonMonoxideDetector` | Carbon Monoxide Detector | `carbonMonoxideDetector`, `battery` | *None* | 🟢 Low Risk |
| `smokeDetector` | Smoke Detector | `smokeDetector`, `battery` | *None* | 🟢 Low Risk |
| `waterSensor` | Water Leak Sensor | `waterSensor`, `battery` | *None* | 🟢 Low Risk |


### Security

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `accessManagementService` | Access Management Service | `statusReport` | `softwareUpdate` | 🟢 Low Risk |
| `camera` | Camera | `cameraStream` | `imageCapture`, `motionSensor`, `soundDetection`, `switch` | 🔴 **High Risk** |
| `credentialManagementService` | Credential Management Service | `statusReport` | `softwareUpdate` | 🟢 Low Risk |
| `deviceOwnershipTransferService` | Device Ownership Transfer Service | `statusReport` | `softwareUpdate` | 🟢 Low Risk |
| `door` | Door | `doorControl` | `lock`, `contactSensor` | 🔴 **High Risk** |
| `doorbell` | Doorbell | `cameraStream` | `motionSensor`, `imageCapture`, `audioVolume` | 🔴 **High Risk** |
| `garageDoor` | Garage Door | `garageDoorControl` | `contactSensor`, `motionSensor`, `battery` | 🔴 **High Risk** |
| `gate` | Gate | `doorControl` | `lock`, `contactSensor` | 🔴 **High Risk** |
| `lock` | Door Lock | `lock` | `lockCodes`, `tamperAlert`, `battery`, `contactSensor` | 🔴 **High Risk** |
| `securitySystem` | Security System | `securitySystem` | `statusReport`, `motionSensor`, `contactSensor` | 🔴 **High Risk** |
| `smartLock` | Smart Lock | `lock` | `lockCodes`, `battery` | 🔴 **High Risk** |
| `virtualDevice` | Virtual Device | `statusReport` | `softwareUpdate` | 🟢 Low Risk |


### Sensor

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `airQualityDetector` | Air Quality Monitor | `airQualitySensor` | `temperatureMeasurement`, `relativeHumidityMeasurement`, `carbonDioxideMeasurement`, `carbonMonoxideDetector` | 🟢 Low Risk |
| `contactSensor` | Contact Sensor | `contactSensor`, `battery` | `temperatureMeasurement` | 🟢 Low Risk |
| `humiditySensor` | Humidity Sensor | `relativeHumidityMeasurement`, `battery` | *None* | 🟢 Low Risk |
| `lightSensor` | Light Sensor | `illuminanceMeasurement`, `battery` | *None* | 🟢 Low Risk |
| `motionSensor` | Motion Sensor | `motionSensor`, `battery` | `illuminanceMeasurement` | 🟢 Low Risk |
| `occupancySensor` | Occupancy Sensor | `occupancySensor`, `battery` | *None* | 🟢 Low Risk |
| `temperatureSensor` | Temperature Sensor | `temperatureMeasurement`, `battery` | *None* | 🟢 Low Risk |


### Water

| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| `bathtub` | Bathtub | `fill` | `temperatureMeasurement`, `startStop` | 🟡 **Medium Risk** |
| `faucet` | Faucet | `startStop` | `dispense`, `temperatureMeasurement` | 🟡 **Medium Risk** |
| `shower` | Shower | `startStop` | `temperatureMeasurement`, `dispense` | 🟡 **Medium Risk** |
| `sprinkler` | Sprinkler | `sprinkler` | `valve`, `timer` | 🟡 **Medium Risk** |
| `valve` | Valve | `valve` | `waterSensor`, `battery` | 🔴 **High Risk** |
| `waterHeater` | Water Heater | `switch` | `temperatureMeasurement`, `thermostatHeatingSetpoint` | 🟡 **Medium Risk** |
| `waterPurifier` | Water Purifier | `switch` | `filterStatus`, `waterSensor` | 🟢 Low Risk |
| `waterSoftener` | Water Softener | `switch` | `filterStatus`, `waterSensor` | 🟢 Low Risk |
