import Foundation

final class SharedDefaults {
    static let suiteName = "group.com.yourname.translatingkeyboard"
    /// Service identifier for the Keychain entries. The actual sharing
    /// between container app and extension is controlled by the
    /// `keychain-access-groups` entitlement, not this string.
    static let keychainService = "com.yourname.translatingkeyboard.api"

    /// Account name used both for the new Keychain entry and for the legacy
    /// UserDefaults entry we migrate away from.
    private static let apiKeyAccount = "claude_api_key"

    static let shared = SharedDefaults()

    /// `true` only when the App Group container is available. Container app
    /// and extension misconfigurations should not crash the keyboard
    /// extension — iOS disables keyboards that crash repeatedly. Callers
    /// check this and surface a setup error to the user instead.
    let isConfigured: Bool

    let defaults: UserDefaults?
    private let keychain = KeychainStore(service: SharedDefaults.keychainService)

    private init() {
        defaults = UserDefaults(suiteName: SharedDefaults.suiteName)
        isConfigured = (defaults != nil)
    }

    // MARK: - API key (reserved for the future AI-prediction mode)

    /// One-shot migration from a v1 plaintext UserDefaults entry to Keychain.
    /// Idempotent. Returns the migrated value so the triggering accessor
    /// doesn't need a second keychain round-trip.
    private func migrateLegacyAPIKeyIfNeeded() -> String? {
        guard let defaults else { return nil }
        guard let legacy = defaults.string(forKey: SharedDefaults.apiKeyAccount),
              !legacy.isEmpty else { return nil }
        if keychain.string(forKey: SharedDefaults.apiKeyAccount) == nil {
            _ = keychain.setString(legacy, forKey: SharedDefaults.apiKeyAccount)
        }
        defaults.removeObject(forKey: SharedDefaults.apiKeyAccount)
        return legacy
    }

    var apiKey: String? {
        get {
            if let key = keychain.string(forKey: SharedDefaults.apiKeyAccount),
               !key.isEmpty { return key }
            return migrateLegacyAPIKeyIfNeeded()
        }
        set {
            defaults?.removeObject(forKey: SharedDefaults.apiKeyAccount)
            _ = keychain.setString(newValue, forKey: SharedDefaults.apiKeyAccount)
        }
    }

    func synchronize() {
        defaults?.synchronize()
    }
}
