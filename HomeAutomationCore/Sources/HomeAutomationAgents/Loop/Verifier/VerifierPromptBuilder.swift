import Foundation
import HomeAutomationCore

// MARK: - VerifierPrompt

public struct VerifierPrompt: Sendable, Equatable {
    public let text: String
    public let characterCount: Int

    public init(text: String) {
        self.text = text
        self.characterCount = text.count
    }
}

// MARK: - VerifierPromptBuilder

public struct VerifierPromptBuilder: Sendable {

    public static let instructions = """
    You are a verifier for a home-automation draft. Your job is to check \
    whether the draft correctly interprets the user's natural-language command.

    Rules:
    1. Compare the user text against each populated field.
    2. Only dispute fields that are clearly wrong given the user text.
    3. Set accepted=true if everything looks correct; otherwise list disputes.
    4. A dispute needs evidence — quote the user text that contradicts the field.
    5. If the risk seems higher than assessed (e.g. security devices, locks, \
    cameras), set riskUnderstated=true.
    6. If the user intent is genuinely ambiguous, set needsClarification=true.
    7. You may only dispute fields from the provided disputable-field list.
    8. Do not invent new fields or suggest structural changes.
    """

    public let characterBudget: Int

    public init(characterBudget: Int = 4000) {
        self.characterBudget = characterBudget
    }

    public func makeInitialPrompt(envelope: DraftEnvelope) -> VerifierPrompt {
        let disputableIDs = envelope.disputableFieldIDs()
        let lowConfIDs = Set(envelope.lowConfidenceFieldIDs(threshold: 0.5))

        var sections: [String] = []

        sections.append("User text: \"\(envelope.userText)\"")
        sections.append("Operation: \(envelope.operation) (confidence: \(formatted(envelope.operationConfidence)))")

        if let cmd = envelope.command {
            sections.append(renderCommandSection(cmd, lowConfIDs: lowConfIDs))
        }

        if let auto = envelope.automation {
            sections.append(renderAutomationSection(auto, lowConfIDs: lowConfIDs))
        }

        sections.append("Risk: \(envelope.risk.level) — \(envelope.risk.floorReason)")

        let fieldList = disputableIDs.map { id in
            let flag = lowConfIDs.contains(id) ? " ⚠" : ""
            return "  \(id.rawValue)\(flag)"
        }.joined(separator: "\n")
        sections.append("Disputable fields:\n\(fieldList)")

        let fullPrompt = sections.joined(separator: "\n\n")

        if fullPrompt.count <= characterBudget {
            return VerifierPrompt(text: fullPrompt)
        }

        return truncatePrompt(sections: sections, envelope: envelope, lowConfIDs: lowConfIDs)
    }

    public func makeDeltaPrompt(
        envelope: DraftEnvelope,
        previousDisputes: [DraftDispute],
        repairedFields: [FieldID]
    ) -> VerifierPrompt {
        var lines: [String] = []
        lines.append("User text: \"\(envelope.userText)\"")
        lines.append("Previously disputed fields have been repaired. Verify the updated values:")

        for fieldID in repairedFields {
            let currentValue = resolveFieldValue(fieldID, in: envelope) ?? "(empty)"
            let priorDispute = previousDisputes.first { $0.fieldID == fieldID.rawValue }
            let evidenceLine = priorDispute.map { "  Prior dispute: \($0.evidence)" } ?? ""

            lines.append("  \(fieldID.rawValue): \(currentValue)\(evidenceLine.isEmpty ? "" : "\n\(evidenceLine)")")
        }

        lines.append("Respond with a new verdict. Only re-dispute fields that are still wrong.")

        return VerifierPrompt(text: lines.joined(separator: "\n"))
    }

    // MARK: - Command rendering

    private func renderCommandSection(
        _ cmd: CommandDraftSection,
        lowConfIDs: Set<FieldID>
    ) -> String {
        var lines: [String] = ["Command:"]
        appendField(&lines, "  target", cmd.targetDeviceID, flag: lowConfIDs.contains(.command(.targetDeviceID)))
        appendField(&lines, "  capability", cmd.capability, flag: lowConfIDs.contains(.command(.capability)))
        appendField(&lines, "  command", cmd.commandName, flag: lowConfIDs.contains(.command(.commandName)))
        appendField(&lines, "  room", cmd.room, flag: lowConfIDs.contains(.command(.room)))

        if !cmd.parameters.isEmpty {
            let paramStr = cmd.parameters.map { "\($0.name)=\($0.value)" }.joined(separator: ", ")
            let flag = lowConfIDs.contains(.command(.parameters)) ? " ⚠" : ""
            lines.append("  parameters: \(paramStr)\(flag)")
        }

        if !cmd.candidateTable.isEmpty {
            lines.append(renderCandidateTable(cmd.candidateTable, label: "  Candidates"))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Automation rendering

    private func renderAutomationSection(
        _ auto: AutomationDraftSection,
        lowConfIDs: Set<FieldID>
    ) -> String {
        var lines: [String] = ["Automation:"]

        if let trigger = auto.trigger {
            let typeFlag = lowConfIDs.contains(.triggerType) ? " ⚠" : ""
            lines.append("  Trigger: \(trigger.type)\(typeFlag)")
            if let time = trigger.time {
                let timeFlag = lowConfIDs.contains(.triggerTime) ? " ⚠" : ""
                lines.append("    time: \(String(format: "%02d:%02d", time.hour, time.minute))\(timeFlag)")
            }
            if let repeatRule = trigger.repeatRule {
                let repeatFlag = lowConfIDs.contains(.triggerRepeat) ? " ⚠" : ""
                lines.append("    repeat: \(repeatRule)\(repeatFlag)")
            }
        }

        for (i, action) in auto.actions.enumerated() {
            lines.append("  Action[\(i)]: \"\(action.rawText)\"")
            appendField(&lines, "    target", action.command.targetDeviceID, flag: lowConfIDs.contains(.action(i, .targetDeviceID)))
            appendField(&lines, "    capability", action.command.capability, flag: lowConfIDs.contains(.action(i, .capability)))
            appendField(&lines, "    command", action.command.commandName, flag: lowConfIDs.contains(.action(i, .commandName)))

            if !action.command.candidateTable.isEmpty {
                lines.append(renderCandidateTable(action.command.candidateTable, label: "    Candidates"))
            }
        }

        if !auto.conditionLeaves.isEmpty {
            lines.append("  Conditions:")
            for (i, leaf) in auto.conditionLeaves.enumerated() {
                let targetFlag = lowConfIDs.contains(.conditionLeaf(i, .target)) ? " ⚠" : ""
                lines.append("    [\(i)] \"\(leaf.rawText)\" → target=\(leaf.target ?? "?")\(targetFlag) cap=\(leaf.capability ?? "?") attr=\(leaf.attribute ?? "?") op=\(leaf.operatorName?.rawValue ?? "?") val=\(leaf.value ?? "?")")
            }
        }

        if let tree = auto.conditionTree {
            let interpretation = treeInterpretation(tree, leaves: auto.conditionLeaves)
            lines.append("  Interpretation: \(interpretation)")
        }

        if auto.precedenceAmbiguous {
            lines.append("  ⚠ Precedence ambiguity detected in conditions")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func renderCandidateTable(_ candidates: [CompactCandidate], label: String) -> String {
        let rows = candidates.map { "    \($0.id) | \($0.name) | \($0.room ?? "-") | \($0.deviceType)" }
        return "\(label):\n\(rows.joined(separator: "\n"))"
    }

    private func appendField(_ lines: inout [String], _ label: String, _ value: String?, flag: Bool) {
        guard let value else { return }
        let marker = flag ? " ⚠" : ""
        lines.append("\(label): \(value)\(marker)")
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func treeInterpretation(_ tree: ConditionTreeDraft, leaves: [ConditionLeafDraft]) -> String {
        let leafMap = Dictionary(uniqueKeysWithValues: leaves.map { ($0.id, $0.rawText) })
        return describeTree(tree, leafMap: leafMap)
    }

    private func describeTree(_ tree: ConditionTreeDraft, leafMap: [String: String]) -> String {
        switch tree {
        case .leaf(let id):
            return leafMap[id] ?? id
        case .and(let children):
            let parts = children.map { describeTree($0, leafMap: leafMap) }
            return "(\(parts.joined(separator: " AND ")))"
        case .or(let children):
            let parts = children.map { describeTree($0, leafMap: leafMap) }
            return "(\(parts.joined(separator: " OR ")))"
        case .not(let child):
            return "NOT \(describeTree(child, leafMap: leafMap))"
        }
    }

    private func truncatePrompt(
        sections: [String],
        envelope: DraftEnvelope,
        lowConfIDs: Set<FieldID>
    ) -> VerifierPrompt {
        var truncated = sections

        for i in truncated.indices {
            if truncated[i].contains("Candidates:") {
                truncated[i] = truncateCandidates(truncated[i], maxPerSection: 3)
            }
        }

        let result = truncated.joined(separator: "\n\n")
        return VerifierPrompt(text: result)
    }

    private func truncateCandidates(_ section: String, maxPerSection: Int) -> String {
        let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [Substring] = []
        var candidateCount = 0
        var inCandidateBlock = false

        for line in lines {
            if line.hasSuffix("Candidates:") {
                inCandidateBlock = true
                candidateCount = 0
                result.append(line)
                continue
            }
            if inCandidateBlock {
                if line.contains("|") {
                    candidateCount += 1
                    if candidateCount <= maxPerSection {
                        result.append(line)
                    }
                    continue
                } else {
                    inCandidateBlock = false
                }
            }
            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private func resolveFieldValue(_ fieldID: FieldID, in envelope: DraftEnvelope) -> String? {
        switch fieldID.rawValue {
        case "operation":
            return String(describing: envelope.operation)
        case "risk.level":
            return String(describing: envelope.risk.level)
        case "command.targetDeviceID":
            return envelope.command?.targetDeviceID
        case "command.capability":
            return envelope.command?.capability
        case "command.commandName":
            return envelope.command?.commandName
        case "command.room":
            return envelope.command?.room
        case "command.parameters":
            return envelope.command?.parameters.map { "\($0.name)=\($0.value)" }.joined(separator: ", ")
        case "automation.trigger.type":
            return envelope.automation?.trigger.map { String(describing: $0.type) }
        case "automation.trigger.time":
            return envelope.automation?.trigger?.time.map { String(format: "%02d:%02d", $0.hour, $0.minute) }
        case "automation.trigger.repeat":
            return envelope.automation?.trigger?.repeatRule.map { String(describing: $0) }
        default:
            if fieldID.rawValue.hasPrefix("automation.actions[") {
                return resolveActionFieldValue(fieldID, in: envelope)
            }
            if fieldID.rawValue.hasPrefix("automation.conditionLeaves[") {
                return resolveConditionFieldValue(fieldID, in: envelope)
            }
            return nil
        }
    }

    private func resolveActionFieldValue(_ fieldID: FieldID, in envelope: DraftEnvelope) -> String? {
        guard let match = fieldID.rawValue.firstMatch(of: /automation\.actions\[(\d+)\]\.(.+)/),
              let index = Int(match.output.1),
              let actions = envelope.automation?.actions,
              index < actions.count else { return nil }
        let cmd = actions[index].command
        switch String(match.output.2) {
        case "targetDeviceID": return cmd.targetDeviceID
        case "capability": return cmd.capability
        case "commandName": return cmd.commandName
        case "room": return cmd.room
        default: return nil
        }
    }

    private func resolveConditionFieldValue(_ fieldID: FieldID, in envelope: DraftEnvelope) -> String? {
        guard let match = fieldID.rawValue.firstMatch(of: /automation\.conditionLeaves\[(\d+)\]\.(.+)/),
              let index = Int(match.output.1),
              let leaves = envelope.automation?.conditionLeaves,
              index < leaves.count else { return nil }
        let leaf = leaves[index]
        switch String(match.output.2) {
        case "target": return leaf.target
        case "capability": return leaf.capability
        case "attribute": return leaf.attribute
        case "operator": return leaf.operatorName?.rawValue
        case "value": return leaf.value
        default: return nil
        }
    }
}
