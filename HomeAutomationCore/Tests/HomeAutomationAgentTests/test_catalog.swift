import XCTest
import Foundation

struct HomeCatalogDeviceType: Decodable {
    let id: String
}
struct Catalog: Decodable {
    let deviceTypes: [HomeCatalogDeviceType]
}

final class CatalogTests: XCTestCase {
    func testCatalogDecoding() throws {
        // Adjust path according to how swift test runs (from the root of the package)
        let fileURL = URL(fileURLWithPath: "Sources/HomeAutomationCore/Resources/home_automation_capability_catalog.json")
        guard let data = try? Data(contentsOf: fileURL) else {
            XCTFail("Catalog file not found")
            return
        }
        
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        let ids = catalog.deviceTypes.map { $0.id }
        
        XCTAssertTrue(ids.contains("routine"), "Catalog should contain routine")
        XCTAssertTrue(ids.contains("scene"), "Catalog should contain scene")
    }
}
