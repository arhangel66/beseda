import Foundation

enum SettingsText {
    static func webhookResponse(status: Int, action: String?, seconds: String, locale: Locale = .current) -> String {
        String(format: get("Webhook response %d%@ in %@ seconds", locale: locale), status,
               action.map { " · \($0)" } ?? "", seconds)
    }

    static func serviceFailure(_ message: String, locale: Locale = .current) -> String {
        if message == "Микрофон не доступен" { return get(message, locale: locale) }
        if message.hasPrefix("Сервер ответил "), let status = Int(message.dropFirst("Сервер ответил ".count)) {
            return String(format: get("Summary server returned HTTP %d. Check the server and try again.", locale: locale), status)
        }
        return webhookMessage(message, locale: locale)
    }

    static func webhookMessage(_ message: String, locale: Locale = .current) -> String {
        if locale.language.languageCode?.identifier == "ru" { return message }
        if message.hasPrefix("повтор в ") {
            return String(format: get("Retry at %@", locale: locale), String(message.dropFirst("повтор в ".count)))
        }
        if message.hasPrefix("Сервис отклонил запрос: HTTP ") {
            return String(format: get("Service rejected the request: HTTP %@", locale: locale), String(message.dropFirst("Сервис отклонил запрос: HTTP ".count)))
        }
        if message.hasPrefix("Сервис не ответил за ") {
            return String(format: get("Service did not respond within %@", locale: locale), String(message.dropFirst("Сервис не ответил за ".count).dropLast(2)))
        }
        return get(message, locale: locale)
    }

    static func get(_ key: String, locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier == "ru" ? "ru" : "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj", inDirectory: "Resources"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Settings")
    }
}
