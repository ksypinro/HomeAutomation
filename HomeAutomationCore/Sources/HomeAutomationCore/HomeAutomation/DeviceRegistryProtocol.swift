import Foundation

public protocol DeviceRegistryProtocol: Sendable {
    func allDevices() async -> [HomeCandidateRecord]

    func retrieveCandidates(
        text: String,
        hints: HomeResolutionState,
        limit: Int
    ) async -> [HomeCandidateRecord]

    func executeLowRiskPlan(_ plan: HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord
}

public extension DeviceRegistryProtocol {
    func retrieveCandidates(
        text: String,
        hints: HomeResolutionState,
        limit: Int = 80
    ) async -> [HomeCandidateRecord] {
        let devices = await allDevices()
        let query = text.normalizedHomeTokenString
        let hintedRooms = Set(hints.slots.rooms.map(\.normalizedHomeTokenString))
        let hintedTypes = Set(hints.deviceType.deviceTypes.map(\.normalizedHomeTokenString))
        let hintedNicknames = Set(hints.slots.deviceNicknames.map(\.normalizedHomeTokenString))
        let hintedFamilies = Set(hints.intent.topFamilies)

        let scored = devices.map { device in
            (
                device: device,
                score: Self.score(
                    device,
                    query: query,
                    hintedRooms: hintedRooms,
                    hintedTypes: hintedTypes,
                    hintedNicknames: hintedNicknames,
                    hintedFamilies: hintedFamilies
                )
            )
        }

        let positiveMatches = scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.device.displayName < rhs.device.displayName
                }
                return lhs.score > rhs.score
            }
            .map(\.device)

        if !positiveMatches.isEmpty {
            return Array(positiveMatches.prefix(limit))
        }

        return Array(devices.prefix(limit))
    }

    private static func score(
        _ device: HomeCandidateRecord,
        query: String,
        hintedRooms: Set<String>,
        hintedTypes: Set<String>,
        hintedNicknames: Set<String>,
        hintedFamilies: Set<HomeAutomationIntentFamily>
    ) -> Int {
        var total = 0
        let name = device.displayName.normalizedHomeTokenString
        let room = device.room?.normalizedHomeTokenString
        let type = device.deviceType.normalizedHomeTokenString
        let capabilities = device.capabilities.map(\.normalizedHomeTokenString)
        let aliases = device.metadata["aliases"]?
            .split(separator: ",")
            .map { String($0).normalizedHomeTokenString } ?? []

        if query.contains(name) { total += 8 }
        if query.contains(type) { total += 5 }
        if let room, query.contains(room) { total += 5 }
        for alias in aliases where !alias.isEmpty && containsTokenPhrase(query, phrase: alias) {
            total += 4
        }
        if HomeDeviceTypeRelations.matches(type, in: hintedTypes) { total += 4 }
        if let room, hintedRooms.contains(room) { total += 4 }
        if hintedNicknames.contains(name) { total += 4 }

        for capability in capabilities where query.contains(capability) {
            total += 2
        }

        if hintedFamilies.contains(.power), device.capabilities.contains("switch") {
            total += 2
        }
        if hintedFamilies.contains(.brightness), device.capabilities.contains("switchLevel") {
            total += 3
        }
        if hintedFamilies.contains(.temperature),
           device.capabilities.contains("thermostatCoolingSetpoint") ||
           device.capabilities.contains("thermostatHeatingSetpoint") ||
           device.capabilities.contains("thermostatMode") ||
           device.capabilities.contains("airConditionerFanMode") ||
           device.capabilities.contains("temperatureMeasurement") {
            total += 3
        }
        if hintedFamilies.contains(.media),
           device.capabilities.contains("mediaPlayback") ||
           device.capabilities.contains("audioVolume") ||
           device.capabilities.contains("channel") {
            total += 3
        }
        if hintedFamilies.contains(.applianceCycle),
           device.capabilities.contains("washerOperatingState") ||
           device.capabilities.contains("dryerOperatingState") ||
           device.capabilities.contains("robotCleanerMovement") ||
           device.capabilities.contains("ovenMode") {
            total += 3
        }
        if hintedFamilies.contains(.statusQuery),
           device.capabilities.contains("contactSensor") ||
           device.capabilities.contains("motionSensor") ||
           device.capabilities.contains("temperatureMeasurement") ||
           device.capabilities.contains("airQualitySensor") {
            total += 2
        }
        if hintedFamilies.contains(.lockUnlock),
           device.capabilities.contains("lock") {
            total += 4
        }
        if hintedFamilies.contains(.openClose),
           device.capabilities.contains("doorControl") ||
           device.capabilities.contains("garageDoorControl") ||
           device.capabilities.contains("windowShade") ||
           device.capabilities.contains("valve") {
            total += 4
        }

        return total
    }

    private static func containsTokenPhrase(_ normalizedText: String, phrase: String) -> Bool {
        let normalizedPhrase = phrase.normalizedHomeTokenString
        guard !normalizedPhrase.isEmpty else { return false }
        return " \(normalizedText) ".contains(" \(normalizedPhrase) ")
    }
}
