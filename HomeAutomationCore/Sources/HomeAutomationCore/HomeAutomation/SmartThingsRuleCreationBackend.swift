import Foundation

public enum SmartThingsRuleCreationMode: String, Sendable, Hashable, Codable {
    case dryRun
    case create
}

public struct SmartThingsRuleCreationOptions: Sendable, Hashable, Codable {
    public let mode: SmartThingsRuleCreationMode
    public let locationID: String?
    public let confirmsHighRiskAutomation: Bool

    public init(
        mode: SmartThingsRuleCreationMode,
        locationID: String? = nil,
        confirmsHighRiskAutomation: Bool = false
    ) {
        self.mode = mode
        self.locationID = locationID
        self.confirmsHighRiskAutomation = confirmsHighRiskAutomation
    }

    public static let dryRun = SmartThingsRuleCreationOptions(mode: .dryRun)

    public static func create(
        locationID: String,
        confirmsHighRiskAutomation: Bool = false
    ) -> SmartThingsRuleCreationOptions {
        SmartThingsRuleCreationOptions(
            mode: .create,
            locationID: locationID,
            confirmsHighRiskAutomation: confirmsHighRiskAutomation
        )
    }
}

public enum SmartThingsRuleCreationStatus: String, Sendable, Hashable, Codable {
    case created
    case skipped
    case confirmationRequired
    case failed
}

public struct SmartThingsRuleCreationReceipt: Sendable, Hashable, Codable {
    public let status: SmartThingsRuleCreationStatus
    public let ruleID: String?
    public let locationID: String?
    public let requestID: String?
    public let message: String
    public let createdAt: Date?
    public let rawResponse: String?

    public init(
        status: SmartThingsRuleCreationStatus,
        ruleID: String? = nil,
        locationID: String? = nil,
        requestID: String? = nil,
        message: String,
        createdAt: Date? = nil,
        rawResponse: String? = nil
    ) {
        self.status = status
        self.ruleID = ruleID
        self.locationID = locationID
        self.requestID = requestID
        self.message = message
        self.createdAt = createdAt
        self.rawResponse = rawResponse
    }
}

public struct SmartThingsRuleCreationRequest: Sendable {
    public let document: SmartThingsRuleDocument
    public let locationID: String
    public let plan: HomeAutomationCreationPlan

    public init(
        document: SmartThingsRuleDocument,
        locationID: String,
        plan: HomeAutomationCreationPlan
    ) {
        self.document = document
        self.locationID = locationID
        self.plan = plan
    }
}

public protocol SmartThingsRuleCreating: Sendable {
    func createRule(_ request: SmartThingsRuleCreationRequest) async throws -> SmartThingsRuleCreationReceipt
}

public struct SmartThingsRuleCreationHTTPResponse: Sendable, Hashable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct SmartThingsRuleCreationHTTPError: Error, Sendable, Hashable, LocalizedError {
    public let statusCode: Int
    public let responseBody: String

    public init(statusCode: Int, responseBody: String) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    public var errorDescription: String? {
        "SmartThings rule creation failed with HTTP \(statusCode): \(responseBody)"
    }
}

public struct SmartThingsHTTPRuleCreator: SmartThingsRuleCreating {
    public typealias Transport = @Sendable (URLRequest) async throws -> SmartThingsRuleCreationHTTPResponse

    private let baseURL: URL
    private let bearerToken: String
    private let transport: Transport

    public init(
        bearerToken: String,
        baseURL: URL = URL(string: "https://api.smartthings.com/v1")!,
        transport: @escaping Transport = SmartThingsHTTPRuleCreator.urlSessionTransport
    ) {
        self.bearerToken = bearerToken
        self.baseURL = baseURL
        self.transport = transport
    }

    public func createRule(_ request: SmartThingsRuleCreationRequest) async throws -> SmartThingsRuleCreationReceipt {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rules"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "locationId", value: request.locationID)
        ]
        guard let url = components?.url else {
            throw FoundationLabCoreError.invalidRequest("Invalid SmartThings Rules API URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = Data(request.document.jsonString.utf8)

        let response = try await transport(urlRequest)
        let responseBody = String(data: response.body, encoding: .utf8) ?? ""
        guard (200..<300).contains(response.statusCode) else {
            throw SmartThingsRuleCreationHTTPError(
                statusCode: response.statusCode,
                responseBody: responseBody
            )
        }

        return SmartThingsRuleCreationReceipt(
            status: .created,
            ruleID: Self.extractRuleID(from: response.body),
            locationID: request.locationID,
            requestID: Self.requestID(from: response.headers),
            message: "SmartThings rule created.",
            createdAt: Date(),
            rawResponse: responseBody.isEmpty ? nil : responseBody
        )
    }

    public static func urlSessionTransport(_ request: URLRequest) async throws -> SmartThingsRuleCreationHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoundationLabCoreError.invalidRequest("SmartThings Rules API returned a non-HTTP response")
        }
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partial, entry in
            guard let key = entry.key as? String else { return }
            partial[key] = String(describing: entry.value)
        }
        return SmartThingsRuleCreationHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data
        )
    }

    private static func extractRuleID(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["ruleId"] as? String ??
            object["ruleID"] as? String ??
            object["id"] as? String
    }

    private static func requestID(from headers: [String: String]) -> String? {
        for key in ["x-request-id", "X-Request-ID", "X-Request-Id"] {
            if let value = headers[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
