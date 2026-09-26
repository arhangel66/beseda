import Foundation
import Security

/// Generic-password items of one service in the login keychain; the account is the setting's key.
/// A class so a test can subclass it into one whose writes fail.
class Keychain {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "app.beseda.Beseda") {
        self.service = service
    }

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// true only when the value reads back as written
    func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        var status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess && read(account: account) == value
    }

    /// every item of this service; tests clean up with it
    func deleteAll() {
        // the file-based login keychain can leave a match behind on one call
        let query = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary
        while SecItemDelete(query) == errSecSuccess {}
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
