import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import HomeAutomationRAG

public protocol EvaluationCoordinating: Sendable {
    func makeOrchestrator(for testCase: EvaluationCase, mode: EvaluationMode) -> HomeCommandOrchestrator
    func makeKnowledgeIndexer() -> KnowledgeIndexer
}

public struct EvaluationCoordinator: EvaluationCoordinating {
    private let ragCoordinator: RAGCoordinator

    public init(ragCoordinator: RAGCoordinator = RAGCoordinator()) {
        self.ragCoordinator = ragCoordinator
    }

    public func makeOrchestrator(
        for testCase: EvaluationCase,
        mode: EvaluationMode
    ) -> HomeCommandOrchestrator {
        let registry = DeviceCoordinator.makeMockDeviceRegistry(
            devices: testCase.fixture.devices.isEmpty ? nil : testCase.fixture.devices
        )
        return HomeAutomationRootCoordinator(
            deviceRegistry: registry,
            foundationModelAvailability: { mode == .live }
        ).makeOrchestrator()
    }

    public func makeKnowledgeIndexer() -> KnowledgeIndexer {
        ragCoordinator.makeKnowledgeIndexer(cache: nil)
    }
}
