import Foundation
import HomeAutomationOrchestrator

let detector = HomeOperationDetectionService()
let result = detector.detect("Delete my morning automation")
print("Operation: \(result.operation)")
