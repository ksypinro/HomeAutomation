import Foundation

public struct FoundationModelBatchItemID: Sendable, Codable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum FoundationModelBatchPrivacyClass: String, Sendable, Codable, Hashable {
    case localOnly
    case privateUserData
    case deviceMetadata
    case unknown
}

public struct FoundationModelBatchCompatibilityKey: Sendable, Codable, Hashable {
    public let runID: String?
    public let modelProvider: String
    public let instructionDigest: String
    public let responseSchemaDigest: String
    public let toolSetDigest: String
    public let locale: String
    public let policyVersion: String
    public let privacyClass: FoundationModelBatchPrivacyClass
    public let workflowScopeID: String?

    public init(
        runID: String? = nil,
        modelProvider: String = "foundationModels",
        instructionDigest: String,
        responseSchemaDigest: String,
        toolSetDigest: String = "none",
        locale: String = Locale.current.identifier,
        policyVersion: String = "default",
        privacyClass: FoundationModelBatchPrivacyClass = .unknown,
        workflowScopeID: String? = nil
    ) {
        self.runID = runID
        self.modelProvider = modelProvider
        self.instructionDigest = instructionDigest
        self.responseSchemaDigest = responseSchemaDigest
        self.toolSetDigest = toolSetDigest
        self.locale = locale
        self.policyVersion = policyVersion
        self.privacyClass = privacyClass
        self.workflowScopeID = workflowScopeID
    }

    public var digest: String {
        Self.stableDigest([
            runID ?? "none",
            modelProvider,
            instructionDigest,
            responseSchemaDigest,
            toolSetDigest,
            locale,
            policyVersion,
            privacyClass.rawValue,
            workflowScopeID ?? "none"
        ].joined(separator: "|"))
    }

    public static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public struct FoundationModelBatchContext: Sendable, Codable, Hashable {
    public let batchID: String
    public let itemCount: Int
    public let compatibilityDigest: String
    public let coalescingDelayMs: Double

    public init(
        batchID: String,
        itemCount: Int,
        compatibilityDigest: String,
        coalescingDelayMs: Double = 0
    ) {
        self.batchID = batchID
        self.itemCount = itemCount
        self.compatibilityDigest = compatibilityDigest
        self.coalescingDelayMs = coalescingDelayMs
    }
}

public enum FoundationModelBatchContextScope {
    @TaskLocal public static var current: FoundationModelBatchContext?
}
