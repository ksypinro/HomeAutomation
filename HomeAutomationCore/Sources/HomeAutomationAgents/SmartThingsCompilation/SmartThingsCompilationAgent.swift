import Foundation
import HomeAutomationCore

public struct SmartThingsCompilationAgent: HomeAgent {
    public typealias Input = SmartThingsCompilationInput
    public typealias Output = SmartThingsCompilationOutput

    public let id = AgentID.smartThingsCompilation
    public let capabilities: Set<AgentCapability> = [.smartThingsCompilation]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let compiler: SmartThingsRuleCompiler

    public init(compiler: SmartThingsRuleCompiler) {
        self.compiler = compiler
    }

    public func run(
        _ input: SmartThingsCompilationInput,
        context: ResolutionContext
    ) async throws -> SmartThingsCompilationOutput {
        if let speculative = context.scopedValue(for: AutomationRuntimeContextKeys.speculativeCompilation),
           let json = speculative.smartThingsRuleJSON {
            let plan = HomeAutomationCreationPlan(
                name: input.ruleDraft.name,
                ruleDraft: input.ruleDraft,
                resolvedActions: input.resolvedActions,
                smartThingsRuleJSON: json,
                requiresConfirmation: input.requiresConfirmation || input.validation?.requiresConfirmation == true,
                unsupportedCompilationReason: input.validation?.unsupportedCompilationReason
            )
            return SmartThingsCompilationOutput(
                plan: plan,
                document: nil,
                detail: speculative.compilationDetail
            )
        }

        let initialPlan = HomeAutomationCreationPlan(
            name: input.ruleDraft.name,
            ruleDraft: input.ruleDraft,
            resolvedActions: input.resolvedActions,
            smartThingsRuleJSON: nil,
            requiresConfirmation: input.requiresConfirmation || input.validation?.requiresConfirmation == true,
            unsupportedCompilationReason: input.validation?.unsupportedCompilationReason
        )

        do {
            let document = try compiler.compile(initialPlan)
            let compiledPlan = HomeAutomationCreationPlan(
                name: initialPlan.name,
                ruleDraft: initialPlan.ruleDraft,
                resolvedActions: initialPlan.resolvedActions,
                smartThingsRuleJSON: document.jsonString,
                requiresConfirmation: initialPlan.requiresConfirmation,
                unsupportedCompilationReason: initialPlan.unsupportedCompilationReason
            )
            return SmartThingsCompilationOutput(
                plan: compiledPlan,
                document: document,
                detail: "compiled"
            )
        } catch {
            let failedPlan = HomeAutomationCreationPlan(
                name: initialPlan.name,
                ruleDraft: initialPlan.ruleDraft,
                resolvedActions: initialPlan.resolvedActions,
                smartThingsRuleJSON: nil,
                requiresConfirmation: initialPlan.requiresConfirmation,
                unsupportedCompilationReason: initialPlan.unsupportedCompilationReason ?? error.localizedDescription
            )
            return SmartThingsCompilationOutput(
                plan: failedPlan,
                document: nil,
                detail: error.localizedDescription
            )
        }
    }
}
