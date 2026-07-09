import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import OSLog

public struct SpeculativeAssemblyCompiler: Sendable {
    private let compiler: SmartThingsRuleCompiler
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.SpeculativeCompiler")

    public init(compiler: SmartThingsRuleCompiler = SmartThingsRuleCompiler()) {
        self.compiler = compiler
    }

    func compile(
        plan: AutomationComponentPlan,
        resolvedComponents: AutomationResolvedComponentSet,
        context: ResolutionContext
    ) async -> SpeculativeCompilationResult? {
        let assemblyAgent = AutomationDraftAssemblyAgent()
        let input = AutomationDraftAssemblyInput(
            componentPlan: plan,
            resolvedComponents: resolvedComponents
        )

        let ruleDraft: HomeAutomationRuleDraft
        do {
            ruleDraft = try await assemblyAgent.run(input, context: context)
        } catch {
            logger.debug("[speculative] Assembly failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let resolvedActions = resolvedComponents.actionResults.compactMap(\.resolvedAction)
        let creationPlan = HomeAutomationCreationPlan(
            name: ruleDraft.name,
            ruleDraft: ruleDraft,
            resolvedActions: resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: resolvedComponents.actionResults.contains(where: \.requiresConfirmation),
            unsupportedCompilationReason: nil
        )

        do {
            let document = try compiler.compile(creationPlan)
            logger.debug("[speculative] Compilation succeeded.")
            return SpeculativeCompilationResult(
                ruleDraft: ruleDraft,
                smartThingsRuleJSON: document.jsonString,
                compilationDetail: "speculative-compiled"
            )
        } catch {
            logger.debug("[speculative] Compilation failed: \(error.localizedDescription, privacy: .public); draft still usable.")
            return SpeculativeCompilationResult(
                ruleDraft: ruleDraft,
                smartThingsRuleJSON: nil,
                compilationDetail: "speculative-assembly-only: \(error.localizedDescription)"
            )
        }
    }
}
