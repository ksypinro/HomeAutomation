import Foundation
import HomeAutomationCore

public enum CapabilityAttributeCatalogTool {
    public static func promptList(for capabilities: [String]) -> String {
        capabilities.compactMap { capability in
            guard let definition = HomeCapabilityRegistry.definitions[capability] else {
                return nil
            }
            return "- \(capability): attributes=[\(definition.attributeNames.joined(separator: ", "))]"
        }
        .joined(separator: "\n")
    }
}
