import Foundation

public struct SmartThingsRESTClient: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String
    public typealias Transport = @Sendable (URLRequest) async throws -> HTTPResponse

    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let transport: Transport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://api.smartthings.com/v1")!,
        bearerToken: String,
        transport: @escaping Transport = SmartThingsRESTClient.urlSessionTransport
    ) {
        self.init(
            baseURL: baseURL,
            tokenProvider: { bearerToken },
            transport: transport
        )
    }

    public init(
        baseURL: URL = URL(string: "https://api.smartthings.com/v1")!,
        tokenProvider: @escaping TokenProvider,
        transport: @escaping Transport = SmartThingsRESTClient.urlSessionTransport
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func getDevices(query: DeviceListQuery = DeviceListQuery()) async throws -> DeviceListResponse {
        try await request(
            method: "GET",
            path: ["devices"],
            queryItems: query.queryItems,
            responseType: DeviceListResponse.self
        )
    }

    public func getDevice(deviceID: String) async throws -> Device {
        try await request(
            method: "GET",
            path: ["devices", deviceID],
            responseType: Device.self
        )
    }

    public func getDeviceStatus(deviceID: String) async throws -> DeviceStatusResponse {
        try await request(
            method: "GET",
            path: ["devices", deviceID, "status"],
            responseType: DeviceStatusResponse.self
        )
    }

    @discardableResult
    public func executeDeviceCommands(
        deviceID: String,
        request commandRequest: DeviceCommandsRequest
    ) async throws -> DeviceCommandsResponse {
        try await request(
            method: "POST",
            path: ["devices", deviceID, "commands"],
            body: commandRequest,
            responseType: DeviceCommandsResponse.self,
            emptyResponse: DeviceCommandsResponse(results: [])
        )
    }

    public func listRooms(locationID: String) async throws -> RoomListResponse {
        try await request(
            method: "GET",
            path: ["locations", locationID, "rooms"],
            responseType: RoomListResponse.self
        )
    }

    public func getRoom(locationID: String, roomID: String) async throws -> Room {
        try await request(
            method: "GET",
            path: ["locations", locationID, "rooms", roomID],
            responseType: Room.self
        )
    }

    private func request<Response: Decodable>(
        method: String,
        path: [String],
        queryItems: [URLQueryItem] = [],
        responseType: Response.Type,
        emptyResponse: Response? = nil
    ) async throws -> Response {
        try await request(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: nil,
            responseType: responseType,
            emptyResponse: emptyResponse
        )
    }

    private func request<Body: Encodable, Response: Decodable>(
        method: String,
        path: [String],
        queryItems: [URLQueryItem] = [],
        body: Body,
        responseType: Response.Type,
        emptyResponse: Response? = nil
    ) async throws -> Response {
        let bodyData = try encoder.encode(body)
        return try await request(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: bodyData,
            responseType: responseType,
            emptyResponse: emptyResponse
        )
    }

    private func request<Response: Decodable>(
        method: String,
        path: [String],
        queryItems: [URLQueryItem],
        bodyData: Data?,
        responseType: Response.Type,
        emptyResponse: Response? = nil
    ) async throws -> Response {
        let url = try url(path: path, queryItems: queryItems)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = bodyData
        }

        let response = try await transport(urlRequest)
        let responseBody = String(data: response.body, encoding: .utf8) ?? ""
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError(statusCode: response.statusCode, responseBody: responseBody)
        }

        guard !response.body.isEmpty else {
            if let emptyResponse {
                return emptyResponse
            }
            throw FoundationLabCoreError.invalidRequest("SmartThings API returned an empty response for \(method) \(url.path)")
        }

        do {
            return try decoder.decode(Response.self, from: response.body)
        } catch {
            throw DecodingFailure(
                endpoint: "\(method) \(url.path)",
                responseBody: responseBody,
                underlyingDescription: String(describing: error)
            )
        }
    }

    private func url(path: [String], queryItems: [URLQueryItem]) throws -> URL {
        let endpoint = path.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw FoundationLabCoreError.invalidRequest("Invalid SmartThings API URL")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw FoundationLabCoreError.invalidRequest("Invalid SmartThings API URL")
        }
        return url
    }

    public static func urlSessionTransport(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoundationLabCoreError.invalidRequest("SmartThings API returned a non-HTTP response")
        }
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partial, entry in
            guard let key = entry.key as? String else { return }
            partial[key] = String(describing: entry.value)
        }
        return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
    }
}

public extension SmartThingsRESTClient {
    struct HTTPResponse: Sendable, Hashable {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data

        public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    struct HTTPError: Error, Sendable, Hashable, LocalizedError {
        public let statusCode: Int
        public let responseBody: String

        public init(statusCode: Int, responseBody: String) {
            self.statusCode = statusCode
            self.responseBody = responseBody
        }

        public var errorDescription: String? {
            "SmartThings API request failed with HTTP \(statusCode): \(responseBody)"
        }
    }

    struct DecodingFailure: Error, Sendable, Hashable, LocalizedError {
        public let endpoint: String
        public let responseBody: String
        public let underlyingDescription: String

        public init(endpoint: String, responseBody: String, underlyingDescription: String) {
            self.endpoint = endpoint
            self.responseBody = responseBody
            self.underlyingDescription = underlyingDescription
        }

        public var errorDescription: String? {
            "Unable to decode SmartThings API response for \(endpoint): \(underlyingDescription)"
        }
    }

    struct DeviceListQuery: Sendable, Hashable {
        public let locationID: String?
        public let roomID: String?
        public let capability: String?
        public let capabilities: [String]
        public let deviceIDs: [String]

        public init(
            locationID: String? = nil,
            roomID: String? = nil,
            capability: String? = nil,
            capabilities: [String] = [],
            deviceIDs: [String] = []
        ) {
            self.locationID = locationID
            self.roomID = roomID
            self.capability = capability
            self.capabilities = capabilities
            self.deviceIDs = deviceIDs
        }

        var queryItems: [URLQueryItem] {
            var items: [URLQueryItem] = []
            if let locationID, !locationID.isEmpty {
                items.append(URLQueryItem(name: "locationId", value: locationID))
            }
            if let roomID, !roomID.isEmpty {
                items.append(URLQueryItem(name: "roomId", value: roomID))
            }
            if let capability, !capability.isEmpty {
                items.append(URLQueryItem(name: "capability", value: capability))
            }
            for capability in capabilities where !capability.isEmpty {
                items.append(URLQueryItem(name: "capabilities", value: capability))
            }
            for deviceID in deviceIDs where !deviceID.isEmpty {
                items.append(URLQueryItem(name: "deviceId", value: deviceID))
            }
            return items
        }
    }

    struct DeviceListResponse: Sendable, Hashable, Codable {
        public let items: [Device]
        public let links: Links?

        public init(items: [Device], links: Links? = nil) {
            self.items = items
            self.links = links
        }

        private enum CodingKeys: String, CodingKey {
            case items
            case links = "_links"
        }
    }

    struct Device: Sendable, Hashable, Codable {
        public let deviceID: String
        public let name: String?
        public let label: String?
        public let manufacturerName: String?
        public let presentationID: String?
        public let deviceManufacturerCode: String?
        public let locationID: String?
        public let roomID: String?
        public let deviceTypeID: String?
        public let deviceTypeName: String?
        public let type: String?
        public let restrictionTier: Int?
        public let allowed: [String]?
        public let components: [Component]?
        public let profile: DeviceProfile?
        public let owner: DeviceOwner?
        public let createdDate: String?
        public let lastUpdatedDate: String?

        public init(
            deviceID: String,
            name: String? = nil,
            label: String? = nil,
            manufacturerName: String? = nil,
            presentationID: String? = nil,
            deviceManufacturerCode: String? = nil,
            locationID: String? = nil,
            roomID: String? = nil,
            deviceTypeID: String? = nil,
            deviceTypeName: String? = nil,
            type: String? = nil,
            restrictionTier: Int? = nil,
            allowed: [String]? = nil,
            components: [Component]? = nil,
            profile: DeviceProfile? = nil,
            owner: DeviceOwner? = nil,
            createdDate: String? = nil,
            lastUpdatedDate: String? = nil
        ) {
            self.deviceID = deviceID
            self.name = name
            self.label = label
            self.manufacturerName = manufacturerName
            self.presentationID = presentationID
            self.deviceManufacturerCode = deviceManufacturerCode
            self.locationID = locationID
            self.roomID = roomID
            self.deviceTypeID = deviceTypeID
            self.deviceTypeName = deviceTypeName
            self.type = type
            self.restrictionTier = restrictionTier
            self.allowed = allowed
            self.components = components
            self.profile = profile
            self.owner = owner
            self.createdDate = createdDate
            self.lastUpdatedDate = lastUpdatedDate
        }

        private enum CodingKeys: String, CodingKey {
            case deviceID = "deviceId"
            case name
            case label
            case manufacturerName
            case presentationID = "presentationId"
            case deviceManufacturerCode
            case locationID = "locationId"
            case roomID = "roomId"
            case deviceTypeID = "deviceTypeId"
            case deviceTypeName
            case type
            case restrictionTier
            case allowed
            case components
            case profile
            case owner
            case createdDate
            case lastUpdatedDate
        }
    }

    struct Component: Sendable, Hashable, Codable {
        public let id: String
        public let label: String?
        public let capabilities: [Capability]
        public let categories: [Category]?

        public init(
            id: String,
            label: String? = nil,
            capabilities: [Capability] = [],
            categories: [Category]? = nil
        ) {
            self.id = id
            self.label = label
            self.capabilities = capabilities
            self.categories = categories
        }
    }

    struct Capability: Sendable, Hashable, Codable {
        public let id: String
        public let version: Int?

        public init(id: String, version: Int? = nil) {
            self.id = id
            self.version = version
        }
    }

    struct Category: Sendable, Hashable, Codable {
        public let name: String
        public let categoryType: String?

        public init(name: String, categoryType: String? = nil) {
            self.name = name
            self.categoryType = categoryType
        }
    }

    struct DeviceProfile: Sendable, Hashable, Codable {
        public let id: String?

        public init(id: String? = nil) {
            self.id = id
        }
    }

    struct DeviceOwner: Sendable, Hashable, Codable {
        public let ownerType: String?
        public let ownerID: String?

        public init(ownerType: String? = nil, ownerID: String? = nil) {
            self.ownerType = ownerType
            self.ownerID = ownerID
        }

        private enum CodingKeys: String, CodingKey {
            case ownerType
            case ownerID = "ownerId"
        }
    }

    struct DeviceStatusResponse: Sendable, Hashable, Codable {
        public let components: [String: ComponentStatus]

        public init(components: [String: ComponentStatus]) {
            self.components = components
        }
    }

    struct ComponentStatus: Sendable, Hashable, Codable {
        public let capabilities: [String: CapabilityStatus]

        public init(capabilities: [String: CapabilityStatus]) {
            self.capabilities = capabilities
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.capabilities = try container.decode([String: CapabilityStatus].self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(capabilities)
        }
    }

    struct CapabilityStatus: Sendable, Hashable, Codable {
        public let attributes: [String: AttributeState]

        public init(attributes: [String: AttributeState]) {
            self.attributes = attributes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.attributes = try container.decode([String: AttributeState].self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(attributes)
        }
    }

    struct AttributeState: Sendable, Hashable, Codable {
        public let value: SmartThingsRuleJSONValue?
        public let unit: String?
        public let data: SmartThingsRuleJSONValue?
        public let timestamp: String?

        public init(
            value: SmartThingsRuleJSONValue? = nil,
            unit: String? = nil,
            data: SmartThingsRuleJSONValue? = nil,
            timestamp: String? = nil
        ) {
            self.value = value
            self.unit = unit
            self.data = data
            self.timestamp = timestamp
        }
    }

    struct DeviceCommandsRequest: Sendable, Hashable, Codable {
        public let commands: [DeviceCommand]

        public init(commands: [DeviceCommand]) {
            self.commands = commands
        }
    }

    struct DeviceCommand: Sendable, Hashable, Codable {
        public let component: String
        public let capability: String
        public let command: String
        public let arguments: [SmartThingsRuleJSONValue]

        public init(
            component: String = "main",
            capability: String,
            command: String,
            arguments: [SmartThingsRuleJSONValue] = []
        ) {
            self.component = component
            self.capability = capability
            self.command = command
            self.arguments = arguments
        }
    }

    struct DeviceCommandsResponse: Sendable, Hashable, Codable {
        public let results: [DeviceCommandResult]?

        public init(results: [DeviceCommandResult]? = nil) {
            self.results = results
        }
    }

    struct DeviceCommandResult: Sendable, Hashable, Codable {
        public let id: String?
        public let status: String?
        public let component: String?
        public let capability: String?
        public let command: String?

        public init(
            id: String? = nil,
            status: String? = nil,
            component: String? = nil,
            capability: String? = nil,
            command: String? = nil
        ) {
            self.id = id
            self.status = status
            self.component = component
            self.capability = capability
            self.command = command
        }
    }

    struct RoomListResponse: Sendable, Hashable, Codable {
        public let items: [Room]
        public let links: Links?

        public init(items: [Room], links: Links? = nil) {
            self.items = items
            self.links = links
        }

        private enum CodingKeys: String, CodingKey {
            case items
            case links = "_links"
        }
    }

    struct Room: Sendable, Hashable, Codable {
        public let roomID: String
        public let locationID: String?
        public let name: String?
        public let backgroundImage: String?

        public init(
            roomID: String,
            locationID: String? = nil,
            name: String? = nil,
            backgroundImage: String? = nil
        ) {
            self.roomID = roomID
            self.locationID = locationID
            self.name = name
            self.backgroundImage = backgroundImage
        }

        private enum CodingKeys: String, CodingKey {
            case roomID = "roomId"
            case locationID = "locationId"
            case name
            case backgroundImage
        }
    }

    struct Links: Sendable, Hashable, Codable {
        public let next: Link?
        public let previous: Link?
        public let selfLink: Link?

        public init(next: Link? = nil, previous: Link? = nil, selfLink: Link? = nil) {
            self.next = next
            self.previous = previous
            self.selfLink = selfLink
        }

        private enum CodingKeys: String, CodingKey {
            case next
            case previous
            case selfLink = "self"
        }
    }

    struct Link: Sendable, Hashable, Codable {
        public let href: String

        public init(href: String) {
            self.href = href
        }
    }
}
