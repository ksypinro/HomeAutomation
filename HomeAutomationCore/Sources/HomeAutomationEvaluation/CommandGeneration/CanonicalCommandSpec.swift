import Foundation
import HomeAutomationCore

public enum CanonicalCommandCategory: String, Sendable, Codable, Hashable {
    case directPower
    case brightness
    case climate
    case media
    case lockOpenClose
    case statusQuery
    case scheduleAutomation
    case conditionAutomation
    case unsupported
}

public struct CanonicalCommandSpec: Sendable, Codable, Hashable {
    public let id: String
    public let fixtureID: String
    public let suite: String
    public let tags: [String]
    public let category: CanonicalCommandCategory
    public let canonicalUtterance: String
    public let deviceDisplayName: String?
    public let room: String?
    public let expected: ExpectedResolvedOutput

    public init(
        id: String,
        fixtureID: String,
        suite: String,
        tags: [String] = [],
        category: CanonicalCommandCategory,
        canonicalUtterance: String,
        deviceDisplayName: String? = nil,
        room: String? = nil,
        expected: ExpectedResolvedOutput
    ) {
        self.id = id
        self.fixtureID = fixtureID
        self.suite = suite
        self.tags = tags
        self.category = category
        self.canonicalUtterance = canonicalUtterance
        self.deviceDisplayName = deviceDisplayName
        self.room = room
        self.expected = expected
    }
}
