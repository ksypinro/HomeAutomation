public protocol CommandParaphraseProvider: Sendable {
    func paraphrases(for spec: CanonicalCommandSpec, count: Int) async throws -> [String]
}

public enum CommandParaphraseProviderError: Error, Sendable, Equatable {
    case unsupported(String)
    case liveModelUnavailable(String)
    case invalidModelJSON(String)
    case codexCLIUnavailable(String)
    case codexCLIExecutionFailed(exitCode: Int32, stderr: String)
    case codexCLIInvalidOutput(String)
    case semanticDriftRejected(specID: String, rejectedCount: Int)
    case insufficientValidParaphrases(specID: String, requested: Int, accepted: Int)
    case modelGenerationFailed(String)
}
