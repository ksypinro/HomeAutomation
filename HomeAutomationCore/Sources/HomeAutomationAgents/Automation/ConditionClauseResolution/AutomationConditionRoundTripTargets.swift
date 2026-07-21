import Foundation
import HomeAutomationCore

/// Identity round-trip target for Graph orchestrator: all lossless forms accepted.
public struct AutomationConditionGraphTarget: AutomationConditionRoundTripTarget {
    public init() {}

    public func roundTripResidual(for condition: HomeAutomationCondition) -> AutomationConditionResidualReason? {
        nil
    }
}

/// Restricted round-trip target for Verifier Loop: only losslessly representable forms accepted.
/// The Verifier consumes ConditionLeafDraft + ConditionTreeDraft which cannot represent:
/// - .changes operator
/// - .literalRange operands
/// - unit separation
/// - right-hand device operand (cross-device operands)
/// - locationMode
/// - per-comparison trigger policy (only AON trees)
public struct AutomationConditionVerifierTarget: AutomationConditionRoundTripTarget {
    public init() {}

    public func roundTripResidual(for condition: HomeAutomationCondition) -> AutomationConditionResidualReason? {
        canRepresent(condition) ? nil : .notRoundTripSafe
    }

    private func canRepresent(_ condition: HomeAutomationCondition) -> Bool {
        switch condition {
        case .changes:
            return false
        case .comparison(let comp):
            return isANDONPolicy(comp.triggerPolicy) && operandIsRepresentable(comp.left) && operandIsRepresentable(comp.right)
        case .and(let children), .or(let children):
            return children.allSatisfy { canRepresent($0) }
        case .not(let child):
            return canRepresent(child)
        }
    }

    private func operandIsRepresentable(_ operand: HomeAutomationConditionOperand) -> Bool {
        switch operand {
        case .deviceAttribute(_, let deviceID, _, _):
            return deviceID?.isEmpty == false
        case .literalString:
            return true
        case .literalNumber:
            return true
        case .literalRange:
            return false
        case .locationMode:
            return false
        case .unsupported:
            return false
        }
    }

    private func isANDONPolicy(_ policy: HomeAutomationConditionTriggerPolicy) -> Bool {
        policy == .always
    }
}
