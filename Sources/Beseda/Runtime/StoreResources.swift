import Foundation

extension Bundle {
    static nonisolated var besedaResources: Bundle {
#if BESEDA_STORE
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Beseda_Beseda.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
#else
        return .module
#endif
    }
}
