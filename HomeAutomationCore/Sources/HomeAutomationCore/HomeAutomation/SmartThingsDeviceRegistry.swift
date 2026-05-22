import Foundation

public actor SmartThingsDeviceRegistry: DeviceRegistryProtocol {
    public struct Options: Sendable, Hashable {
        public let locationID: String?
        public let includeStatus: Bool

        public init(locationID: String? = nil, includeStatus: Bool = true) {
            self.locationID = locationID
            self.includeStatus = includeStatus
        }
    }

    private let client: SmartThingsRESTClient
    private let options: Options
    private var cachedDevices: [HomeCandidateRecord] = []
    private var lastRefreshError: Error?

    public init(
        client: SmartThingsRESTClient,
        options: Options = Options()
    ) {
        self.client = client
        self.options = options
    }

    public init(
        bearerToken: String,
        baseURL: URL = URL(string: "https://api.smartthings.com/v1")!,
        options: Options = Options()
    ) {
        self.init(
            client: SmartThingsRESTClient(baseURL: baseURL, bearerToken: bearerToken),
            options: options
        )
    }

    public func allDevices() async -> [HomeCandidateRecord] {
        do {
            let devices = try await refreshDevices()
            return devices
        } catch {
            lastRefreshError = error
            return cachedDevices
        }
    }

    public func refreshDevices() async throws -> [HomeCandidateRecord] {
        let response = try await client.getDevices(
            query: SmartThingsRESTClient.DeviceListQuery(locationID: options.locationID)
        )
        let devices = response.items
        async let rooms = roomNameMap(for: devices)
        async let statuses = statusMap(for: devices)
        let roomMap = await rooms
        let deviceStatusMap = options.includeStatus ? await statuses : [:]
        let mapped = mapDevices(
            devices,
            rooms: roomMap,
            statuses: deviceStatusMap
        )
        cachedDevices = mapped
        lastRefreshError = nil
        return mapped
    }

    public func lastError() -> Error? {
        lastRefreshError
    }

    public func executeLowRiskPlan(_ plan: HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord {
        let commandSteps = plan.steps.filter { $0.type == "command" }
        guard !commandSteps.isEmpty else {
            throw FoundationLabCoreError.invalidRequest("Missing SmartThings command step")
        }

        for step in commandSteps {
            let value = try await resolvedValue(for: step)
            let arguments = value.map { [Self.jsonValue(from: $0)] } ?? []
            let command = SmartThingsRESTClient.DeviceCommand(
                component: "main",
                capability: step.capability,
                command: step.command,
                arguments: arguments
            )
            try await client.executeDeviceCommands(
                deviceID: step.deviceID,
                request: SmartThingsRESTClient.DeviceCommandsRequest(commands: [command])
            )
        }

        guard let lastStep = commandSteps.last else {
            throw FoundationLabCoreError.invalidRequest("Missing SmartThings command step")
        }

        let device = try await client.getDevice(deviceID: lastStep.deviceID)
        let status = try? await client.getDeviceStatus(deviceID: lastStep.deviceID)
        let rooms = await roomNameMap(for: [device])
        return mapDevice(device, roomName: rooms[device.roomID ?? ""], status: status)
    }

    private func roomNameMap(
        for devices: [SmartThingsRESTClient.Device]
    ) async -> [String: String] {
        let locationIDs = Set(([options.locationID] + devices.map(\.locationID)).compactMap { $0 })
        guard !locationIDs.isEmpty else { return [:] }
        let client = self.client

        return await withTaskGroup(of: [String: String].self) { group in
            for locationID in locationIDs {
                group.addTask {
                    do {
                        let response = try await client.listRooms(locationID: locationID)
                        return Dictionary(
                            uniqueKeysWithValues: response.items.compactMap { room in
                                guard !room.roomID.isEmpty else { return nil }
                                return (room.roomID, room.name ?? room.roomID)
                            }
                        )
                    } catch {
                        return [:]
                    }
                }
            }

            var merged: [String: String] = [:]
            for await partial in group {
                merged.merge(partial) { current, _ in current }
            }
            return merged
        }
    }

    private func statusMap(
        for devices: [SmartThingsRESTClient.Device]
    ) async -> [String: SmartThingsRESTClient.DeviceStatusResponse] {
        guard options.includeStatus else { return [:] }
        let client = self.client

        return await withTaskGroup(of: (String, SmartThingsRESTClient.DeviceStatusResponse?).self) { group in
            for device in devices {
                group.addTask {
                    do {
                        return (device.deviceID, try await client.getDeviceStatus(deviceID: device.deviceID))
                    } catch {
                        return (device.deviceID, nil)
                    }
                }
            }

            var statuses: [String: SmartThingsRESTClient.DeviceStatusResponse] = [:]
            for await (deviceID, status) in group {
                if let status {
                    statuses[deviceID] = status
                }
            }
            return statuses
        }
    }

    private func mapDevices(
        _ devices: [SmartThingsRESTClient.Device],
        rooms: [String: String],
        statuses: [String: SmartThingsRESTClient.DeviceStatusResponse]
    ) -> [HomeCandidateRecord] {
        devices.map { device in
            mapDevice(
                device,
                roomName: device.roomID.flatMap { rooms[$0] },
                status: statuses[device.deviceID]
            )
        }
    }

    private func mapDevice(
        _ device: SmartThingsRESTClient.Device,
        roomName: String?,
        status: SmartThingsRESTClient.DeviceStatusResponse?
    ) -> HomeCandidateRecord {
        let components = device.components ?? []
        let capabilities = unique(components.flatMap { component in
            component.capabilities.map(\.id)
        })
        let categories = unique(components.flatMap { component in
            component.categories?.map(\.name) ?? []
        })
        let displayName = firstNonEmpty(device.label, device.name, device.deviceID) ?? device.deviceID
        let inferredDeviceType = HomeDeviceTypeInferencer.infer(
            deviceName: displayName,
            capabilities: capabilities,
            categoryNames: categories,
            deviceTypeName: device.deviceTypeName,
            deviceTypeID: device.deviceTypeID,
            smartThingsType: device.type,
            profileID: device.profile?.id,
            presentationID: device.presentationID,
            manufacturerName: device.manufacturerName
        )
        let metadata = compactMetadata([
            "smartThingsDeviceId": device.deviceID,
            "smartThingsLocationId": device.locationID,
            "smartThingsRoomId": device.roomID,
            "smartThingsDeviceTypeId": device.deviceTypeID,
            "smartThingsDeviceTypeName": device.deviceTypeName,
            "smartThingsType": device.type,
            "smartThingsManufacturer": device.manufacturerName,
            "smartThingsPresentationId": device.presentationID,
            "smartThingsProfileId": device.profile?.id,
            "smartThingsOwnerId": device.owner?.ownerID,
            "smartThingsOwnerType": device.owner?.ownerType,
            "smartThingsCategories": categories.isEmpty ? nil : categories.joined(separator: ","),
            "inferredDeviceTypeConfidence": String(inferredDeviceType.confidence),
            "inferredDeviceTypeEvidence": inferredDeviceType.evidence.joined(separator: " | ")
        ])
        let riskLevel = capabilities
            .map { HomeCapabilityRegistry.riskLevel(for: $0) }
            .maxBySmartThingsRegistrySeverity()

        return HomeCandidateRecord(
            id: device.deviceID,
            type: .device,
            displayName: displayName,
            deviceType: inferredDeviceType.deviceType,
            room: roomName,
            capabilities: capabilities,
            supportedCommands: HomeCapabilityRegistry.supportedCommands(for: capabilities),
            supportedModes: HomeCapabilityRegistry.supportedModes(for: capabilities),
            currentState: status?.flatState ?? [:],
            metadata: metadata,
            riskLevel: riskLevel
        )
    }

    private func resolvedValue(for step: HomeAutomationExecutionStep) async throws -> String? {
        guard let formula = step.valueFormula?.trimmingCharacters(in: .whitespacesAndNewlines),
              !formula.isEmpty else {
            return step.value
        }

        let parts = formula.split(separator: " ").map(String.init)
        guard parts.count == 3,
              parts[0] == "current",
              parts[1] == "+" || parts[1] == "-",
              let delta = Double(parts[2]) else {
            throw FoundationLabCoreError.invalidRequest("Unsupported value formula")
        }

        let status = try await client.getDeviceStatus(deviceID: step.deviceID)
        let state = status.flatState
        let attribute = step.attribute ?? HomeCapabilityRegistry.definitions[step.capability]?.attributeNames.first ?? step.capability
        guard let currentValue = state[attribute],
              let current = Double(currentValue) else {
            throw FoundationLabCoreError.invalidRequest("Unable to resolve current value for formula")
        }

        let resolved = parts[1] == "+" ? current + delta : current - delta
        if resolved.rounded() == resolved {
            return String(Int(resolved))
        }
        return String(resolved)
    }

    private static func jsonValue(from string: String) -> SmartThingsRuleJSONValue {
        if let integer = Int(string) {
            return .integer(integer)
        }
        if let decimal = Double(string) {
            return .decimal(decimal)
        }
        if string == "true" {
            return .bool(true)
        }
        if string == "false" {
            return .bool(false)
        }
        return .string(string)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }

    private func compactMetadata(_ pairs: [String: String?]) -> [String: String] {
        pairs.reduce(into: [String: String]()) { partial, entry in
            guard let value = entry.value, !value.isEmpty else { return }
            partial[entry.key] = value
        }
    }
}

private extension SmartThingsRESTClient.DeviceStatusResponse {
    var flatState: [String: String] {
        components.values.reduce(into: [String: String]()) { partial, component in
            for capability in component.capabilities.values {
                for (attributeName, state) in capability.attributes {
                    if let value = state.value?.smartThingsRegistryDisplayString {
                        partial[attributeName] = value
                    }
                }
            }
        }
    }
}

private extension SmartThingsRuleJSONValue {
    var smartThingsRegistryDisplayString: String? {
        switch self {
        case .null:
            return nil
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return String(value)
        case .array, .object:
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}

private extension [HomeAutomationRiskLevel] {
    func maxBySmartThingsRegistrySeverity() -> HomeAutomationRiskLevel {
        self.max { lhs, rhs in
            lhs.smartThingsRegistrySeverity < rhs.smartThingsRegistrySeverity
        } ?? .low
    }
}

private extension HomeAutomationRiskLevel {
    var smartThingsRegistrySeverity: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}
