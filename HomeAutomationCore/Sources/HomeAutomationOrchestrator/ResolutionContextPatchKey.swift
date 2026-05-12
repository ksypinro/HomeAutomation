import Foundation

/// String constants used as dictionary keys when agents patch the `ResolutionContext`.
public enum ResolutionContextPatchKey {
    public static let resolverResult = "resolverResult"
    public static let language = "language"
    public static let domain = "domain"
    public static let intent = "intent"
    public static let deviceType = "deviceType"
    public static let slots = "slots"
    public static let risk = "risk"
    public static let resolutionState = "resolutionState"
    public static let retrievedCandidates = "retrievedCandidates"
    public static let selectedCandidateIDs = "selectedCandidateIDs"
    public static let aggregation = "aggregation"
    public static let hydratedCandidates = "hydratedCandidates"
    public static let knowledgeSnippets = "knowledgeSnippets"
    public static let retrievalReports = "retrievalReports"
    public static let instructionPackage = "instructionPackage"
    public static let draft = "draft"
    public static let executionPlan = "executionPlan"
    public static let resolution = "resolution"
}
