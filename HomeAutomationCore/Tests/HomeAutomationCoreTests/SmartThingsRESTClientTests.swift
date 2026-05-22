import Foundation
import HomeAutomationCore
import Testing

@Suite
struct SmartThingsRESTClientTests {
    @Test
    func clientCallsRequestedDeviceAndRoomEndpoints() async throws {
        let recorder = RequestRecorder()
        let client = SmartThingsRESTClient(bearerToken: "test-token") { request in
            await recorder.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/devices"):
                return response("""
                {"items":[{"deviceId":"dev-1","label":"Bedroom Lamp","locationId":"loc-1","roomId":"room-1","components":[{"id":"main","capabilities":[{"id":"switch","version":1}],"categories":[{"name":"light"}]}]}]}
                """)
            case ("GET", "/v1/devices/dev-1"):
                return response("""
                {"deviceId":"dev-1","label":"Bedroom Lamp","locationId":"loc-1","roomId":"room-1","components":[{"id":"main","capabilities":[{"id":"switch","version":1}],"categories":[{"name":"light"}]}]}
                """)
            case ("GET", "/v1/devices/dev-1/status"):
                return response("""
                {"components":{"main":{"switch":{"switch":{"value":"off","timestamp":"2026-05-22T00:00:00Z"}}}}}
                """)
            case ("POST", "/v1/devices/dev-1/commands"):
                return SmartThingsRESTClient.HTTPResponse(statusCode: 204)
            case ("GET", "/v1/locations/loc-1/rooms"):
                return response("""
                {"items":[{"roomId":"room-1","locationId":"loc-1","name":"Bedroom"}]}
                """)
            case ("GET", "/v1/locations/loc-1/rooms/room-1"):
                return response("""
                {"roomId":"room-1","locationId":"loc-1","name":"Bedroom"}
                """)
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return SmartThingsRESTClient.HTTPResponse(statusCode: 404, body: Data())
            }
        }

        let devices = try await client.getDevices(query: .init(locationID: "loc-1"))
        let device = try await client.getDevice(deviceID: "dev-1")
        let status = try await client.getDeviceStatus(deviceID: "dev-1")
        try await client.executeDeviceCommands(
            deviceID: "dev-1",
            request: .init(commands: [.init(capability: "switch", command: "on")])
        )
        let rooms = try await client.listRooms(locationID: "loc-1")
        let room = try await client.getRoom(locationID: "loc-1", roomID: "room-1")

        #expect(devices.items.first?.deviceID == "dev-1")
        #expect(device.label == "Bedroom Lamp")
        #expect(status.components["main"]?.capabilities["switch"]?.attributes["switch"]?.value == .string("off"))
        #expect(rooms.items.first?.name == "Bedroom")
        #expect(room.roomID == "room-1")

        let requests = await recorder.requests()
        #expect(requests.count == 6)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
        let commandRequest = try #require(requests.first { $0.httpMethod == "POST" })
        let commandBody = try #require(commandRequest.httpBody)
        let commandJSON = try #require(JSONSerialization.jsonObject(with: commandBody) as? [String: Any])
        let commands = try #require(commandJSON["commands"] as? [[String: Any]])
        #expect(commands.first?["component"] as? String == "main")
        #expect(commands.first?["capability"] as? String == "switch")
        #expect(commands.first?["command"] as? String == "on")
    }

    @Test
    func smartThingsRegistryMapsDevicesRoomsCapabilitiesAndStatus() async throws {
        let client = SmartThingsRESTClient(bearerToken: "test-token") { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/devices"):
                return response("""
                {"items":[{"deviceId":"dev-1","label":"Bedroom Lamp","locationId":"loc-1","roomId":"room-1","components":[{"id":"main","capabilities":[{"id":"switch","version":1},{"id":"switchLevel","version":1}],"categories":[{"name":"light"}]}]}]}
                """)
            case ("GET", "/v1/devices/dev-1/status"):
                return response("""
                {"components":{"main":{"switch":{"switch":{"value":"off"}},"switchLevel":{"level":{"value":35,"unit":"percent"}}}}}
                """)
            case ("GET", "/v1/locations/loc-1/rooms"):
                return response("""
                {"items":[{"roomId":"room-1","locationId":"loc-1","name":"Bedroom"}]}
                """)
            default:
                return SmartThingsRESTClient.HTTPResponse(statusCode: 404, body: Data())
            }
        }
        let registry = SmartThingsDeviceRegistry(
            client: client,
            options: .init(locationID: "loc-1", includeStatus: true)
        )

        let devices = await registry.allDevices()
        let device = try #require(devices.first)

        #expect(device.id == "dev-1")
        #expect(device.displayName == "Bedroom Lamp")
        #expect(device.deviceType == "light")
        #expect(device.room == "Bedroom")
        #expect(device.capabilities == ["switch", "switchLevel"])
        #expect(device.supportedCommands["switch"] == ["on", "off"])
        #expect(device.currentState["switch"] == "off")
        #expect(device.currentState["level"] == "35")
    }
}

private actor RequestRecorder {
    private var storage: [URLRequest] = []

    func append(_ request: URLRequest) {
        storage.append(request)
    }

    func requests() -> [URLRequest] {
        storage
    }
}

private func response(_ json: String) -> SmartThingsRESTClient.HTTPResponse {
    SmartThingsRESTClient.HTTPResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        body: Data(json.utf8)
    )
}
