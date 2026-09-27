import Foundation

enum ArchiveText {
    static func format(_ key: String, _ values: CVarArg..., locale: Locale = .current) -> String {
        String(format: get(key, locale: locale), locale: locale, arguments: values)
    }

    static func displayError(_ error: String, locale: Locale = .current) -> String {
        let legacy = [
            "Обработка прервалась при перезапуске приложения",
            "Найдена на диске без записи в индексе",
            "Движок распознавания не установлен",
            "LM Studio не запущен"
        ]
        return legacy.contains(error) ? get(error, locale: locale) : error
    }

    static func get(_ key: String, locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier == "ru" ? "ru" : "en"
        guard let path = Bundle.besedaResources.path(forResource: language, ofType: "lproj", inDirectory: "Resources"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Archive")
    }
}
