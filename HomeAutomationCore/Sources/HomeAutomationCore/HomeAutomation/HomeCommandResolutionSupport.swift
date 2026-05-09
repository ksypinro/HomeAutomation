import Foundation
import FoundationModels

public protocol HomeCommandResolving: Sendable {
    func resolve(_ text: String, executeLowRiskCommands: Bool) async throws -> HomeAutomationResolverResult
}

public protocol HomeCommandDraftResolving: Sendable {
    func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft
}

public protocol HomeAdapterModelSourcing: Sendable {
    func adapterConfiguration() -> HomeAdapterModelConfiguration?
}

public struct HomeAdapterModelConfiguration: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case file
        case name
        case bundle
        case injectedURL
        case backgroundAsset
    }

    public let source: Source
    public let identifier: String
    public let fileURL: URL?

    public init(source: Source, identifier: String, fileURL: URL? = nil) {
        self.source = source
        self.identifier = identifier
        self.fileURL = fileURL
    }
}

public struct HomeEnvironmentAdapterModelSource: HomeAdapterModelSourcing {
    public init() {}

    public func adapterConfiguration() -> HomeAdapterModelConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        if let adapterFile = environment["HOME_AUTOMATION_ADAPTER_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !adapterFile.isEmpty {
            return HomeAdapterModelConfiguration(
                source: .file,
                identifier: adapterFile,
                fileURL: URL(filePath: adapterFile)
            )
        }

        if let adapterName = environment["HOME_AUTOMATION_ADAPTER_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !adapterName.isEmpty {
            return HomeAdapterModelConfiguration(source: .name, identifier: adapterName)
        }

        return nil
    }
}

public struct HomeStaticAdapterModelSource: HomeAdapterModelSourcing {
    private let configuration: HomeAdapterModelConfiguration?

    public init(configuration: HomeAdapterModelConfiguration?) {
        self.configuration = configuration
    }

    public static func file(_ url: URL, source: HomeAdapterModelConfiguration.Source = .injectedURL) -> HomeStaticAdapterModelSource {
        HomeStaticAdapterModelSource(
            configuration: HomeAdapterModelConfiguration(
                source: source,
                identifier: url.path,
                fileURL: url
            )
        )
    }

    public static func named(_ name: String) -> HomeStaticAdapterModelSource {
        HomeStaticAdapterModelSource(
            configuration: HomeAdapterModelConfiguration(source: .name, identifier: name)
        )
    }

    public func adapterConfiguration() -> HomeAdapterModelConfiguration? {
        configuration
    }
}

public struct HomeAdapterUnavailableError: LocalizedError, Sendable {
    public let diagnostic: HomeAdapterModelDiagnostic

    public init(diagnostic: HomeAdapterModelDiagnostic) {
        self.diagnostic = diagnostic
    }

    public var errorDescription: String? {
        diagnostic.errorDescription ?? "Adapter unavailable"
    }
}

public struct HomeAutomationResolverResult: Sendable, Hashable, Codable {
    public let state: HomeResolutionState
    public let retrievedCandidates: [HomeCandidateRecord]
    public let aggregation: HomeCandidateAggregationResult
    public let hydratedCandidates: [HomeCandidateRecord]
    public let draft: HomeCommandDraft?
    public let resolution: HomeCommandResolution

    public init(
        state: HomeResolutionState,
        retrievedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult,
        hydratedCandidates: [HomeCandidateRecord],
        draft: HomeCommandDraft?,
        resolution: HomeCommandResolution
    ) {
        self.state = state
        self.retrievedCandidates = retrievedCandidates
        self.aggregation = aggregation
        self.hydratedCandidates = hydratedCandidates
        self.draft = draft
        self.resolution = resolution
    }
}

public struct FoundationHomeCommandDraftResolver: HomeCommandDraftResolving {
    private let adapterProvider: HomeAdapterModelProvider

    public init(adapterProvider: HomeAdapterModelProvider = HomeAdapterModelProvider()) {
        self.adapterProvider = adapterProvider
    }

    public static func generationOptions(for mode: HomeGenerationMode) -> GenerationOptions {
        switch mode {
        case .greedy:
            return GenerationOptions(sampling: .greedy)
        case .defaultSampling:
            return GenerationOptions()
        }
    }

    public func prewarm(from package: HomeModelInstructionPackage, promptPrefix: Prompt? = nil) throws {
        try adapterProvider.prewarmSmartHomeSession(
            instructions: package.instructions,
            tools: package.tools,
            useAdapter: package.useAdapter,
            promptPrefix: promptPrefix
        )
    }

    public func streamDraft(from package: HomeModelInstructionPackage) throws -> LanguageModelSession.ResponseStream<HomeCommandDraft> {
        let session = try adapterProvider.makeSmartHomeSession(
            instructions: package.instructions,
            tools: package.tools,
            useAdapter: package.useAdapter
        )

        switch package.generationMode {
        case .greedy:
            return session.streamResponse(
                to: Prompt(package.prompt),
                generating: HomeCommandDraft.self,
                options: Self.generationOptions(for: package.generationMode)
            )
        case .defaultSampling:
            return session.streamResponse(to: Prompt(package.prompt), generating: HomeCommandDraft.self)
        }
    }

    public func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        let session = try adapterProvider.makeSmartHomeSession(
            instructions: package.instructions,
            tools: package.tools,
            useAdapter: package.useAdapter
        )

        switch package.generationMode {
        case .greedy:
            return try await session.respond(
                to: Prompt(package.prompt),
                generating: HomeCommandDraft.self,
                options: Self.generationOptions(for: package.generationMode)
            ).content
        case .defaultSampling:
            return try await session.respond(to: Prompt(package.prompt), generating: HomeCommandDraft.self).content
        }
    }
}

public struct HomeAdapterModelDiagnostic: Sendable, Hashable, Codable {
    public let attempted: Bool
    public let succeeded: Bool
    public let errorDescription: String?
    public let errorKind: FoundationModelFailureKind?
    public let adapterSource: String?
    public let adapterIdentifier: String?
    public let compatibilityVersion: String?
    public let loadOutcome: String

    public init(
        attempted: Bool,
        succeeded: Bool,
        errorDescription: String? = nil,
        errorKind: FoundationModelFailureKind? = nil,
        adapterSource: String? = nil,
        adapterIdentifier: String? = nil,
        compatibilityVersion: String? = nil,
        loadOutcome: String? = nil
    ) {
        self.attempted = attempted
        self.succeeded = succeeded
        self.errorDescription = errorDescription
        self.errorKind = errorKind
        self.adapterSource = adapterSource
        self.adapterIdentifier = adapterIdentifier
        self.compatibilityVersion = compatibilityVersion
        self.loadOutcome = loadOutcome ?? (succeeded ? "loaded" : (attempted ? "failed" : "notConfigured"))
    }
}

public final class HomeAdapterModelDiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var diagnostic: HomeAdapterModelDiagnostic?

    public init() {}

    public func record(_ diagnostic: HomeAdapterModelDiagnostic) {
        lock.lock()
        self.diagnostic = diagnostic
        lock.unlock()
    }

    public func lastDiagnostic() -> HomeAdapterModelDiagnostic? {
        lock.lock()
        defer { lock.unlock() }
        return diagnostic
    }
}

public struct HomeAdapterModelProvider: Sendable {
    private let diagnosticsStore: HomeAdapterModelDiagnosticsStore?
    private let adapterSource: any HomeAdapterModelSourcing

    public init(
        diagnosticsStore: HomeAdapterModelDiagnosticsStore? = nil,
        adapterSource: any HomeAdapterModelSourcing = HomeEnvironmentAdapterModelSource()
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.adapterSource = adapterSource
    }

    public var hasConfiguredAdapter: Bool {
        adapterConfiguration() != nil
    }

    public func adapterConfiguration() -> HomeAdapterModelConfiguration? {
        adapterSource.adapterConfiguration()
    }

    public func makeSmartHomeSession(
        instructions: Instructions,
        tools: [any Tool] = [],
        useAdapter: Bool
    ) throws -> LanguageModelSession {
        if useAdapter {
            let adapterResult = makeAdapterModel()
            diagnosticsStore?.record(adapterResult.diagnostic)
            if let model = adapterResult.model {
                return LanguageModelSession(model: model, tools: tools, instructions: instructions)
            }
            if adapterResult.diagnostic.attempted {
                throw HomeAdapterUnavailableError(diagnostic: adapterResult.diagnostic)
            }
        }

        return LanguageModelSession(tools: tools, instructions: instructions)
    }

    public func prewarmSmartHomeSession(
        instructions: Instructions,
        tools: [any Tool] = [],
        useAdapter: Bool,
        promptPrefix: Prompt? = nil
    ) throws {
        let session = try makeSmartHomeSession(
            instructions: instructions,
            tools: tools,
            useAdapter: useAdapter
        )
        session.prewarm(promptPrefix: promptPrefix)
    }

    private func makeAdapterModel() -> (
        model: SystemLanguageModel?,
        diagnostic: HomeAdapterModelDiagnostic
    ) {
        guard let configuration = adapterConfiguration() else {
            return (
                nil,
                HomeAdapterModelDiagnostic(
                    attempted: false,
                    succeeded: false,
                    compatibilityVersion: HomeAdapterCompatibilityManifest.current.runtimeVersion
                )
            )
        }

        do {
            switch configuration.source {
            case .file, .bundle, .injectedURL, .backgroundAsset:
                guard let fileURL = configuration.fileURL else {
                    throw FoundationLabCoreError.invalidRequest("Adapter file URL missing")
                }
                let adapter = try SystemLanguageModel.Adapter(fileURL: fileURL)
                return (
                    SystemLanguageModel(adapter: adapter),
                    HomeAdapterModelDiagnostic(
                        attempted: true,
                        succeeded: true,
                        adapterSource: configuration.source.rawValue,
                        adapterIdentifier: configuration.identifier,
                        compatibilityVersion: HomeAdapterCompatibilityManifest.current.runtimeVersion
                    )
                )
            case .name:
                let adapter = try SystemLanguageModel.Adapter(name: configuration.identifier)
                return (
                    SystemLanguageModel(adapter: adapter),
                    HomeAdapterModelDiagnostic(
                        attempted: true,
                        succeeded: true,
                        adapterSource: configuration.source.rawValue,
                        adapterIdentifier: configuration.identifier,
                        compatibilityVersion: HomeAdapterCompatibilityManifest.current.runtimeVersion
                    )
                )
            }
        } catch {
            return (
                nil,
                HomeAdapterModelDiagnostic(
                    attempted: true,
                    succeeded: false,
                    errorDescription: error.localizedDescription,
                    errorKind: FoundationModelDiagnostics.failureKind(for: error),
                    adapterSource: configuration.source.rawValue,
                    adapterIdentifier: configuration.identifier,
                    compatibilityVersion: HomeAdapterCompatibilityManifest.current.runtimeVersion
                )
            )
        }
    }
}

public enum HomeFoundationModelPrewarmer {
    public static func prewarmDefaultSession(promptPrefix: String? = nil) {
        guard SystemLanguageModel.default.isAvailable else { return }
        let session = LanguageModelSession(instructions: Instructions("Prepare to resolve concise smart-home commands."))
        session.prewarm(promptPrefix: promptPrefix.map(Prompt.init))
    }
}
