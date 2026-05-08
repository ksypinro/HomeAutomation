import Foundation
import HomeAutomationCore
import HomeAutomationRAG

public struct LanguageAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeLanguageDetectionResult

    public let id = AgentID.language
    public let capabilities: Set<AgentCapability> = [.languageDetection]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let detect: @Sendable (String) async throws -> HomeLanguageDetectionResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        detect: @escaping @Sendable (String) async throws -> HomeLanguageDetectionResult
    ) {
        self.detect = detect
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.detect = worker.detectLanguage
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeLanguageDetectionResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "language detection", contextRetriever: contextRetriever)
        return try await detect(enrichedInput)
    }
}

public struct DomainAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeDomainClassificationResult

    public let id = AgentID.domain
    public let capabilities: Set<AgentCapability> = [.domainClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeDomainClassificationResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeDomainClassificationResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyDomain
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeDomainClassificationResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "domain classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}

public struct IntentFamilyAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeIntentFamilyResult

    public let id = AgentID.intentFamily
    public let capabilities: Set<AgentCapability> = [.intentClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeIntentFamilyResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeIntentFamilyResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyIntentFamily
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeIntentFamilyResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "intent family classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}

public struct DeviceTypeAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeDeviceTypeResult

    public let id = AgentID.deviceType
    public let capabilities: Set<AgentCapability> = [.deviceTypeExtraction]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeDeviceTypeResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeDeviceTypeResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyDeviceType
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeDeviceTypeResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "device type extraction", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}

public struct SlotExtractionAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeSlotExtractionResult

    public let id = AgentID.slotExtraction
    public let capabilities: Set<AgentCapability> = [.slotExtraction]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let extract: @Sendable (String) async throws -> HomeSlotExtractionResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        extract: @escaping @Sendable (String) async throws -> HomeSlotExtractionResult
    ) {
        self.extract = extract
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.extract = worker.extractSlots
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeSlotExtractionResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "slot extraction", contextRetriever: contextRetriever)
        return try await extract(enrichedInput)
    }
}

public struct RiskClassificationAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeRiskClassificationResult

    public let id = AgentID.riskClassification
    public let capabilities: Set<AgentCapability> = [.riskClassification]
    public let timeoutNanoseconds: UInt64 = 10_000_000_000
    private let classify: @Sendable (String) async throws -> HomeRiskClassificationResult
    private let contextRetriever: ContextRetriever?

    public init(
        contextRetriever: ContextRetriever? = nil,
        classify: @escaping @Sendable (String) async throws -> HomeRiskClassificationResult
    ) {
        self.classify = classify
        self.contextRetriever = contextRetriever
    }

    public init(
        worker: HomeAgentWorkerSessionSupport = HomeAgentWorkerSessionSupport(),
        contextRetriever: ContextRetriever? = nil
    ) {
        self.classify = worker.classifyRisk
        self.contextRetriever = contextRetriever
    }

    public func run(_ input: String, context: ResolutionContext) async throws -> HomeRiskClassificationResult {
        let enrichedInput = await AgentRAGSupport.nluInput(input, task: "risk classification", contextRetriever: contextRetriever)
        return try await classify(enrichedInput)
    }
}
