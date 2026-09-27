import Foundation
import os
import Security

/// Generic-password items of one service in the login keychain; the account is the setting's key.
/// A class so a test can subclass it into one whose writes fail; immutable, so it is shared with
/// the background read.
class Keychain: @unchecked Sendable {
    let service: String
    /// where builds up to 0.4.x kept the keys. A login-keychain item trusts only the signature
    /// that created it, so a build signed otherwise (Developer ID) gets a prompt reading it; the
    /// value is copied into `service` once, where this build owns it and later reads are silent
    let legacyService: String?

    /// the app's own keys; derived from the bundle id so an isolated copy never touches the installed app's
    static var app: Keychain {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.beseda.Beseda"
        return Keychain(service: "\(bundleID).keys", legacyService: bundleID)
    }

    /// only the real app outside the isolated-launch recipe opens the login keychain: a copy under
    /// another bundle id, a copy launched with a temp home, or a test run shares his login keychain,
    /// and reading the main app's items there puts a permission dialog on his screen
    static let usesLoginKeychain: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return Bundle.main.bundleIdentifier == "app.beseda.Beseda"
            && environment["BESEDA_NO_KEYCHAIN"] == nil && environment["CFFIXED_USER_HOME"] == nil
    }()
    /// where secrets live when the login keychain is off, keyed by service then account; gone at exit
    private static let memory = OSAllocatedUnfairLock(initialState: [String: [String: String]]())

    init(service: String, legacyService: String? = nil) {
        self.service = service
        self.legacyService = legacyService
    }

    func read(account: String) -> String? {
        if let value = read(account: account, service: service) {
            return value
        }
        guard let legacyService, let value = read(account: account, service: legacyService) else {
            return nil
        }
        // the legacy item stays: it is the copy an older build still reads after a rollback
        _ = save(value, account: account)
        return value
    }

    private func read(account: String, service: String) -> String? {
        guard Self.usesLoginKeychain else {
            return Self.memory.withLock { $0[service]?[account] }
        }
        var query = baseQuery(account: account, service: service)
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
        guard Self.usesLoginKeychain else {
            Self.memory.withLock { $0[service, default: [:]][account] = value }
            return true
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess && read(account: account, service: service) == value
    }

    /// every item of this service; tests clean up with it
    func deleteAll() {
        guard Self.usesLoginKeychain else {
            Self.memory.withLock { $0[service] = nil }
            return
        }
        // the file-based login keychain can leave a match behind on one call
        let query = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary
        while SecItemDelete(query) == errSecSuccess {}
    }

    private func baseQuery(account: String, service: String? = nil) -> [String: Any] {
        let service = service ?? self.service
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
