import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("HomeAutomationCore_HomeAutomationCore.bundle").path
        let buildPath = "/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/.build/arm64-apple-macosx/debug/HomeAutomationCore_HomeAutomationCore.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}