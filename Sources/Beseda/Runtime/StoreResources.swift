import Foundation

extension Bundle {
    static nonisolated var besedaResources: Bundle {
#if BESEDA_STORE
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Beseda_Beseda.bundle"),
              let bundle = Bundle(url: url) else {
            fatalError("could not load store resources")
        }
        return bundle
#else
        return .module
#endif
    }
}
