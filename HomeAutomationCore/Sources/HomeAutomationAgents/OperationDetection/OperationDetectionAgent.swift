import Foundation
import HomeAutomationCore

public struct OperationDetectionAgent: HomeAgent {
    public typealias Input = String
    public typealias Output = HomeOperationDetectionResult

    public let id = AgentID.operationDetection
    public let capabilities: Set<AgentCapability> = [.operationDetection]
    public let timeoutNanoseconds: UInt64 = 60_000_000_000
    private let worker: OperationDetectionWorkerSession

    public init(
        worker: OperationDetectionWorkerSession = OperationDetectionWorkerSession(
            ruleDetect: { text in HomeOperationDetectionService().analyzeSemantics(text) }
        )
    ) {
        self.worker = worker
    }

    public func run(
        _ input: String,
        context: ResolutionContext
    ) async throws -> HomeOperationDetectionResult {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? context.request.text
            : input
        return try await worker.detectOperation(text)
    }
}
