import Foundation
import HomeAutomationCore

public protocol LegacyDeviceRegistryProviding: Sendable {
    func allDevices() async -> [HomeCandidateRecord]
    func retrieveCandidates(text: String, hints: HomeResolutionState, limit: Int) async -> [HomeCandidateRecord]
    func executeLowRiskPlan(_ plan: HomeAutomationExecutionPlan) async throws -> HomeCandidateRecord
}

extension MockHomeDeviceRegistry: LegacyDeviceRegistryProviding {}
