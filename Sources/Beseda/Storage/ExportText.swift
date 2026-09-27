import Foundation

enum ExportText {
    static func get(_ key: String, locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier == "ru" ? "ru" : "en"
        guard let path = Bundle.besedaResources.path(forResource: language, ofType: "lproj", inDirectory: "Resources"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Export")
    }
}
