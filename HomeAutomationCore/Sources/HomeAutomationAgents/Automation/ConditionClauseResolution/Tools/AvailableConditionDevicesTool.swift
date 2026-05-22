import Foundation
import HomeAutomationCore

public enum AvailableConditionDevicesTool {
    public static func promptList(from devices: [HomeCandidateRecord]) -> String {
        devices.map { device in
            let room = device.room ?? "unknown"
            return "- id=\(device.id), name=\(device.displayName), type=\(device.deviceType), room=\(room), capabilities=[\(device.capabilities.joined(separator: ", "))]"
        }
        .joined(separator: "\n")
    }
}
