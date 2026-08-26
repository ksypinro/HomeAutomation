import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

/// Single owner of the device registry, coordinator, and orchestrator for the
/// whole process.
///
/// Both the SwiftUI app and the App Intents read from here. That sharing is the
/// reason `ResolveHomeCommandIntent` pins itself to `.main` execution: the
/// device registry is an in-memory actor, so an intent running in a separate
/// extension process would mutate a device world the app never sees.
@MainActor
final class HomeAutomationRuntime {
    static let shared = HomeAutomationRuntime()

    /// App Intents always resolve with this configuration, regardless of what
    /// the app's pickers happen to be set to. An intent invoked from Siri or
    /// Shortcuts has to behave the same way every time — inheriting whatever
    /// the UI was last left on would make it non-deterministic.
    static let intentChoice: OrchestratorChoice = .adaptiveStatic
    static let intentCompiler: GraphCompilerChoice = .disabled

    let registry = MockHomeDeviceRegistry()

    private(set) var coordinator: HomeAutomationCoordinator
    private(set) var orchestrator: HomeCommandOrchestrator

    /// Built lazily and reused. Separate from `orchestrator` so the UI and the
    /// intents can run different arms, but minted from the same coordinator so
    /// they still share one RAG index and one device registry.
    private var cachedIntentOrchestrator: HomeCommandOrchestrator?

    /// Retained so a second caller joins the in-flight upgrade instead of
    /// kicking off a duplicate index build.
    private var ragUpgrade: Task<Void, Never>?
    private var hasUpgradedToRAG = false

    private var currentChoice: OrchestratorChoice = .graph
    private var currentCompiler: GraphCompilerChoice = .disabled

    private init() {
        let initialCoordinator = HomeAutomationCoordinator(deviceRegistry: registry)
        coordinator = initialCoordinator
        orchestrator = initialCoordinator.makeOrchestrator()
    }

    /// Rebuilds the coordinator with the RAG index attached. Idempotent, and
    /// safe to await from several callers — the index is built once.
    func upgradeToRAG() async {
        if hasUpgradedToRAG { return }
        if let ragUpgrade {
            await ragUpgrade.value
            return
        }

        let task = Task { [registry] in
            let upgraded = await HomeCommandOrchestrator.makeRAGEnabledCoordinator(
                deviceRegistry: registry
            )
            await MainActor.run {
                self.coordinator = upgraded
                self.hasUpgradedToRAG = true
                // The cached intent orchestrator was minted from the old,
                // RAG-less coordinator — drop it so the next intent run picks
                // up the index.
                self.cachedIntentOrchestrator = nil
                self.rebuildOrchestrator(choice: self.currentChoice, compiler: self.currentCompiler)
            }
        }
        ragUpgrade = task
        await task.value
        ragUpgrade = nil
    }

    /// The orchestrator App Intents resolve through: always
    /// `Self.intentChoice` / `Self.intentCompiler`, never the UI's selection.
    func intentOrchestrator() -> HomeCommandOrchestrator {
        if let cachedIntentOrchestrator { return cachedIntentOrchestrator }
        let built = makeOrchestrator(choice: Self.intentChoice, compiler: Self.intentCompiler)
        cachedIntentOrchestrator = built
        return built
    }

    /// Mints a fresh orchestrator from the retained coordinator for the selected
    /// mode. The RAG index and device registry are reused; only the runtime
    /// dependencies (agent registry, loop orchestrator) are rebuilt.
    func rebuildOrchestrator(choice: OrchestratorChoice, compiler: GraphCompilerChoice) {
        currentChoice = choice
        currentCompiler = compiler
        orchestrator = makeOrchestrator(choice: choice, compiler: compiler)
    }

    private func makeOrchestrator(
        choice: OrchestratorChoice,
        compiler: GraphCompilerChoice
    ) -> HomeCommandOrchestrator {
        let dependencies = coordinator.makeRuntimeDependencies(
            orchestrationMode: choice.orchestrationMode,
            useMiniPipeline: choice.usesMiniPipeline,
            portfolioRolloutMode: choice.rolloutMode,
            portfolioEligibilityPolicy: choice.portfolioEligibilityPolicy,
            graphCompilationMode: compiler.mode
        )
        return HomeCommandOrchestrator(dependencies: dependencies)
    }
}
