import Foundation
import Observation
import Security

@MainActor
@Observable
final class PlaylistCredentials {
    static let shared = PlaylistCredentials()

    var username: String {
        didSet { KeychainCredentialStore.set(username, account: .username) }
    }

    var password: String {
        didSet { KeychainCredentialStore.set(password, account: .password) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let legacyUsername = defaults.string(forKey: "playlistUsername") ?? ""
        let legacyPassword = defaults.string(forKey: "playlistPassword") ?? ""

        username = KeychainCredentialStore.value(for: .username) ?? legacyUsername
        password = KeychainCredentialStore.value(for: .password) ?? legacyPassword

        if !legacyUsername.isEmpty || !legacyPassword.isEmpty {
            KeychainCredentialStore.set(username, account: .username)
            KeychainCredentialStore.set(password, account: .password)
            defaults.removeObject(forKey: "playlistUsername")
            defaults.removeObject(forKey: "playlistPassword")
        }
    }

    func clear() {
        username = ""
        password = ""
    }

    func savePassword(for profileID: UUID) {
        KeychainCredentialStore.set(password, accountName: "playlist.password.\(profileID.uuidString)")
    }

    func loadPassword(for profileID: UUID) {
        password = KeychainCredentialStore.value(accountName: "playlist.password.\(profileID.uuidString)") ?? ""
    }
}

private enum KeychainCredentialStore {
    enum Account: String {
        case username = "playlist.username"
        case password = "playlist.password"
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.tiptv.credentials"

    static func value(for account: Account) -> String? {
        value(accountName: account.rawValue)
    }

    static func value(accountName: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: Account) {
        set(value, accountName: account.rawValue)
    }

    static func set(_ value: String, accountName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName
        ]

        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
