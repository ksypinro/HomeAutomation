import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum PreparedRegistryFreshness: String, Sendable, Codable, Hashable {
    case fresh
    case stale
    case unknown
    case unavailable
}

public enum PreparedOrchestrationDiagnosticCode: String, Sendable, Codable, Hashable {
    case cancelled
    case extractionFailed
}

public struct PreparedOrchestrationDiagnostic: Sendable, Codable, Hashable {
    public let code: PreparedOrchestrationDiagnosticCode
    public let source: PortfolioFeatureSource
    public let detail: String

    public init(
        code: PreparedOrchestrationDiagnosticCode,
        source: PortfolioFeatureSource,
        detail: String
    ) {
        self.code = code
        self.source = source
        self.detail = detail
    }
}

public struct PreparedCommandRequestMetadata: Sendable, Codable, Hashable {
    public let text: String
    public let executeLowRiskCommands: Bool
    public let automationCreationMode: String
    public let timestamp: Date

    public init(request: CommandRequest) {
        self.text = request.text
        self.executeLowRiskCommands = request.executeLowRiskCommands
        self.automationCreationMode = request.automationCreationOptions.mode.rawValue
        self.timestamp = request.timestamp
    }
}

public struct PreparedDeviceSnapshot: Sendable, Codable, Hashable {
    public struct DeviceSummary: Sendable, Codable, Hashable {
        public let id: String
        public let type: HomeCandidateType
        public let deviceType: String
        public let capabilityIDs: [String]
        public let supportedCommandCount: Int
        public let supportedModeCount: Int
        public let riskLevel: HomeAutomationRiskLevel

        public init(device: HomeCandidateRecord) {
            self.id = device.id
            self.type = device.type
            self.deviceType = device.deviceType
            self.capabilityIDs = device.capabilities.sorted()
            self.supportedCommandCount = device.supportedCommands.values.reduce(0) { $0 + $1.count }
            self.supportedModeCount = device.supportedModes.count
            self.riskLevel = device.riskLevel
        }
    }

    public let version: String
    public let devices: [HomeCandidateRecord]
    public let summaries: [DeviceSummary]

    public init(devices: [HomeCandidateRecord]) {
        self.devices = devices.sorted { lhs, rhs in
            if lhs.id == rhs.id { return lhs.deviceType < rhs.deviceType }
            return lhs.id < rhs.id
        }
        self.summaries = self.devices.map(DeviceSummary.init(device:))
        self.version = Self.fingerprint(for: summaries)
    }

    public func freshness(comparedTo current: PreparedDeviceSnapshot?) -> PreparedRegistryFreshness {
        guard let current else { return .unknown }
        return current.version == version ? .fresh : .stale
    }

    public static func fingerprint(for summaries: [DeviceSummary]) -> String {
        let payload = summaries
            .map { summary in
                [
                    summary.id,
                    "\(summary.type)",
                    summary.deviceType,
                    summary.capabilityIDs.joined(separator: ","),
                    String(summary.supportedCommandCount),
                    String(summary.supportedModeCount),
                    "\(summary.riskLevel)",
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        return fnv1a64(payload)
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public struct PreparedOrchestrationRequest: Sendable, Codable, Hashable {
    public let request: PreparedCommandRequestMetadata
    public let featureSnapshot: PortfolioFeatureSnapshot
    public let deterministicEnvelope: DraftEnvelope
    public let deviceSnapshot: PreparedDeviceSnapshot
    public let memoryReferenceDetected: Bool
    public let memoryHints: [MemoryHint]
    public let resolutionState: HomeResolutionState
    public let candidateIDs: [String]
    public let registryVersion: String
    public let diagnostics: [PreparedOrchestrationDiagnostic]

    public init(
        request: PreparedCommandRequestMetadata,
        featureSnapshot: PortfolioFeatureSnapshot,
        deterministicEnvelope: DraftEnvelope,
        deviceSnapshot: PreparedDeviceSnapshot,
        memoryReferenceDetected: Bool,
        memoryHints: [MemoryHint],
        resolutionState: HomeResolutionState,
        candidateIDs: [String],
        diagnostics: [PreparedOrchestrationDiagnostic] = []
    ) {
        self.request = request
        self.featureSnapshot = featureSnapshot
        self.deterministicEnvelope = deterministicEnvelope
        self.deviceSnapshot = deviceSnapshot
        self.memoryReferenceDetected = memoryReferenceDetected
        self.memoryHints = memoryHints
        self.resolutionState = resolutionState
        self.candidateIDs = candidateIDs
        self.registryVersion = deviceSnapshot.version
        self.diagnostics = diagnostics
    }

    public func registryFreshness(
        comparedTo currentSnapshot: PreparedDeviceSnapshot?
    ) -> PreparedRegistryFreshness {
        deviceSnapshot.freshness(comparedTo: currentSnapshot)
    }
}
