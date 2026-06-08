import Foundation
import HomeAutomationCore

/// Private support types for the rule-based fallback resolver.

struct AgentScoredDevice {
    let device: HomeCandidateRecord
    let draftIntent: AgentDraftIntent
    let score: Int
}

struct AgentDraftIntent {
    let intent: HomeAutomationIntent
    let capability: String
    let command: String
    let parameters: [HomeResolvedParameter]
}

struct AgentCapabilityCommand {
    let capability: String
    let command: String
}

struct AgentSemanticHints {
    let preferredDeviceIDs: Set<String>
    let preferredCapabilityIDs: Set<String>
    let preferredCommands: Set<String>

    init(
        preferredDeviceIDs: Set<String> = [],
        preferredCapabilityIDs: Set<String> = [],
        preferredCommands: Set<String> = []
    ) {
        self.preferredDeviceIDs = preferredDeviceIDs
        self.preferredCapabilityIDs = preferredCapabilityIDs
        self.preferredCommands = preferredCommands
    }
}

struct AgentRuleIntent {
    let family: HomeAutomationIntentFamily
    let intent: HomeAutomationIntent
    let capabilityPreferences: [AgentCapabilityCommand]
    let parameters: [HomeResolvedParameter]
    let deviceTypeHints: Set<String>

    init?(normalized: String) {
        let tokens = normalized.agentTokenSet
        let numbers = AgentTextParser.extractedNumbers(from: normalized)
        let firstNumber = numbers.first

        if AgentTextParser.containsAny(normalized, ["movie time", "good night", "routine", "scene"]) {
            self.init(family: .routine, intent: .runRoutine, capabilityPreferences: [.init(capability: "routine", command: "run")], parameters: [], deviceTypeHints: ["routine"])
            return
        }
        if tokens.contains("unlock") || normalized.contains("open the lock") {
            self.init(family: .lockUnlock, intent: .unlock, capabilityPreferences: [.init(capability: "lock", command: "unlock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if tokens.contains("lock") || tokens.contains("secure") {
            self.init(family: .lockUnlock, intent: .lock, capabilityPreferences: [.init(capability: "lock", command: "lock")], parameters: [], deviceTypeHints: ["lock"])
            return
        }
        if AgentTextParser.containsAny(normalized, ["open", "raise"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .open,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "open"),
                    .init(capability: "doorControl", command: "open"),
                    .init(capability: "windowShade", command: "open"),
                    .init(capability: "valve", command: "open")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["close", "lower"]) &&
            AgentTextParser.containsAny(normalized, ["door", "garage", "blind", "shade", "valve"]) {
            self.init(
                family: .openClose,
                intent: .close,
                capabilityPreferences: [
                    .init(capability: "garageDoorControl", command: "close"),
                    .init(capability: "doorControl", command: "close"),
                    .init(capability: "windowShade", command: "close"),
                    .init(capability: "valve", command: "close")
                ],
                parameters: [],
                deviceTypeHints: ["garage door", "door", "blind", "valve"]
            )
            return
        }
        if let mediaIntent = mediaIntent(for: normalized, firstNumber: firstNumber) {
            self = mediaIntent
            return
        }
        if AgentTextParser.containsAny(normalized, ["status", "check", "what is", "is the", "tell me", "battery"]) {
            self.init(
                family: .statusQuery,
                intent: .getStatus,
                capabilityPreferences: statusCapabilityPreferences(for: normalized),
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["cooler", "warmer"]) {
            let direction = normalized.contains("cooler") ? -1 : 1
            self.init(
                family: .temperature,
                intent: direction < 0 ? .decreaseValue : .increaseValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "delta", numericValue: Double(firstNumber ?? 1), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["temperature", "setpoint", "degrees"]) && firstNumber != nil {
            self.init(
                family: .temperature,
                intent: .setValue,
                capabilityPreferences: [
                    .init(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint"),
                    .init(capability: "thermostatHeatingSetpoint", command: "setHeatingSetpoint")
                ],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "degrees", confidence: 0.85)
                ],
                deviceTypeHints: ["air conditioner", "thermostat"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, ["brightness", "bright", "dim", "percent", "level"]) && firstNumber != nil {
            let isIncrease = AgentTextParser.containsAny(normalized, ["increase", "raise", "brighter"])
            let isDecrease = AgentTextParser.containsAny(normalized, ["decrease", "lower", "dim"])
            let command = isIncrease ? "increaseValue" : isDecrease ? "decreaseValue" : "setLevel"
            self.init(
                family: .brightness,
                intent: isIncrease ? .increaseValue : isDecrease ? .decreaseValue : .setValue,
                capabilityPreferences: [.init(capability: "switchLevel", command: command)],
                parameters: [
                    HomeResolvedParameter(name: "value", numericValue: Double(firstNumber ?? 0), unit: "percent", confidence: 0.9)
                ],
                deviceTypeHints: ["light"]
            )
            return
        }
        if AgentTextParser.containsAny(normalized, tvRulePowerOffPhrases) {
            self.init(
                family: .power,
                intent: .turnOff,
                capabilityPreferences: [.init(capability: "switch", command: "off")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }
        if AgentTextParser.containsAny(normalized, tvRulePowerOnPhrases) {
            self.init(
                family: .power,
                intent: .turnOn,
                capabilityPreferences: [.init(capability: "switch", command: "on")],
                parameters: [],
                deviceTypeHints: Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
            )
            return
        }

        return nil
    }

    init(
        family: HomeAutomationIntentFamily,
        intent: HomeAutomationIntent,
        capabilityPreferences: [AgentCapabilityCommand],
        parameters: [HomeResolvedParameter],
        deviceTypeHints: Set<String>
    ) {
        self.family = family
        self.intent = intent
        self.capabilityPreferences = capabilityPreferences
        self.parameters = parameters
        self.deviceTypeHints = deviceTypeHints
    }

    func makeDraftIntent(for device: HomeCandidateRecord) -> AgentDraftIntent? {
        guard let preference = capabilityPreferences.first(where: { device.capabilities.contains($0.capability) }) else {
            return nil
        }
        return AgentDraftIntent(
            intent: intent,
            capability: preference.capability,
            command: preference.command,
            parameters: parameters
        )
    }
}

private let tvRulePowerOnPhrases = [
    "turn on", "switch on", "power on", "power up", "start", "enable", "activate", "wake up",
    "wake", "boot", "boot up", "fire up", "bring on", "put on", "start up", "energize"
]

private let tvRulePowerOffPhrases = [
    "turn off", "switch off", "power off", "power down", "shut off", "shut down", "disable",
    "deactivate", "sleep", "put to sleep", "kill power", "stop power", "cut power", "switch down"
]

private let tvRuleChannelUpPhrases = [
    "next channel", "channel up", "increase channel", "raise channel", "move to next channel",
    "advance channel", "go up one channel", "step up a channel", "skip to next channel",
    "flip to next channel", "channel forward", "tune up one channel", "scan up one channel",
    "nudge channel up", "hop to next channel", "jump to next channel", "browse forward",
    "cycle forward", "go forward one channel", "move channel forward"
]

private let tvRuleChannelDownPhrases = [
    "previous channel", "prev channel", "last channel", "channel down", "decrease channel",
    "lower channel", "move to previous channel", "go back a channel", "step down a channel",
    "channel back", "tune down one channel", "scan down one channel", "hop back a channel",
    "jump to prior channel", "flip to previous channel", "back one channel", "cycle backward",
    "browse backward", "return to previous channel", "move channel backward"
]

private let tvRuleSetChannelPhrases = [
    "channel", "station", "tune to channel", "go to channel", "jump to channel", "select channel",
    "put channel", "set channel", "open channel", "show channel", "move to channel",
    "switch to channel", "load channel", "choose channel", "watch channel"
]

private let tvRuleSetVolumePhrases = [
    "volume", "sound level", "audio level", "speaker level", "loudness"
]

private let tvRuleVolumeUpPhrases = [
    "volume up", "turn up", "increase volume", "raise volume", "louder", "boost volume",
    "pump up volume", "make louder", "amplify volume", "add volume", "bump volume up",
    "nudge volume up", "crank up volume", "more volume", "lift volume", "turn sound up",
    "raise audio", "increase audio", "up the sound", "make tv louder"
]

private let tvRuleVolumeDownPhrases = [
    "volume down", "turn down", "decrease volume", "lower volume", "quieter", "reduce volume",
    "soften volume", "drop volume", "bring down volume", "make quieter", "lower audio",
    "turn sound down", "less volume", "dial down volume", "nudge volume down", "cut volume",
    "quiet down", "reduce audio", "lower sound", "make tv softer", "softer", "make softer"
]

private let tvRuleMutePhrases = [
    "mute", "silence", "turn sound off", "disable audio", "kill audio", "kill sound",
    "cut audio", "cut the sound", "no sound", "quiet the tv", "shush", "shush the tv",
    "turn audio off", "turn volume off", "remove sound", "block sound", "suppress audio",
    "make silent", "silence audio", "silence the tv", "quiet the", "silent"
]

private let tvRuleUnmutePhrases = [
    "unmute", "restore sound", "turn sound back on", "enable audio", "bring audio back",
    "take off mute", "restore audio", "sound back on", "cancel mute", "remove mute",
    "undo mute", "turn volume back on", "re enable sound", "let audio play", "unsilence",
    "wake the sound", "resume sound", "restore tv volume", "restore volume", "restore",
    "enable sound", "bring back sound"
]

private let tvRulePlayPhrases = [
    "play", "resume", "continue", "start playback", "begin playback", "start playing",
    "resume playback", "play media", "play video", "continue show", "resume show",
    "start the program", "begin the video", "play the movie", "continue the movie",
    "restart playback", "roll video", "run playback", "start streaming", "resume streaming"
]

private let tvRulePausePhrases = [
    "pause", "hold playback", "freeze playback", "pause video", "pause show",
    "suspend playback", "stop temporarily", "put playback on hold", "hold the show",
    "pause media", "pause stream", "halt playback", "park the video", "pause program",
    "pause the tv content", "take a break", "pause what is playing", "pause the movie",
    "pause the current video", "hold current playback"
]

private let tvRuleStopPlaybackPhrases = [
    "stop playback", "stop media", "stop video", "end playback", "end show", "halt media",
    "quit playback", "terminate playback", "cancel playback", "stop stream",
    "shut playback down", "close media playback", "finish playback", "stop current video",
    "end program", "cease playback", "cut playback", "stop what is playing",
    "turn playback off", "halt the show"
]

private let tvRuleFastForwardPhrases = [
    "fast forward", "skip ahead", "jump ahead", "scan forward", "advance playback",
    "go forward", "move forward", "skip forward", "advance video", "cue forward",
    "seek ahead", "scrub forward", "forward the playback", "hurry ahead", "speed ahead",
    "leap ahead", "wind forward", "move ahead in video", "push playback forward",
    "fast forward playback"
]

private let tvRuleRewindPhrases = [
    "rewind", "go back", "skip back", "jump back", "scan backward", "move backward",
    "rewind playback", "seek back", "scrub back", "back up video", "reverse playback",
    "wind back", "return earlier", "go earlier", "move back in video", "step back",
    "roll back playback", "backtrack playback", "pull playback back", "rewind video"
]

private let tvRuleInputSourcePhrases = [
    "input", "source", "hdmi", "usb", " av ", "select input", "choose input",
    "change input", "switch input", "set input", "select source", "choose source",
    "change source", "switch source", "set source", "route to", "use hdmi", "use usb",
    "move source", "tv source"
]

private func mediaIntent(for normalized: String, firstNumber: Int?) -> AgentRuleIntent? {
    let explicitDeviceTypeHints = Set(AgentTextParser.deviceTypes(for: normalized).map(\.agentNormalizedHomeTokenString))
    let deviceTypeHints = explicitDeviceTypeHints.isEmpty
        ? explicitDeviceTypeHints.union(["tv", "television", "speaker", "receiver", "set top box", "audio system"])
        : explicitDeviceTypeHints

    if AgentTextParser.containsAny(normalized, tvRuleChannelUpPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .increaseValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "channel", command: "channelUp")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleChannelDownPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .decreaseValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "channel", command: "channelDown")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if firstNumber != nil, AgentTextParser.containsAny(normalized, tvRuleSetChannelPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "channel", command: "setChannel")],
            parameters: [HomeResolvedParameter(name: "channel", numericValue: Double(firstNumber ?? 0), confidence: 0.9)],
            deviceTypeHints: deviceTypeHints
        )
    }

    if let inputSource = mediaInputSource(from: normalized) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaInputSource", command: "setInputSource")],
            parameters: [HomeResolvedParameter(name: "inputSource", value: inputSource, confidence: 0.9)],
            deviceTypeHints: deviceTypeHints
        )
    }

    if AgentTextParser.containsAny(normalized, tvRuleUnmutePhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "audioVolume", command: "unmute")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleMutePhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "audioVolume", command: "mute")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleVolumeUpPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .increaseValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "audioVolume", command: "volumeUp")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleVolumeDownPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .decreaseValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "audioVolume", command: "volumeDown")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleSetVolumePhrases), let firstNumber {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "audioVolume", command: "setVolume")],
            parameters: [HomeResolvedParameter(name: "volume", numericValue: Double(firstNumber), confidence: 0.9)],
            deviceTypeHints: deviceTypeHints
        )
    }

    if AgentTextParser.containsAny(normalized, tvRuleFastForwardPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaPlayback", command: "fastForward")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleRewindPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .setValue,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaPlayback", command: "rewind")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRulePausePhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .pause,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaPlayback", command: "pause")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRuleStopPlaybackPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .stop,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaPlayback", command: "stop")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }
    if AgentTextParser.containsAny(normalized, tvRulePlayPhrases) {
        return AgentRuleIntent(
            family: .media,
            intent: .start,
            capabilityPreferences: [AgentCapabilityCommand(capability: "mediaPlayback", command: "play")],
            parameters: [],
            deviceTypeHints: deviceTypeHints
        )
    }

    return nil
}

private func mediaInputSource(from normalized: String) -> String? {
    guard AgentTextParser.containsAny(normalized, tvRuleInputSourcePhrases) else {
        return nil
    }
    if normalized.contains("hdmi 1") || normalized.contains("hdmi1") {
        return "HDMI1"
    }
    if normalized.contains("hdmi 2") || normalized.contains("hdmi2") {
        return "HDMI2"
    }
    if normalized.contains("usb") {
        return "USB"
    }
    if normalized.contains(" av ") || normalized.hasSuffix(" av") || normalized.hasPrefix("av ") {
        return "AV"
    }
    if normalized.contains("input tv") || normalized.contains("input to tv") ||
        normalized.contains("source tv") || normalized.contains("source to tv") ||
        normalized.contains("tv source") || normalized.contains("source to television") {
        return "TV"
    }
    return nil
}

private func statusCapabilityPreferences(for normalized: String) -> [AgentCapabilityCommand] {
    if normalized.contains("battery") {
        return [AgentCapabilityCommand(capability: "battery", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["temperature", "hot", "cold"]) {
        return [AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus")]
    }
    if normalized.contains("humidity") {
        return [AgentCapabilityCommand(capability: "relativeHumidityMeasurement", command: "getStatus")]
    }
    if AgentTextParser.containsAny(normalized, ["open", "closed", "door"]) {
        return [
            AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
            AgentCapabilityCommand(capability: "garageDoorControl", command: "getStatus"),
            AgentCapabilityCommand(capability: "lock", command: "getStatus")
        ]
    }
    return [
        AgentCapabilityCommand(capability: "temperatureMeasurement", command: "getStatus"),
        AgentCapabilityCommand(capability: "contactSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "motionSensor", command: "getStatus"),
        AgentCapabilityCommand(capability: "switch", command: "getStatus"),
        AgentCapabilityCommand(capability: "battery", command: "getStatus")
    ]
}
