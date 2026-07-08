import Foundation
import HomeAutomationCore

public struct AutomationRiskAssessor: Sendable {

    public init() {}

    public func assess(envelope: DraftEnvelope) -> RiskSection {
        var risk = envelope.risk

        if let auto = envelope.automation {
            for action in auto.actions {
                let state = AgentTextParser.deterministicState(for: action.rawText)
                risk.raise(to: state.risk.riskLevel, reason: state.risk.reason)
            }
        }

        if let cmd = envelope.command {
            let state = AgentTextParser.deterministicState(for: envelope.userText)
            risk.raise(to: state.risk.riskLevel, reason: state.risk.reason)

            if let cap = cmd.capability, ["lock", "alarm", "securitySystem"].contains(cap) {
                risk.raise(to: .high, reason: "Security-sensitive capability: \(cap)")
            }
        }

        return risk
    }

    public func assessFromActions(_ actionTexts: [String]) -> RiskSection {
        var risk = RiskSection(level: .low, floorReason: "Rule-level risk floor")
        for text in actionTexts {
            let state = AgentTextParser.deterministicState(for: text)
            risk.raise(to: state.risk.riskLevel, reason: state.risk.reason)
        }
        return risk
    }

    public func requiresConfirmation(envelope: DraftEnvelope) -> Bool {
        let risk = assess(envelope: envelope)
        return risk.level == .high || risk.level == .critical
    }
}
