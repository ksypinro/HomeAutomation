public protocol HomeCandidateResolving: Sendable {
    func resolveCandidates(
        userText: String,
        resolutionState: HomeResolutionState,
        candidates: [HomeCompactCandidateView]
    ) async throws -> HomeCandidateAggregationResult
}
