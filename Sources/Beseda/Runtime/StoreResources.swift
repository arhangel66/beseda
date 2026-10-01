import Foundation

extension Bundle {
    static nonisolated var besedaResources: Bundle {
        // codesign refuses anything in the .app root, where SwiftPM's accessor looks, so every bundle keeps it here
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Beseda_Beseda.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }
}
