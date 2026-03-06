import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("AmadeusApp_AmadeusApp.bundle").path
        let buildPath = "/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/.build/arm64-apple-macosx/debug/AmadeusApp_AmadeusApp.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}