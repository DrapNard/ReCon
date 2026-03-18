import Foundation
import Security

final class KeychainStore {
    enum Key: String, CaseIterable {
        case userId
        case machineId
        case token
        case password
        case uid
    }

    private let service = "com.drapnard.recon"
    private let itemAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = itemAccessibility
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: itemAccessibility,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            reportUnexpectedStatus(updateStatus, operation: "update", key: key)
        default:
            reportUnexpectedStatus(addStatus, operation: "add", key: key)
        }
    }

    func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            if status != errSecItemNotFound {
                reportUnexpectedStatus(status, operation: "get", key: key)
            }
            return nil
        }
        return value
    }

    func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            reportUnexpectedStatus(status, operation: "delete", key: key)
        }
    }

    func clearAll() {
        Key.allCases.forEach(delete)
    }

    private func reportUnexpectedStatus(_ status: OSStatus, operation: String, key: Key) {
        if status == errSecMissingEntitlement {
            return
        }
        #if DEBUG
        NSLog("Keychain \(operation) failed for key \(key.rawValue): \(status)")
        #endif
    }
}
