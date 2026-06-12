import Foundation
import HomeAutomationCore
import os

public struct CapabilityResolutionInput: Sendable {
    public let rawText: String
    public let resolutionState: HomeResolutionState
    public let hydratedCandidates: [HomeCandidateRecord]
    public let aggregation: HomeCandidateAggregationResult
    public let knowledgeSnippets: [KnowledgeSnippet]

    public init(
        rawText: String,
        resolutionState: HomeResolutionState,
        hydratedCandidates: [HomeCandidateRecord],
        aggregation: HomeCandidateAggregationResult,
        knowledgeSnippets: [KnowledgeSnippet]
    ) {
        self.rawText = rawText
        self.resolutionState = resolutionState
        self.hydratedCandidates = hydratedCandidates
        self.aggregation = aggregation
        self.knowledgeSnippets = knowledgeSnippets
    }
}

/// Selects the most likely device capability and command before draft generation.
///
/// This agent makes capability matching explicit and evaluation-friendly. It does
/// not replace draft generation or safety validation; it provides structured
/// guidance and evidence for those later stages.
public struct CapabilityResolutionAgent: HomeAgent {
    public typealias Input = CapabilityResolutionInput
    public typealias Output = HomeCapabilityDecision

    public let id = AgentID.capabilityResolution
    public let capabilities: Set<AgentCapability> = [.capabilityResolution]
    public let timeoutNanoseconds: UInt64 = 30_000_000_000
    private let resolve: @Sendable (CapabilityResolutionInput) async throws -> HomeCapabilityDecision
    private let logger = Logger(subsystem: "HomeAutomation", category: "Agent.CapabilityResolution")

    public init(
        resolve: @escaping @Sendable (CapabilityResolutionInput) async throws -> HomeCapabilityDecision
    ) {
        self.resolve = resolve
    }

    public init() {
        self.resolve = Self.resolveDeterministically
    }

    public init(worker: CapabilityResolutionWorker) {
        self.resolve = { input in
            try await worker.resolve(input)
        }
    }

    public func run(
        _ input: CapabilityResolutionInput,
        context: ResolutionContext
    ) async throws -> HomeCapabilityDecision {
        logger.debug("[run] Executing CapabilityResolutionAgent")
        return try await resolve(input)
    }

    public static func resolveDeterministically(_ input: CapabilityResolutionInput) -> HomeCapabilityDecision {
        let target = selectedDevice(from: input)
        let alternatives = rankedAlternatives(input: input, target: target)
        let selected = alternatives.first
        let evidence = selected?.evidence ?? ["No supported capability matched the command with high confidence."]

        return HomeCapabilityDecision(
            selectedCapability: selected?.capability,
            selectedCommand: selected?.command,
            targetDeviceID: selected?.targetDeviceID ?? target?.id,
            alternatives: alternatives,
            evidence: evidence,
            confidence: selected?.confidence ?? 0.2
        )
    }

    private static func selectedDevice(from input: CapabilityResolutionInput) -> HomeCandidateRecord? {
        for id in input.aggregation.finalCandidateIDs {
            if let candidate = input.hydratedCandidates.first(where: { $0.id == id }) {
                return candidate
            }
        }
        return input.hydratedCandidates.first
    }

    private static func rankedAlternatives(
        input: CapabilityResolutionInput,
        target: HomeCandidateRecord?
    ) -> [HomeCapabilityAlternative] {
        guard let target else { return [] }
        let normalized = input.rawText.agentNormalizedHomeTokenString
        let families = input.resolutionState.intent.topFamilies
        var alternatives: [HomeCapabilityAlternative] = []

        for capability in target.capabilities {
            let commands = target.supportedCommands[capability, default: HomeCapabilityRegistry.supportedCommands(for: capability)]
            let proposal = commandProposal(
                capability: capability,
                commands: commands,
                normalizedText: normalized,
                families: families,
                state: input.resolutionState
            )
            guard let proposal else { continue }
            let evidence = evidenceLines(
                capability: capability,
                command: proposal.command,
                device: target,
                input: input,
                baseEvidence: proposal.evidence
            )
            alternatives.append(
                HomeCapabilityAlternative(
                    capability: capability,
                    command: proposal.command,
                    targetDeviceID: target.id,
                    confidence: proposal.confidence,
                    evidence: evidence
                )
            )
        }

        return alternatives
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.capability < $1.capability
                }
                return $0.confidence > $1.confidence
            }
            .prefix(5)
            .map { $0 }
    }

    private static func commandProposal(
        capability: String,
        commands: [String],
        normalizedText: String,
        families: [HomeAutomationIntentFamily],
        state: HomeResolutionState
    ) -> (command: String?, confidence: Double, evidence: [String])? {
        let hasPowerIntent = families.contains(.power)
        let hasTemperatureIntent = families.contains(.temperature)
        let hasBrightnessIntent = families.contains(.brightness)
        let hasLockIntent = families.contains(.lockUnlock)
        let hasOpenCloseIntent = families.contains(.openClose)
        let hasStatusIntent = families.contains(.statusQuery)
        let hasRoutineIntent = families.contains(.routine)
        let hasMediaIntent = families.contains(.media)
        let hasMediaControlIntent = containsAny(normalizedText, mediaControlPhrases)
        let hasTurnOn = containsAny(normalizedText, powerOnPhrases)
        let hasTurnOff = containsAny(normalizedText, powerOffPhrases)

        if capability == "switch", !hasMediaControlIntent, hasPowerIntent || hasTurnOn || hasTurnOff {
            if hasTurnOff, commands.contains("off") {
                return ("off", 0.95, ["Power intent and off phrase matched switch.off."])
            }
            if hasTurnOn, commands.contains("on") {
                return ("on", 0.95, ["Power intent and on phrase matched switch.on."])
            }
        }

        if capability == "lock", hasLockIntent || containsAny(normalizedText, ["lock", "unlock"]) {
            if normalizedText.contains("unlock"), commands.contains("unlock") {
                return ("unlock", 0.92, ["Lock/unlock intent matched lock.unlock."])
            }
            if normalizedText.contains("lock"), commands.contains("lock") {
                return ("lock", 0.9, ["Lock/unlock intent matched lock.lock."])
            }
        }

        if hasOpenCloseIntent || containsAny(normalizedText, ["open", "close"]) {
            if normalizedText.contains("open"), commands.contains("open") {
                return ("open", 0.88, ["Open/close intent matched \(capability).open."])
            }
            if normalizedText.contains("close"), commands.contains("close") {
                return ("close", 0.88, ["Open/close intent matched \(capability).close."])
            }
        }

        if capability == "switchLevel", hasBrightnessIntent {
            if commands.contains("setLevel"), !state.slots.values.isEmpty {
                return ("setLevel", 0.84, ["Brightness intent and numeric value matched switchLevel.setLevel."])
            }
            if containsAny(normalizedText, ["increase", "raise", "brighter"]), commands.contains("increaseValue") {
                return ("increaseValue", 0.78, ["Brightness increase phrase matched switchLevel.increaseValue."])
            }
            if containsAny(normalizedText, ["decrease", "lower", "dim"]), commands.contains("decreaseValue") {
                return ("decreaseValue", 0.78, ["Brightness decrease phrase matched switchLevel.decreaseValue."])
            }
        }

        if hasTemperatureIntent {
            if capability == "switch", (hasTurnOn || hasTurnOff) {
                if hasTurnOff, commands.contains("off") {
                    return ("off", 0.9, ["Temperature device power-off phrase matched switch.off."])
                }
                if hasTurnOn, commands.contains("on") {
                    return ("on", 0.9, ["Temperature device power-on phrase matched switch.on."])
                }
            }
            if capability == "thermostatCoolingSetpoint", commands.contains("setCoolingSetpoint"), !state.slots.values.isEmpty {
                return ("setCoolingSetpoint", 0.86, ["Temperature value matched thermostatCoolingSetpoint.setCoolingSetpoint."])
            }
            if capability == "thermostatHeatingSetpoint", commands.contains("setHeatingSetpoint"), !state.slots.values.isEmpty {
                return ("setHeatingSetpoint", 0.78, ["Temperature value matched thermostatHeatingSetpoint.setHeatingSetpoint."])
            }
            if capability == "airConditionerMode", commands.contains("setAirConditionerMode"), !state.slots.modes.isEmpty {
                return ("setAirConditionerMode", 0.76, ["AC mode phrase matched airConditionerMode.setAirConditionerMode."])
            }
            if capability == "airConditionerFanMode", commands.contains("setFanMode"), containsAny(normalizedText, ["fan", "speed"]) {
                return ("setFanMode", 0.74, ["Fan mode phrase matched airConditionerFanMode.setFanMode."])
            }
        }

        if hasMediaIntent || hasMediaControlIntent {
            if capability == "channel" {
                if containsAny(normalizedText, channelUpPhrases),
                   commands.contains("channelUp") {
                    return ("channelUp", 0.92, ["Media channel phrase matched channel.channelUp."])
                }
                if containsAny(normalizedText, channelDownPhrases),
                   commands.contains("channelDown") {
                    return ("channelDown", 0.92, ["Media channel phrase matched channel.channelDown."])
                }
                if containsAny(normalizedText, setChannelPhrases), !state.slots.values.isEmpty, commands.contains("setChannel") {
                    return ("setChannel", 0.88, ["Media channel number matched channel.setChannel."])
                }
            }

            if capability == "audioVolume" {
                if containsAny(normalizedText, unmutePhrases), commands.contains("unmute") {
                    return ("unmute", 0.98, ["Media audio phrase matched audioVolume.unmute."])
                }
                if containsAny(normalizedText, mutePhrases), commands.contains("mute") {
                    return ("mute", 0.97, ["Media audio phrase matched audioVolume.mute."])
                }
                if containsAny(normalizedText, volumeUpPhrases),
                   commands.contains("volumeUp") {
                    return ("volumeUp", 0.88, ["Media audio phrase matched audioVolume.volumeUp."])
                }
                if containsAny(normalizedText, volumeDownPhrases),
                   commands.contains("volumeDown") {
                    return ("volumeDown", 0.88, ["Media audio phrase matched audioVolume.volumeDown."])
                }
                if containsAny(normalizedText, setVolumePhrases), !state.slots.values.isEmpty, commands.contains("setVolume") {
                    return ("setVolume", 0.86, ["Media audio value matched audioVolume.setVolume."])
                }
            }

            if capability == "mediaPlayback" {
                if containsAny(normalizedText, fastForwardPhrases), commands.contains("fastForward") {
                    return ("fastForward", 0.88, ["Media playback phrase matched mediaPlayback.fastForward."])
                }
                if containsAny(normalizedText, rewindPhrases), commands.contains("rewind") {
                    return ("rewind", 0.88, ["Media playback phrase matched mediaPlayback.rewind."])
                }
                if containsAny(normalizedText, pausePhrases), commands.contains("pause") {
                    return ("pause", 0.88, ["Media playback phrase matched mediaPlayback.pause."])
                }
                if containsAny(normalizedText, stopPlaybackPhrases), commands.contains("stop") {
                    return ("stop", 0.86, ["Media playback phrase matched mediaPlayback.stop."])
                }
                if containsAny(normalizedText, playPhrases), commands.contains("play") {
                    return ("play", 0.96, ["Media playback phrase matched mediaPlayback.play."])
                }
            }

            if capability == "mediaInputSource",
               containsAny(normalizedText, inputSourcePhrases),
               commands.contains("setInputSource") {
                return ("setInputSource", 0.86, ["Media input phrase matched mediaInputSource.setInputSource."])
            }

            if capability == "appSelector",
               containsAny(normalizedText, ["open", "launch", "app", "netflix", "hulu", "youtube"]),
               commands.contains("launchApp") {
                return ("launchApp", 0.82, ["Media app phrase matched appSelector.launchApp."])
            }
        }

        if hasStatusIntent || containsAny(normalizedText, ["status", "check", "what is", "showing", "reading"]) {
            if commands.contains("getStatus") {
                return ("getStatus", 0.82, ["Status query matched \(capability).getStatus."])
            }
            if HomeCapabilityRegistry.definitions[capability]?.attributeNames.isEmpty == false {
                return ("getStatus", 0.72, ["Status query matched readable attribute for \(capability)."])
            }
        }

        if hasRoutineIntent, commands.contains("run") {
            return ("run", 0.8, ["Routine intent matched run command."])
        }

        return nil
    }

    private static func evidenceLines(
        capability: String,
        command: String?,
        device: HomeCandidateRecord,
        input: CapabilityResolutionInput,
        baseEvidence: [String]
    ) -> [String] {
        var evidence = baseEvidence
        evidence.append("Target device \(device.id) supports capability \(capability).")
        if let command {
            evidence.append("Target device \(device.id) supports command \(command): \(device.supportedCommands[capability, default: []].contains(command)).")
        }
        if !input.knowledgeSnippets.isEmpty {
            let matchedSources = input.knowledgeSnippets
                .filter { snippet in
                    snippet.content.agentNormalizedHomeTokenString.contains(capability.agentNormalizedHomeTokenString)
                }
                .prefix(3)
                .map(\.sourceID)
            if !matchedSources.isEmpty {
                evidence.append("RAG sources mention capability: \(matchedSources.joined(separator: ", ")).")
            }
        }
        return evidence
    }

    private static let powerOnPhrases = [
        "turn on", "switch on", "power on", "power up", "start", "enable", "activate", "wake up",
        "wake", "boot", "boot up", "fire up", "bring on", "put on", "start up", "energize"
    ]

    private static let powerOffPhrases = [
        "turn off", "switch off", "power off", "power down", "shut off", "shut down", "disable",
        "deactivate", "sleep", "put to sleep", "kill power", "stop power", "cut power", "switch down"
    ]

    private static let channelPhrases = [
        "channel", "station", "program", "broadcast", "tune"
    ]

    private static let channelUpPhrases = [
        "next channel", "channel up", "increase channel", "raise channel", "move to next channel",
        "advance channel", "go up one channel", "step up a channel", "skip to next channel",
        "flip to next channel", "channel forward", "tune up one channel", "scan up one channel",
        "nudge channel up", "hop to next channel", "jump to next channel", "browse forward",
        "cycle forward", "go forward one channel", "move channel forward"
    ]

    private static let channelDownPhrases = [
        "previous channel", "prev channel", "last channel", "channel down", "decrease channel",
        "lower channel", "move to previous channel", "go back a channel", "step down a channel",
        "channel back", "tune down one channel", "scan down one channel", "hop back a channel",
        "jump to prior channel", "flip to previous channel", "back one channel", "cycle backward",
        "browse backward", "return to previous channel", "move channel backward"
    ]

    private static let setChannelPhrases = [
        "channel", "station", "tune to channel", "go to channel", "jump to channel", "select channel",
        "put channel", "set channel", "open channel", "show channel", "move to channel",
        "switch to channel", "load channel", "choose channel", "watch channel"
    ]

    private static let setVolumePhrases = [
        "volume", "sound level", "audio level", "speaker level", "loudness"
    ]

    private static let volumeUpPhrases = [
        "volume up", "turn up", "increase volume", "raise volume", "louder", "boost volume",
        "pump up volume", "make louder", "amplify volume", "add volume", "bump volume up",
        "nudge volume up", "crank up volume", "more volume", "lift volume", "turn sound up",
        "raise audio", "increase audio", "up the sound", "make tv louder"
    ]

    private static let volumeDownPhrases = [
        "volume down", "turn down", "decrease volume", "lower volume", "quieter", "reduce volume",
        "soften volume", "drop volume", "bring down volume", "make quieter", "lower audio",
        "turn sound down", "less volume", "dial down volume", "nudge volume down", "cut volume",
        "quiet down", "reduce audio", "lower sound", "make tv softer", "softer", "make softer"
    ]

    private static let mutePhrases = [
        "mute", "silence", "turn sound off", "disable audio", "kill audio", "kill sound",
        "cut audio", "cut the sound", "no sound", "quiet the tv", "shush", "shush the tv",
        "turn audio off", "turn volume off", "remove sound", "block sound", "suppress audio",
        "make silent", "silence audio", "silence the tv", "quiet the", "silent"
    ]

    private static let unmutePhrases = [
        "unmute", "restore sound", "turn sound back on", "enable audio", "bring audio back",
        "take off mute", "restore audio", "sound back on", "cancel mute", "remove mute",
        "undo mute", "turn volume back on", "re enable sound", "let audio play", "unsilence",
        "wake the sound", "resume sound", "restore tv volume", "restore volume", "restore",
        "enable sound", "bring back sound"
    ]

    private static let playPhrases = [
        "play", "resume", "continue", "start playback", "begin playback", "start playing",
        "resume playback", "play media", "play video", "continue show", "resume show",
        "start the program", "begin the video", "play the movie", "continue the movie",
        "restart playback", "roll video", "run playback", "start streaming", "resume streaming"
    ]

    private static let pausePhrases = [
        "pause", "hold playback", "freeze playback", "pause video", "pause show",
        "suspend playback", "stop temporarily", "put playback on hold", "hold the show",
        "pause media", "pause stream", "halt playback", "park the video", "pause program",
        "pause the tv content", "take a break", "pause what is playing", "pause the movie",
        "pause the current video", "hold current playback"
    ]

    private static let stopPlaybackPhrases = [
        "stop playback", "stop media", "stop video", "end playback", "end show", "halt media",
        "quit playback", "terminate playback", "cancel playback", "stop stream",
        "shut playback down", "close media playback", "finish playback", "stop current video",
        "end program", "cease playback", "cut playback", "stop what is playing",
        "turn playback off", "halt the show"
    ]

    private static let fastForwardPhrases = [
        "fast forward", "skip ahead", "jump ahead", "scan forward", "advance playback",
        "go forward", "move forward", "skip forward", "advance video", "cue forward",
        "seek ahead", "scrub forward", "forward the playback", "hurry ahead", "speed ahead",
        "leap ahead", "wind forward", "move ahead in video", "push playback forward",
        "fast forward playback"
    ]

    private static let rewindPhrases = [
        "rewind", "go back", "skip back", "jump back", "scan backward", "move backward",
        "rewind playback", "seek back", "scrub back", "back up video", "reverse playback",
        "wind back", "return earlier", "go earlier", "move back in video", "step back",
        "roll back playback", "backtrack playback", "pull playback back", "rewind video"
    ]

    private static let inputSourcePhrases = [
        "input", "source", "hdmi", "usb", " av ", "select input", "choose input",
        "change input", "switch input", "set input", "select source", "choose source",
        "change source", "switch source", "set source", "route to", "use hdmi", "use usb",
        "move source", "tv source"
    ]

    private static let mediaControlPhrases =
        channelPhrases + channelUpPhrases + channelDownPhrases + setChannelPhrases +
        setVolumePhrases + volumeUpPhrases + volumeDownPhrases + mutePhrases + unmutePhrases +
        playPhrases + pausePhrases + stopPlaybackPhrases + fastForwardPhrases + rewindPhrases +
        inputSourcePhrases + ["audio", "sound", "media", "movie", "video", "playback", "streaming", "show", "content"]

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
