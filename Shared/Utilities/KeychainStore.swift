import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let s):
            return "Keychain error (\(s))."
        }
    }
}

/// Thin wrapper around `kSecClassGenericPassword`. Items are stored in the
/// shared keychain access group listed in both targets' .entitlements files,
/// so the container app and the keyboard extension see the same items.
///
/// `accessGroup` is intentionally optional. When `nil`, the system stores the
/// item in the first keychain-access-group entitled to the calling target —
/// for this project, that's the shared group, so app and extension share
/// state without needing to hardcode the team-id-prefixed group string.
struct KeychainStore {
    let service: String
    let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func string(forKey account: String) -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns `true` on success or when the key was already absent (for nil
    /// writes). Failures are silent rather than throwing — callers treat
    /// keychain unavailability the same as "no key configured".
    @discardableResult
    func setString(_ value: String?, forKey account: String) -> Bool {
        var baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup { baseQuery[kSecAttrAccessGroup] = accessGroup }

        guard let value, !value.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        // Item doesn't exist yet — add it. AccessibleAfterFirstUnlock so the
        // keyboard extension can read it after a device reboot once the user
        // unlocks the phone the first time.
        var addQuery = baseQuery
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
}
