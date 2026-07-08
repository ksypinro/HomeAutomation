import Foundation
import HomeAutomationCore

public enum StructuralDraftBuilder {

    public static func commandDraft(
        from section: CommandDraftSection?,
        risk: RiskSection,
        capabilityOverride: HomeCapabilityDecision? = nil
    ) -> HomeCommandDraft? {
        guard let section else { return nil }
        let capability = capabilityOverride?.selectedCapability ?? section.capability
        let commandName = capabilityOverride?.selectedCommand ?? section.commandName
        guard let capability, let commandName else {
            return nil
        }

        let intent = inferIntent(commandName: commandName, capability: capability)

        return HomeCommandDraft(
            intent: intent,
            targetDeviceID: section.targetDeviceID,
            capability: capability,
            command: commandName,
            parameters: section.parameters,
            needsClarification: section.targetDeviceID == nil,
            clarificationQuestion: section.targetDeviceID == nil ? "Which device do you want to control?" : nil,
            requiresConfirmation: risk.level == .high || risk.level == .critical,
            confidence: section.targetDeviceID != nil ? 0.9 : 0.3
        )
    }

    private static func inferIntent(commandName: String, capability: String) -> HomeAutomationIntent {
        switch commandName.lowercased() {
        case "on": return .turnOn
        case "off": return .turnOff
        case "open": return .open
        case "close": return .close
        case "lock": return .lock
        case "unlock": return .unlock
        case "setlevel", "settemperature", "setheatingsetpoint", "setcoolingsetpoint",
             "setcolor", "sethue", "setsaturation":
            return .setValue
        case "start": return .start
        case "stop": return .stop
        case "pause": return .pause
        case "resume": return .resume
        default:
            if capability == "lock" && commandName == "lock" { return .lock }
            if capability == "lock" && commandName == "unlock" { return .unlock }
            return .setValue
        }
    }
}
