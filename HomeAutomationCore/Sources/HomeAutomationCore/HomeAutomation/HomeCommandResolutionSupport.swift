import Foundation
import FoundationModels

public protocol HomeCommandResolving: Sendable {
    func resolve(_ text: String, executeLowRiskCommands: Bool) async throws -> HomeAutomationResolverResult
}

public protocol HomeCommandDraftResolving: Sendable {
    func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft
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

    public func resolveDraft(from package: HomeModelInstructionPackage) async throws -> HomeCommandDraft {
        let session = try adapterProvider.makeSmartHomeSession(
            instructions: package.instructions,
            tools: package.tools,
            useAdapter: package.useAdapter
        )

        switch package.generationMode {
        case .greedy:
            return try await session.respond(to: Prompt(package.prompt), generating: HomeCommandDraft.self).content
        case .defaultSampling:
            return try await session.respond(to: Prompt(package.prompt), generating: HomeCommandDraft.self).content
        }
    }
}

public struct HomeAdapterModelDiagnostic: Sendable, Hashable, Codable {
    public let attempted: Bool
    public let succeeded: Bool
    public let errorDescription: String?

    public init(
        attempted: Bool,
        succeeded: Bool,
        errorDescription: String? = nil
    ) {
        self.attempted = attempted
        self.succeeded = succeeded
        self.errorDescription = errorDescription
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

    public init(diagnosticsStore: HomeAdapterModelDiagnosticsStore? = nil) {
        self.diagnosticsStore = diagnosticsStore
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
        }

        return LanguageModelSession(tools: tools, instructions: instructions)
    }

    private func makeAdapterModel() -> (
        model: SystemLanguageModel?,
        diagnostic: HomeAdapterModelDiagnostic
    ) {
        let environment = ProcessInfo.processInfo.environment

        do {
            if let adapterFile = environment["HOME_AUTOMATION_ADAPTER_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !adapterFile.isEmpty {
                let adapter = try SystemLanguageModel.Adapter(fileURL: URL(filePath: adapterFile))
                return (
                    SystemLanguageModel(adapter: adapter),
                    HomeAdapterModelDiagnostic(attempted: true, succeeded: true)
                )
            }

            if let adapterName = environment["HOME_AUTOMATION_ADAPTER_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !adapterName.isEmpty {
                let adapter = try SystemLanguageModel.Adapter(name: adapterName)
                return (
                    SystemLanguageModel(adapter: adapter),
                    HomeAdapterModelDiagnostic(attempted: true, succeeded: true)
                )
            }
        } catch {
            return (
                nil,
                HomeAdapterModelDiagnostic(
                    attempted: true,
                    succeeded: false,
                    errorDescription: error.localizedDescription
                )
            )
        }

        return (
            nil,
            HomeAdapterModelDiagnostic(attempted: false, succeeded: false)
        )
    }
}
