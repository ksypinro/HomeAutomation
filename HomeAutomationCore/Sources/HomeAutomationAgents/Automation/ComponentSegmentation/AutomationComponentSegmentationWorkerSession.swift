import Foundation
import FoundationModels
import HomeAutomationCore
import os

public struct AutomationComponentSegmentationWorkerSession: Sendable {
    private let foundationModelAvailability: @Sendable () -> Bool
    private let segment: (@Sendable (String) async throws -> AutomationComponentPlanFMOutput)?
    private let logger = Logger(subsystem: "HomeAutomation", category: "Automation.ComponentSegmentation")

    public init(
        foundationModelAvailability: @escaping @Sendable () -> Bool = {
            SystemLanguageModel.default.isAvailable
        },
        segment: (@Sendable (String) async throws -> AutomationComponentPlanFMOutput)? = nil
    ) {
        self.foundationModelAvailability = foundationModelAvailability
        self.segment = segment
    }

    public func segment(_ text: String) async throws -> AutomationComponentPlan {
        let fallback = AutomationPatternParserHintTool.fallbackPlan(for: text)
        if let segment {
            return plan(from: try await segment(text), fallback: fallback)
        }

        guard foundationModelAvailability() else {
            if let fallback { return fallback }
            throw AutomationDraftError.unsupported("I could not segment this automation command.")
        }

        let prompt = AutomationComponentSegmentationPromptBuilder.prompt(
            text: text,
            deterministicHint: fallback
        )
        logger.debug("[FoundationModelInput] \(prompt, privacy: .public)")
        do {
            let session = LanguageModelSession(
                instructions: Instructions(AutomationComponentSegmentationPromptBuilder.instructions)
            )
            let output = try await session.respond(
                to: Prompt(prompt),
                generating: AutomationComponentPlanFMOutput.self
            ).content
            let plan = plan(from: output, fallback: fallback)
            guard !plan.actions.isEmpty else {
                if let fallback { return fallback }
                throw AutomationDraftError.invalidOutput("component segmentation returned no actions")
            }
            logger.debug("[FoundationModelOutput] \(String(describing: plan), privacy: .public)")
            return plan
        } catch {
            logger.error("[FoundationModelError] \(error.localizedDescription, privacy: .public); using deterministic component plan.")
            if let fallback { return fallback }
            throw error
        }
    }

    private func plan(
        from output: AutomationComponentPlanFMOutput,
        fallback: AutomationComponentPlan?
    ) -> AutomationComponentPlan {
        let triggerText = nonEmpty(output.triggerRawText) ?? fallback?.trigger?.rawText
        let triggerKind = output.triggerKind == .unknown
            ? (fallback?.trigger?.kindHint ?? .unknown)
            : output.triggerKind
        let trigger = triggerText.map {
            AutomationTriggerComponent(
                id: fallback?.trigger?.id ?? "t1",
                rawText: $0,
                kindHint: triggerKind
            )
        }

        let actionTexts = output.actionRawTexts.compactMap(nonEmpty)
        let actions = (actionTexts.isEmpty ? fallback?.actions.map(\.rawText) ?? [] : actionTexts)
            .enumerated()
            .map { index, text in AutomationActionComponent(id: "a\(index + 1)", rawText: text, order: index) }

        let conditionTexts = output.conditionRawTexts.compactMap(nonEmpty)
        let conditions = (conditionTexts.isEmpty ? fallback?.conditions.map(\.rawText) ?? [] : conditionTexts)
            .enumerated()
            .map { index, text in AutomationConditionComponent(id: "c\(index + 1)", rawText: text, order: index) }
        let conditionTree = tree(
            connector: output.conditionConnector,
            conditions: conditions,
            fallback: fallback?.conditionTree
        )

        return AutomationComponentPlan(
            trigger: trigger,
            actions: actions,
            conditions: conditions,
            conditionTree: conditionTree,
            unsupportedFragments: merge(output.unsupportedFragments, fallback?.unsupportedFragments ?? []),
            confidence: output.confidence > 0 ? output.confidence : (fallback?.confidence ?? 0.5)
        )
    }

    private func tree(
        connector: String?,
        conditions: [AutomationConditionComponent],
        fallback: AutomationConditionTreeDescriptor?
    ) -> AutomationConditionTreeDescriptor? {
        guard !conditions.isEmpty else { return nil }
        if conditions.count == 1 { return .leaf(conditions[0].id) }
        switch connector?.lowercased() {
        case "or":
            return .or(conditions.map { .leaf($0.id) })
        case "and":
            return .and(conditions.map { .leaf($0.id) })
        default:
            if let fallback, Set(fallback.leafIDs) == Set(conditions.map(\.id)) {
                return fallback
            }
            return .and(conditions.map { .leaf($0.id) })
        }
    }

    private func merge(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in lhs + rhs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { continue }
            seen.insert(trimmed.lowercased())
            result.append(trimmed)
        }
        return result
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
