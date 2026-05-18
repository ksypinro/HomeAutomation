import Foundation
import HomeAutomationOrchestrator
import HomeAutomationAgents
import HomeAutomationCore

func main() async {
    let orchestrator = HomeCommandOrchestrator(
        deviceRegistry: MockHomeDeviceRegistry(),
        foundationModelAvailability: { false }
    )
    let result = try! await orchestrator.resolve("Delete my morning automation", executeLowRiskCommands: false)
    print("RESOLVED AS: \(result.resolution)")
    print("INTENT: \(result.state.intent.topFamilies)")
}

Task {
    await main()
    exit(0)
}
RunLoop.main.run()
