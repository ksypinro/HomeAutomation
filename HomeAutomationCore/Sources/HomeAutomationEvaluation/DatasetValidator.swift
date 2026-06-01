import Foundation

public struct DatasetValidator: Sendable {
    public init() {}

    public func validate(fixtures: [GeneratedEvaluationFixture]) -> [DatasetValidationIssue] {
        var issues: [DatasetValidationIssue] = []
        issues.append(contentsOf: duplicateIDs(
            fixtures.map(\.id),
            field: "fixture.id",
            message: "Fixture ID must be unique"
        ))

        for fixture in fixtures {
            issues.append(contentsOf: validate(fixture: fixture))
        }
        return issues
    }

    public func validate(
        cases: [GeneratedEvaluationCase],
        fixtures: [GeneratedEvaluationFixture]
    ) -> [DatasetValidationIssue] {
        var issues: [DatasetValidationIssue] = []
        let fixtureByID = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, $0) })
        let fixtureDeviceIDs = fixtureByID.mapValues { Set($0.devices.map(\.id)) }
        let fixtureDeviceByID = fixtureByID.mapValues { fixture in
            Dictionary(uniqueKeysWithValues: fixture.devices.map { ($0.id, $0) })
        }

        issues.append(contentsOf: duplicateIDs(
            cases.map(\.id),
            field: "case.id",
            message: "Case ID must be unique"
        ))

        for testCase in cases {
            guard let fixture = fixtureByID[testCase.fixtureID] else {
                issues.append(issue(
                    severity: "error",
                    caseID: testCase.id,
                    fixtureID: testCase.fixtureID,
                    field: "fixtureID",
                    message: "Case references a missing fixture"
                ))
                continue
            }

            if testCase.traceContractID.isEmpty {
                issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "traceContractID", message: "Case must reference a trace contract"))
            }
            if testCase.metricsContractID.isEmpty {
                issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "metricsContractID", message: "Case must reference a metrics contract"))
            }

            let deviceIDs = fixtureDeviceIDs[fixture.id] ?? []
            for expectedID in testCase.expected.expectedDeviceIDs where !deviceIDs.contains(expectedID) {
                issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "expectedDeviceIDs", message: "Expected device ID '\(expectedID)' does not exist in fixture"))
            }

            if let targetDeviceID = testCase.expected.targetDeviceID {
                guard let device = fixtureDeviceByID[fixture.id]?[targetDeviceID] else {
                    issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "targetDeviceID", message: "Expected target device does not exist in fixture"))
                    continue
                }
                if let capability = testCase.expected.capability {
                    if !device.capabilities.contains(capability) {
                        issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "capability", message: "Expected capability '\(capability)' is not on target device '\(targetDeviceID)'"))
                    }
                    if let command = testCase.expected.command,
                       !(device.supportedCommands[capability] ?? []).contains(command) {
                        issues.append(issue(severity: "error", caseID: testCase.id, fixtureID: fixture.id, field: "command", message: "Expected command '\(command)' is not supported by capability '\(capability)' on target device '\(targetDeviceID)'"))
                    }
                }
            }
        }
        return issues
    }

    private func validate(fixture: GeneratedEvaluationFixture) -> [DatasetValidationIssue] {
        var issues: [DatasetValidationIssue] = []
        issues.append(contentsOf: duplicateIDs(
            fixture.devices.map(\.id),
            fixtureID: fixture.id,
            field: "device.id",
            message: "Device ID must be unique within a fixture"
        ))

        for device in fixture.devices {
            if device.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(severity: "error", fixtureID: fixture.id, field: "device.id", message: "Device ID must be non-empty"))
            }
            if device.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(severity: "error", fixtureID: fixture.id, field: "device.displayName", message: "Device display name must be non-empty"))
            }
            if device.deviceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(severity: "error", fixtureID: fixture.id, field: "device.deviceType", message: "Device type must be non-empty"))
            }
            if device.capabilities.isEmpty {
                issues.append(issue(severity: "error", fixtureID: fixture.id, field: "device.capabilities", message: "Device must expose at least one capability"))
            }
            for capability in device.supportedCommands.keys where !device.capabilities.contains(capability) {
                issues.append(issue(severity: "error", fixtureID: fixture.id, field: "device.supportedCommands", message: "Supported command capability '\(capability)' is not listed on device '\(device.id)'"))
            }
            for capability in device.capabilities {
                if device.supportedCommands[capability, default: []].isEmpty && !Self.measurementOnlyCapabilities.contains(capability) {
                    issues.append(issue(severity: "warning", fixtureID: fixture.id, field: "device.supportedCommands", message: "Capability '\(capability)' on device '\(device.id)' has no supported commands"))
                }
            }
        }

        if fixture.category == "numbered-bulbs" {
            issues.append(contentsOf: validateNumberedDevices(fixture))
        }
        return issues
    }

    private func validateNumberedDevices(_ fixture: GeneratedEvaluationFixture) -> [DatasetValidationIssue] {
        let numberedNames = fixture.devices.map(\.displayName).filter { name in
            name.range(of: #"\d+"#, options: .regularExpression) != nil
        }
        guard numberedNames.count >= 5 else {
            return [issue(
                severity: "error",
                fixtureID: fixture.id,
                field: "numberedDevices",
                message: "Numbered fixture must include at least five numbered device names"
            )]
        }

        let requiredNames = ["Bulb 1", "Bulb2", "Bulb 3", "Lamp 01", "Kitchen Light 2"]
        let missing = requiredNames.filter { !numberedNames.contains($0) }
        return missing.map {
            issue(
                severity: "error",
                fixtureID: fixture.id,
                field: "numberedDevices",
                message: "Missing required numbered device '\($0)'"
            )
        }
    }

    private func duplicateIDs(
        _ ids: [String],
        fixtureID: String? = nil,
        field: String,
        message: String
    ) -> [DatasetValidationIssue] {
        let grouped = Dictionary(grouping: ids, by: { $0 })
        return grouped
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { id, _ in
                issue(severity: "error", fixtureID: fixtureID, field: field, message: "\(message): \(id)")
            }
    }

    private func issue(
        severity: String,
        caseID: String? = nil,
        fixtureID: String? = nil,
        field: String,
        message: String
    ) -> DatasetValidationIssue {
        DatasetValidationIssue(
            severity: severity,
            caseID: caseID,
            fixtureID: fixtureID,
            field: field,
            message: message
        )
    }

    private static let measurementOnlyCapabilities: Set<String> = [
        "temperatureMeasurement",
        "relativeHumidityMeasurement",
        "battery",
        "powerMeter",
        "energyMeter",
        "airQualitySensor",
        "filterStatus",
        "contactSensor",
        "motionSensor",
        "smokeDetector",
        "waterSensor",
        "carbonMonoxideDetector",
        "carbonDioxideMeasurement",
        "illuminanceMeasurement"
    ]
}
