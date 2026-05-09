import Foundation

struct HomeCatalogDeviceType: Decodable {
    let id: String
}
struct Catalog: Decodable {
    let deviceTypes: [HomeCatalogDeviceType]
}

if let data = try? Data(contentsOf: URL(fileURLWithPath: "HomeAutomationCore/Sources/HomeAutomationCore/Resources/home_automation_capability_catalog.json")) {
    if let cat = try? JSONDecoder().decode(Catalog.self, from: data) {
        let ids = cat.deviceTypes.map { $0.id }
        print(ids.contains("routine"))
        print(ids.contains("scene"))
    } else { print("decode failed") }
} else { print("file not found") }
