import Foundation
import HomeAutomationAgents
import HomeAutomationCore
import Testing

@Suite
struct TelevisionCapabilityVariationTests {
    @Test
    func televisionCapabilityVariationMatrixHasTwentyPhrasesPerCommand() {
        let grouped = Dictionary(grouping: Self.variations) { $0.key }

        #expect(Self.variations.count == 320)
        for key in Self.expectedKeys {
            #expect(grouped[key]?.count == 20)
        }
    }

    @Test
    func capabilityResolutionHandlesTelevisionCapabilityVariationMatrix() async throws {
        let agent = CapabilityResolutionAgent()
        let tv = try await Self.device(id: "living_room_tv")

        for variation in Self.variations {
            let decision = try await agent.run(
                CapabilityResolutionInput(
                    rawText: variation.text,
                    resolutionState: Self.state(variation.text),
                    hydratedCandidates: [tv],
                    aggregation: HomeCandidateAggregationResult(
                        finalCandidateIDs: [tv.id],
                        needsClarification: false,
                        confidence: 0.95
                    ),
                    knowledgeSnippets: []
                ),
                context: Self.context(text: variation.text)
            )

            #expect(
                decision.targetDeviceID == "living_room_tv",
                "Capability resolution target mismatch for '\(variation.text)': expected living_room_tv, got \(decision.targetDeviceID ?? "nil")"
            )
            #expect(
                decision.selectedCapability == variation.capability,
                "Capability resolution capability mismatch for '\(variation.text)': expected \(variation.capability), got \(decision.selectedCapability ?? "nil")"
            )
            #expect(
                decision.selectedCommand == variation.command,
                "Capability resolution command mismatch for '\(variation.text)': expected \(variation.command), got \(decision.selectedCommand ?? "nil")"
            )
        }
    }

    @Test
    func ruleFallbackHandlesTelevisionCapabilityVariationMatrix() async throws {
        let registry = MockHomeDeviceRegistry()
        let resolver = AgentRuleBasedResolver(
            registry: registry,
            validator: AgentCommandValidator(),
            executor: AgentPlanExecutor(registry: registry),
            bixbyFallbackMapper: AgentBixbyFallbackMapper()
        )

        for variation in Self.variations {
            let result = try await resolver.resolve(variation.text, executeLowRiskCommands: false)

            #expect(
                result.draft?.targetDeviceID == "living_room_tv",
                "Rule fallback target mismatch for '\(variation.text)': expected living_room_tv, got \(result.draft?.targetDeviceID ?? "nil"); resolution=\(result.resolution)"
            )
            #expect(
                result.draft?.capability == variation.capability,
                "Rule fallback capability mismatch for '\(variation.text)': expected \(variation.capability), got \(result.draft?.capability ?? "nil"); resolution=\(result.resolution)"
            )
            #expect(
                result.draft?.command == variation.command,
                "Rule fallback command mismatch for '\(variation.text)': expected \(variation.command), got \(result.draft?.command ?? "nil"); resolution=\(result.resolution)"
            )
        }
    }

    private static let expectedKeys: [String] = [
        "switch.on",
        "switch.off",
        "audioVolume.setVolume",
        "audioVolume.volumeUp",
        "audioVolume.volumeDown",
        "audioVolume.mute",
        "audioVolume.unmute",
        "mediaPlayback.play",
        "mediaPlayback.pause",
        "mediaPlayback.stop",
        "mediaPlayback.fastForward",
        "mediaPlayback.rewind",
        "mediaInputSource.setInputSource",
        "channel.setChannel",
        "channel.channelUp",
        "channel.channelDown"
    ]

    private static let variations: [TVCommandVariation] =
        command("switch", "on", [
            "turn on living room TV",
            "switch on living room TV",
            "power on living room TV",
            "power up living room TV",
            "start living room TV",
            "enable living room TV",
            "activate living room TV",
            "wake up living room TV",
            "wake living room TV",
            "boot living room TV",
            "boot up living room TV",
            "fire up living room TV",
            "bring on living room TV",
            "put on living room TV",
            "start up living room TV",
            "energize living room TV",
            "turn on the living room television",
            "switch on the living room television",
            "power up the living room television",
            "activate the living room television"
        ]) +
        command("switch", "off", [
            "turn off living room TV",
            "switch off living room TV",
            "power off living room TV",
            "power down living room TV",
            "shut off living room TV",
            "shut down living room TV",
            "disable living room TV",
            "deactivate living room TV",
            "sleep living room TV",
            "put to sleep living room TV",
            "kill power to living room TV",
            "stop power to living room TV",
            "cut power to living room TV",
            "switch down living room TV",
            "turn off living room television",
            "power down living room television",
            "shut off living room television",
            "deactivate living room television",
            "disable living room television",
            "put living room TV to sleep"
        ]) +
        command("audioVolume", "setVolume", [
            "set volume of living room TV to 20",
            "change volume of living room TV to 21",
            "put volume of living room TV at 22",
            "adjust volume of living room TV to 23",
            "make volume of living room TV 24",
            "set sound level of living room TV to 25",
            "change sound level of living room TV to 26",
            "set audio level of living room TV to 27",
            "adjust audio level of living room TV to 28",
            "set speaker level of living room TV to 29",
            "put loudness of living room TV at 30",
            "make living room TV volume 31",
            "set living room TV volume to 32",
            "set living room television volume to 33",
            "set volume to 34 on living room TV",
            "set volume 35 for living room TV",
            "adjust living room TV loudness to 36",
            "make living room TV sound level 37",
            "set living room TV audio level to 38",
            "set living room TV speaker level to 39"
        ]) +
        command("audioVolume", "volumeUp", [
            "volume up living room TV",
            "turn up living room TV volume",
            "increase volume on living room TV",
            "raise volume on living room TV",
            "make living room TV louder",
            "boost volume on living room TV",
            "pump up volume on living room TV",
            "make louder the living room TV",
            "amplify volume on living room TV",
            "add volume to living room TV",
            "bump volume up on living room TV",
            "nudge volume up on living room TV",
            "crank up volume on living room TV",
            "more volume on living room TV",
            "lift volume on living room TV",
            "turn sound up on living room TV",
            "raise audio on living room TV",
            "increase audio on living room TV",
            "up the sound on living room TV",
            "make living room TV louder"
        ]) +
        command("audioVolume", "volumeDown", [
            "volume down living room TV",
            "turn down living room TV volume",
            "decrease volume on living room TV",
            "lower volume on living room TV",
            "make living room TV quieter",
            "reduce volume on living room TV",
            "soften volume on living room TV",
            "drop volume on living room TV",
            "bring down volume on living room TV",
            "make quieter the living room TV",
            "lower audio on living room TV",
            "turn sound down on living room TV",
            "less volume on living room TV",
            "dial down volume on living room TV",
            "nudge volume down on living room TV",
            "cut volume on living room TV",
            "quiet down living room TV",
            "reduce audio on living room TV",
            "lower sound on living room TV",
            "make living room TV softer"
        ]) +
        command("audioVolume", "mute", [
            "mute living room TV",
            "silence living room TV",
            "turn sound off on living room TV",
            "disable audio on living room TV",
            "kill audio on living room TV",
            "kill sound on living room TV",
            "cut audio on living room TV",
            "cut the sound on living room TV",
            "no sound on living room TV",
            "quiet the living room TV",
            "shush living room TV",
            "shush the living room TV",
            "turn audio off on living room TV",
            "turn volume off on living room TV",
            "remove sound from living room TV",
            "block sound on living room TV",
            "suppress audio on living room TV",
            "make living room TV silent",
            "silence audio on living room TV",
            "silence the living room TV"
        ]) +
        command("audioVolume", "unmute", [
            "unmute living room TV",
            "restore sound on living room TV",
            "turn sound back on living room TV",
            "enable audio on living room TV",
            "bring audio back on living room TV",
            "take off mute on living room TV",
            "restore audio on living room TV",
            "sound back on living room TV",
            "cancel mute on living room TV",
            "remove mute on living room TV",
            "undo mute on living room TV",
            "turn volume back on living room TV",
            "re-enable sound on living room TV",
            "let audio play on living room TV",
            "unsilence living room TV",
            "wake the sound on living room TV",
            "resume sound on living room TV",
            "restore living room TV volume",
            "enable sound on living room TV",
            "bring back sound on living room TV"
        ]) +
        command("mediaPlayback", "play", [
            "play living room TV",
            "resume living room TV playback",
            "continue living room TV playback",
            "start playback on living room TV",
            "begin playback on living room TV",
            "start playing on living room TV",
            "resume playback on living room TV",
            "play media on living room TV",
            "play video on living room TV",
            "continue show on living room TV",
            "resume show on living room TV",
            "start the program on living room TV",
            "begin the video on living room TV",
            "play the movie on living room TV",
            "continue the movie on living room TV",
            "restart playback on living room TV",
            "roll video on living room TV",
            "run playback on living room TV",
            "start streaming on living room TV",
            "resume streaming on living room TV"
        ]) +
        command("mediaPlayback", "pause", [
            "pause living room TV",
            "hold playback on living room TV",
            "freeze playback on living room TV",
            "pause video on living room TV",
            "pause show on living room TV",
            "suspend playback on living room TV",
            "stop temporarily on living room TV",
            "put playback on hold on living room TV",
            "hold the show on living room TV",
            "pause media on living room TV",
            "pause stream on living room TV",
            "halt playback on living room TV",
            "park the video on living room TV",
            "pause program on living room TV",
            "pause the living room TV content",
            "take a break on living room TV",
            "pause what is playing on living room TV",
            "pause the movie on living room TV",
            "pause the current video on living room TV",
            "hold current playback on living room TV"
        ]) +
        command("mediaPlayback", "stop", [
            "stop playback on living room TV",
            "stop media on living room TV",
            "stop video on living room TV",
            "end playback on living room TV",
            "end show on living room TV",
            "halt media on living room TV",
            "quit playback on living room TV",
            "terminate playback on living room TV",
            "cancel playback on living room TV",
            "stop stream on living room TV",
            "shut playback down on living room TV",
            "close media playback on living room TV",
            "finish playback on living room TV",
            "stop current video on living room TV",
            "end program on living room TV",
            "cease playback on living room TV",
            "cut playback on living room TV",
            "stop what is playing on living room TV",
            "turn playback off on living room TV",
            "halt the show on living room TV"
        ]) +
        command("mediaPlayback", "fastForward", [
            "fast forward living room TV",
            "skip ahead on living room TV",
            "jump ahead on living room TV",
            "scan forward on living room TV",
            "advance playback on living room TV",
            "go forward on living room TV",
            "move forward on living room TV",
            "skip forward on living room TV",
            "advance video on living room TV",
            "cue forward on living room TV",
            "seek ahead on living room TV",
            "scrub forward on living room TV",
            "forward the playback on living room TV",
            "hurry ahead on living room TV",
            "speed ahead on living room TV",
            "leap ahead on living room TV",
            "wind forward on living room TV",
            "move ahead in video on living room TV",
            "push playback forward on living room TV",
            "fast forward playback on living room TV"
        ]) +
        command("mediaPlayback", "rewind", [
            "rewind living room TV",
            "go back on living room TV",
            "skip back on living room TV",
            "jump back on living room TV",
            "scan backward on living room TV",
            "move backward on living room TV",
            "rewind playback on living room TV",
            "seek back on living room TV",
            "scrub back on living room TV",
            "back up video on living room TV",
            "reverse playback on living room TV",
            "wind back on living room TV",
            "return earlier on living room TV",
            "go earlier on living room TV",
            "move back in video on living room TV",
            "step back on living room TV",
            "roll back playback on living room TV",
            "backtrack playback on living room TV",
            "pull playback back on living room TV",
            "rewind video on living room TV"
        ]) +
        command("mediaInputSource", "setInputSource", [
            "set living room TV input to HDMI 1",
            "change living room TV input to HDMI 2",
            "switch living room TV input to USB",
            "select AV input on living room TV",
            "choose TV source on living room TV",
            "set living room TV source to HDMI1",
            "change source to HDMI2 on living room TV",
            "switch source to USB on living room TV",
            "select source AV on living room TV",
            "choose input TV on living room TV",
            "route living room TV to HDMI 1",
            "use HDMI 2 on living room TV",
            "use USB input on living room TV",
            "move source to AV on living room TV",
            "set TV source to TV on living room TV",
            "change input source to HDMI1 on living room TV",
            "switch input source to HDMI2 on living room TV",
            "select media input USB on living room TV",
            "choose HDMI 1 for living room TV",
            "set living room television input to HDMI 2"
        ]) +
        command("channel", "setChannel", [
            "set living room TV to channel 7",
            "change living room TV to channel 8",
            "tune living room TV to channel 9",
            "go to channel 10 on living room TV",
            "jump to channel 11 on living room TV",
            "select channel 12 on living room TV",
            "put channel 13 on living room TV",
            "open channel 14 on living room TV",
            "show channel 15 on living room TV",
            "move to channel 16 on living room TV",
            "switch to channel 17 on living room TV",
            "load channel 18 on living room TV",
            "choose channel 19 on living room TV",
            "watch channel 20 on living room TV",
            "set channel 21 for living room TV",
            "tune to channel 22 on living room TV",
            "go channel 23 on living room TV",
            "put living room TV on channel 24",
            "show station channel 25 on living room TV",
            "select broadcast channel 26 on living room TV"
        ]) +
        command("channel", "channelUp", [
            "next channel on living room TV",
            "channel up on living room TV",
            "increase channel on living room TV",
            "raise channel on living room TV",
            "move to next channel in living room TV",
            "advance channel on living room TV",
            "go up one channel on living room TV",
            "step up a channel on living room TV",
            "skip to next channel on living room TV",
            "flip to next channel on living room TV",
            "channel forward on living room TV",
            "tune up one channel on living room TV",
            "scan up one channel on living room TV",
            "nudge channel up on living room TV",
            "hop to next channel on living room TV",
            "jump to next channel on living room TV",
            "browse forward on living room TV",
            "cycle forward on living room TV",
            "go forward one channel on living room TV",
            "move channel forward on living room TV"
        ]) +
        command("channel", "channelDown", [
            "previous channel on living room TV",
            "prev channel on living room TV",
            "last channel on living room TV",
            "channel down on living room TV",
            "decrease channel on living room TV",
            "lower channel on living room TV",
            "move to previous channel in living room TV",
            "go back a channel on living room TV",
            "step down a channel on living room TV",
            "channel back on living room TV",
            "tune down one channel on living room TV",
            "scan down one channel on living room TV",
            "hop back a channel on living room TV",
            "jump to prior channel on living room TV",
            "flip to previous channel on living room TV",
            "back one channel on living room TV",
            "cycle backward on living room TV",
            "browse backward on living room TV",
            "return to previous channel on living room TV",
            "move channel backward on living room TV"
        ])

    private static func command(
        _ capability: String,
        _ command: String,
        _ texts: [String]
    ) -> [TVCommandVariation] {
        texts.map { TVCommandVariation(text: $0, capability: capability, command: command) }
    }

    private static func context(text: String) -> ResolutionContext {
        ResolutionContext(request: CommandRequest(text: text, executeLowRiskCommands: false))
    }

    private static func state(_ text: String) -> HomeResolutionState {
        AgentTextParser.deterministicState(for: text, confidence: 1)
    }

    private static func device(id: String) async throws -> HomeCandidateRecord {
        let devices = await MockHomeDeviceRegistry().allDevices()
        return try #require(devices.first { $0.id == id })
    }
}

private struct TVCommandVariation: Sendable {
    let text: String
    let capability: String
    let command: String

    var key: String {
        "\(capability).\(command)"
    }
}
