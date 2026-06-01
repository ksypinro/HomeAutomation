import Foundation
import HomeAutomationCore

public struct EvaluationCommandGenerator: Sendable {
    private let paraphraseProvider: any CommandParaphraseProvider
    private let generationMode: EvaluationCommandGenerationMode
    private let paraphraseValidator: CommandParaphraseValidator

    public init(
        paraphraseProvider: any CommandParaphraseProvider = TemplateCommandParaphraseProvider(),
        generationMode: EvaluationCommandGenerationMode = .template,
        paraphraseValidator: CommandParaphraseValidator = CommandParaphraseValidator()
    ) {
        self.paraphraseProvider = paraphraseProvider
        self.generationMode = generationMode
        self.paraphraseValidator = paraphraseValidator
    }

    public func canonicalSpecs(for fixture: GeneratedEvaluationFixture) -> [CanonicalCommandSpec] {
        var specs: [CanonicalCommandSpec] = []
        for device in fixture.devices {
            specs.append(contentsOf: directSpecs(for: device, fixtureID: fixture.id))
            specs.append(contentsOf: statusSpecs(for: device, fixtureID: fixture.id))
            specs.append(contentsOf: brightnessSpecs(for: device, fixtureID: fixture.id))
            specs.append(contentsOf: climateSpecs(for: device, fixtureID: fixture.id))
            specs.append(contentsOf: mediaSpecs(for: device, fixtureID: fixture.id))
            specs.append(contentsOf: lockOpenCloseSpecs(for: device, fixtureID: fixture.id))
        }
        specs.append(contentsOf: automationSpecs(for: fixture))
        specs.append(unsupportedSpec(for: fixture))
        return stableUniqueSpecs(specs)
    }

    public func generateCases(
        for fixtures: [GeneratedEvaluationFixture],
        commandsPerFixture: Int
    ) async throws -> [GeneratedEvaluationCase] {
        var generated: [GeneratedEvaluationCase] = []
        for fixture in fixtures {
            let specs = canonicalSpecs(for: fixture)
            guard !specs.isEmpty else { continue }
            var paraphraseCache: [String: [String]] = [:]
            var caseIndex = 0
            var specIndex = 0
            while caseIndex < commandsPerFixture {
                let spec = specs[specIndex % specs.count]
                let variants = try await cachedParaphrases(
                    for: spec,
                    count: max(4, (commandsPerFixture / max(specs.count, 1)) + 2),
                    cache: &paraphraseCache
                )
                let input = variants[(specIndex / specs.count) % variants.count]
                let caseID = "\(fixture.id).case-\(String(format: "%03d", caseIndex + 1))"
                generated.append(GeneratedEvaluationCase(
                    id: caseID,
                    fixtureID: fixture.id,
                    suite: spec.suite,
                    tags: spec.tags,
                    input: input,
                    canonicalCommandID: spec.id,
                    expected: spec.expected,
                    traceContractID: "\(caseID).trace",
                    metricsContractID: "\(caseID).metrics"
                ))
                caseIndex += 1
                specIndex += 1
            }
        }
        return generated
    }

    public func generateSmokeDataset(
        fixtureLimit: Int = 10,
        commandsPerFixture: Int = 10,
        generatedAt: String = "2026-06-01T00:00:00Z"
    ) async throws -> GeneratedEvaluationDataset {
        try await generateDataset(
            name: "seed-v1-smoke",
            fixtureLimit: fixtureLimit,
            commandsPerFixture: commandsPerFixture,
            generatedAt: generatedAt
        )
    }

    public func generateSeedDataset(
        name: String = "seed-v1",
        fixtureLimit: Int = 10,
        commandsPerFixture: Int = 100,
        generatedAt: String = "2026-06-01T00:00:00Z"
    ) async throws -> GeneratedEvaluationDataset {
        try await generateDataset(
            name: name,
            fixtureLimit: fixtureLimit,
            commandsPerFixture: commandsPerFixture,
            generatedAt: generatedAt
        )
    }

    public func generateDataset(
        name: String,
        fixtureLimit: Int = 10,
        commandsPerFixture: Int,
        generatedAt: String = "2026-06-01T00:00:00Z"
    ) async throws -> GeneratedEvaluationDataset {
        let fixtures = EvaluationFixtureGenerator().generateFixtures(count: fixtureLimit)
        let cases = try await generateCases(for: fixtures, commandsPerFixture: commandsPerFixture)
        let fixtureIssues = DatasetValidator().validate(fixtures: fixtures)
        let caseIssues = DatasetValidator().validate(cases: cases, fixtures: fixtures)
        let validationStatus = (fixtureIssues + caseIssues).contains { $0.severity == "error" } ? "failed" : "passed"
        let manifest = EvaluationDatasetManifest(
            name: name,
            version: "1.0.0",
            generatedAt: generatedAt,
            generatorVersion: "golden-eval-generator-v1",
            fixtureCount: fixtures.count,
            caseCount: cases.count,
            commandsPerFixture: commandsPerFixture,
            generationMode: generationMode.rawValue,
            randomSeed: 20260601,
            validationStatus: validationStatus
        )
        return GeneratedEvaluationDataset(
            manifest: manifest,
            fixtures: fixtures,
            cases: cases,
            traceContracts: ExpectedTraceContractFactory().makeContracts(for: cases),
            metricsContracts: ExpectedMetricsContractFactory().makeContracts(for: cases)
        )
    }

    public func generateFullDataset(
        name: String = "full-v1",
        fixtureLimit: Int = 100,
        commandsPerFixture: Int = 100,
        generatedAt: String = "2026-06-01T00:00:00Z"
    ) async throws -> GeneratedEvaluationDataset {
        try await generateDataset(
            name: name,
            fixtureLimit: fixtureLimit,
            commandsPerFixture: commandsPerFixture,
            generatedAt: generatedAt
        )
    }

    private func cachedParaphrases(
        for spec: CanonicalCommandSpec,
        count: Int,
        cache: inout [String: [String]]
    ) async throws -> [String] {
        if let cached = cache[spec.id] {
            return cached
        }
        let rawParaphrases = try await paraphraseProvider.paraphrases(for: spec, count: count)
        let paraphrases = paraphraseValidator.validatedParaphrases(rawParaphrases, for: spec)
        guard paraphrases.count >= count else {
            throw CommandParaphraseProviderError.insufficientValidParaphrases(
                specID: spec.id,
                requested: count,
                accepted: paraphrases.count
            )
        }
        cache[spec.id] = paraphrases
        return paraphrases
    }

    private func directSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        guard let commands = device.supportedCommands["switch"] else { return [] }
        return commands
            .filter { ["on", "off"].contains($0) }
            .map { command in
                let verb = command == "on" ? "Turn on" : "Turn off"
                return CanonicalCommandSpec(
                    id: "\(fixtureID).\(device.id).switch.\(command)",
                    fixtureID: fixtureID,
                    suite: "end-to-end-direct-command",
                    tags: ["direct-command", "power", device.deviceType],
                    category: .directPower,
                    canonicalUtterance: "\(verb) \(device.displayName)",
                    deviceDisplayName: device.displayName,
                    room: device.room,
                    expected: ExpectedResolvedOutput(
                        operation: .executeDeviceCommand,
                        domain: .homeAutomation,
                        allowedOutcome: .ready,
                        expectedDeviceIDs: [device.id],
                        targetDeviceID: device.id,
                        capability: "switch",
                        command: command
                    )
                )
            }
    }

    private func statusSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        guard let capability = device.supportedCommands.first(where: { $0.value.contains("getStatus") })?.key else {
            return []
        }
        return [
            CanonicalCommandSpec(
                id: "\(fixtureID).\(device.id).status.\(capability)",
                fixtureID: fixtureID,
                suite: "end-to-end-direct-command",
                tags: ["direct-command", "status", device.deviceType],
                category: .statusQuery,
                canonicalUtterance: "What is the status of \(device.displayName)?",
                deviceDisplayName: device.displayName,
                room: device.room,
                expected: ExpectedResolvedOutput(
                    operation: .executeDeviceCommand,
                    domain: .homeAutomation,
                    allowedOutcome: .ready,
                    expectedDeviceIDs: [device.id],
                    targetDeviceID: device.id,
                    capability: capability,
                    command: "getStatus"
                )
            )
        ]
    }

    private func brightnessSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        guard (device.supportedCommands["switchLevel"] ?? []).contains("setLevel") else { return [] }
        return [
            CanonicalCommandSpec(
                id: "\(fixtureID).\(device.id).level.50",
                fixtureID: fixtureID,
                suite: "capability-command",
                tags: ["direct-command", "brightness", device.deviceType],
                category: .brightness,
                canonicalUtterance: "Set \(device.displayName) to 50 percent",
                deviceDisplayName: device.displayName,
                room: device.room,
                expected: ExpectedResolvedOutput(
                    operation: .executeDeviceCommand,
                    domain: .homeAutomation,
                    allowedOutcome: .ready,
                    expectedDeviceIDs: [device.id],
                    targetDeviceID: device.id,
                    capability: "switchLevel",
                    command: "setLevel",
                    parameters: ["level": "50"]
                )
            )
        ]
    }

    private func climateSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        guard (device.supportedCommands["thermostatCoolingSetpoint"] ?? []).contains("setCoolingSetpoint") else {
            return []
        }
        return [
            CanonicalCommandSpec(
                id: "\(fixtureID).\(device.id).cooling.24",
                fixtureID: fixtureID,
                suite: "capability-command",
                tags: ["direct-command", "climate", device.deviceType],
                category: .climate,
                canonicalUtterance: "Set \(device.displayName) to 24 degrees",
                deviceDisplayName: device.displayName,
                room: device.room,
                expected: ExpectedResolvedOutput(
                    operation: .executeDeviceCommand,
                    domain: .homeAutomation,
                    allowedOutcome: .ready,
                    expectedDeviceIDs: [device.id],
                    targetDeviceID: device.id,
                    capability: "thermostatCoolingSetpoint",
                    command: "setCoolingSetpoint",
                    parameters: ["coolingSetpoint": "24"]
                )
            )
        ]
    }

    private func mediaSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        guard (device.supportedCommands["mediaPlayback"] ?? []).contains("play") else {
            return []
        }
        return [
            CanonicalCommandSpec(
                id: "\(fixtureID).\(device.id).media.play",
                fixtureID: fixtureID,
                suite: "capability-command",
                tags: ["direct-command", "media", device.deviceType],
                category: .media,
                canonicalUtterance: "Play \(device.displayName)",
                deviceDisplayName: device.displayName,
                room: device.room,
                expected: ExpectedResolvedOutput(
                    operation: .executeDeviceCommand,
                    domain: .homeAutomation,
                    allowedOutcome: .ready,
                    expectedDeviceIDs: [device.id],
                    targetDeviceID: device.id,
                    capability: "mediaPlayback",
                    command: "play"
                )
            )
        ]
    }

    private func lockOpenCloseSpecs(for device: HomeCandidateRecord, fixtureID: String) -> [CanonicalCommandSpec] {
        if (device.supportedCommands["lock"] ?? []).contains("lock") {
            return ["lock", "unlock"].compactMap { command in
                guard (device.supportedCommands["lock"] ?? []).contains(command) else { return nil }
                return CanonicalCommandSpec(
                    id: "\(fixtureID).\(device.id).lock.\(command)",
                    fixtureID: fixtureID,
                    suite: "capability-command",
                    tags: ["direct-command", "security", device.deviceType],
                    category: .lockOpenClose,
                    canonicalUtterance: "\(command.capitalized) \(device.displayName)",
                    deviceDisplayName: device.displayName,
                    room: device.room,
                    expected: ExpectedResolvedOutput(
                        operation: .executeDeviceCommand,
                        domain: .homeAutomation,
                        allowedOutcome: command == "unlock" ? .confirmation : .ready,
                        expectedDeviceIDs: [device.id],
                        targetDeviceID: device.id,
                        capability: "lock",
                        command: command
                    )
                )
            }
        }
        if (device.supportedCommands["garageDoorControl"] ?? []).contains("open") {
            return ["open", "close"].compactMap { command in
                guard (device.supportedCommands["garageDoorControl"] ?? []).contains(command) else { return nil }
                return CanonicalCommandSpec(
                    id: "\(fixtureID).\(device.id).door.\(command)",
                    fixtureID: fixtureID,
                    suite: "capability-command",
                    tags: ["direct-command", "open-close", device.deviceType],
                    category: .lockOpenClose,
                    canonicalUtterance: "\(command.capitalized) \(device.displayName)",
                    deviceDisplayName: device.displayName,
                    room: device.room,
                    expected: ExpectedResolvedOutput(
                        operation: .executeDeviceCommand,
                        domain: .homeAutomation,
                        allowedOutcome: command == "open" ? .confirmation : .ready,
                        expectedDeviceIDs: [device.id],
                        targetDeviceID: device.id,
                        capability: "garageDoorControl",
                        command: command
                    )
                )
            }
        }
        return []
    }

    private func automationSpecs(for fixture: GeneratedEvaluationFixture) -> [CanonicalCommandSpec] {
        guard let actionDevice = fixture.devices.first(where: { ($0.supportedCommands["switch"] ?? []).contains("on") }) else {
            return []
        }
        let conditionDevice = fixture.devices.first(where: { device in
            device.supportedCommands.values.contains { $0.contains("getStatus") } && device.id != actionDevice.id
        })
        let conditionText = conditionDevice.map { " if \($0.displayName) is off" } ?? ""
        let conditionCount = conditionDevice == nil ? 0 : 1
        return [
            CanonicalCommandSpec(
                id: "\(fixture.id).automation.daily.\(actionDevice.id)",
                fixtureID: fixture.id,
                suite: conditionDevice == nil ? "trigger-resolution" : "condition-resolution",
                tags: ["automation", "schedule"] + (conditionDevice == nil ? [] : ["condition"]),
                category: conditionDevice == nil ? .scheduleAutomation : .conditionAutomation,
                canonicalUtterance: "Turn on \(actionDevice.displayName) every day at 7 AM\(conditionText)",
                deviceDisplayName: actionDevice.displayName,
                room: actionDevice.room,
                expected: ExpectedResolvedOutput(
                    operation: .automationCreation,
                    domain: .homeAutomation,
                    allowedOutcome: .drafted,
                    expectedDeviceIDs: [actionDevice.id],
                    targetDeviceID: actionDevice.id,
                    capability: "switch",
                    command: "on",
                    actionCount: 1,
                    conditionCount: conditionCount,
                    conditionTreeKind: conditionDevice == nil ? nil : "leaf"
                )
            )
        ]
    }

    private func unsupportedSpec(for fixture: GeneratedEvaluationFixture) -> CanonicalCommandSpec {
        CanonicalCommandSpec(
            id: "\(fixture.id).unsupported.weather",
            fixtureID: fixture.id,
            suite: "operation-routing",
            tags: ["unsupported"],
            category: .unsupported,
            canonicalUtterance: "Tell me tomorrow's weather",
            expected: ExpectedResolvedOutput(
                operation: .unsupported,
                domain: .unsupported,
                allowedOutcome: .unsupported
            )
        )
    }

    private func stableUniqueSpecs(_ specs: [CanonicalCommandSpec]) -> [CanonicalCommandSpec] {
        var seen: Set<String> = []
        var result: [CanonicalCommandSpec] = []
        for spec in specs where seen.insert(spec.id).inserted {
            result.append(spec)
        }
        return result
    }
}
