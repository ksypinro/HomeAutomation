public protocol HomeWorkerSessionAnalyzing: Sendable {
    func analyze(_ text: String) async throws -> HomeResolutionState
}
