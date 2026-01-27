//
//  KeychainManager.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import Security
import Foundation

class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    // MARK: - Session Token
    func saveSessionToken(_ token: String) {
        guard let data = token.data(using: .utf8) else {
            Log.error("Failed to convert token to UTF-8 data", category: "Keychain")
            return
        }
        let success = save(data, forKey: APIConstants.sessionTokenKey, accessible: kSecAttrAccessibleAfterFirstUnlock)
        if !success {
            Log.error("Failed to save session token to Keychain", category: "Keychain")
        } else {
            Log.info("✅ Session token saved to Keychain (length: \(token.count), prefix: \(token.prefix(30))...)", category: "Keychain")
        }
    }

    func loadSessionToken() -> String? {
        guard let data = load(forKey: APIConstants.sessionTokenKey) else {
            Log.debug("No session token found in Keychain", category: "Keychain")
            return nil
        }
        guard let token = String(data: data, encoding: .utf8) else {
            Log.error("Failed to convert Keychain data to UTF-8 string", category: "Keychain")
            return nil
        }
        Log.debug("✅ Session token loaded from Keychain (length: \(token.count), prefix: \(token.prefix(30))...)", category: "Keychain")
        return token
    }

    func deleteSessionToken() {
        delete(forKey: APIConstants.sessionTokenKey)
    }

    // MARK: - Private Key
    func savePrivateKey(_ keyData: Data) {
        let success = save(keyData, forKey: APIConstants.privateKeyKey, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        if !success {
            Log.error("Failed to save private key to Keychain", category: "Keychain")
        }
    }

    func loadPrivateKey() -> Data? {
        load(forKey: APIConstants.privateKeyKey)
    }
    
    func saveIdentityKey(_ data: Data) -> Bool {
        return save(data, forKey: "identity_key", accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }
    
    func loadIdentityKey() -> Data? {
        return load(forKey: "identity_key")
    }
    
    // Signed prekey (X25519)
    func saveSignedPrekey(_ data: Data) -> Bool {
        return save(data, forKey: "signed_prekey", accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }
    
    func loadSignedPrekey() -> Data? {
        return load(forKey: "signed_prekey")
    }
    
    // Signing key (Ed25519)
    func saveSigningKey(_ data: Data) -> Bool {
        return save(data, forKey: "signing_key", accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }
    
    func loadSigningKey() -> Data? {
        return load(forKey: "signing_key")
    }

    // MARK: - Private Keys JSON (for Rust persistence)

    /// Save all private keys as JSON string (from Rust export)
    func savePrivateKeysJson(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        return save(data, forKey: "crypto_private_keys_json", accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    /// Load private keys JSON string (for Rust import)
    func loadPrivateKeysJson() -> String? {
        guard let data = load(forKey: "crypto_private_keys_json") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete private keys JSON
    func deletePrivateKeysJson() {
        delete(forKey: "crypto_private_keys_json")
    }

    // MARK: - User ID
    func saveUserId(_ userId: String) {
        guard let data = userId.data(using: .utf8) else { return }
        let success = save(data, forKey: APIConstants.userIdKey, accessible: kSecAttrAccessibleAfterFirstUnlock)
        if !success {
            Log.error("Failed to save user ID to Keychain", category: "Keychain")
        }
    }

    func loadUserId() -> String? {
        guard let data = load(forKey: APIConstants.userIdKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Username (for autofill convenience)
    // Note: We don't save passwords in Keychain - iOS Password AutoFill handles that securely
    func saveLastUsername(_ username: String) {
        guard let data = username.data(using: .utf8) else { return }
        let success = save(data, forKey: APIConstants.lastUsernameKey, accessible: kSecAttrAccessibleAfterFirstUnlock)
        if !success {
            Log.error("Failed to save last username to Keychain", category: "Keychain")
        }
    }
    
    func loadLastUsername() -> String? {
        guard let data = load(forKey: APIConstants.lastUsernameKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteLastUsername() {
        delete(forKey: APIConstants.lastUsernameKey)
    }
    
    // MARK: - Custom Server URL (persistent across app reinstalls)
    func saveCustomServerURL(_ url: String) {
        guard let data = url.data(using: .utf8) else { return }
        // Use kSecAttrAccessibleAfterFirstUnlock to allow access after device unlock
        // This persists across app reinstalls when iCloud Keychain is enabled
        let success = save(data, forKey: APIConstants.customServerURLKey, accessible: kSecAttrAccessibleAfterFirstUnlock)
        if !success {
            Log.error("Failed to save custom server URL to Keychain", category: "Keychain")
        }
    }
    
    func loadCustomServerURL() -> String? {
        guard let data = load(forKey: APIConstants.customServerURLKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteCustomServerURL() {
        delete(forKey: APIConstants.customServerURLKey)
    }
    
    func deleteAllKeys() {
        delete(forKey: "identity_key")
        delete(forKey: "signed_prekey")
        delete(forKey: "signing_key")
    }

    // MARK: - Session Persistence

    /// Save a session JSON string for a specific contact
    /// - Parameters:
    ///   - sessionJson: JSON string of the serialized session
    ///   - contactId: The contact/user ID this session belongs to
    /// - Returns: true if saved successfully
    func saveSessionJson(_ sessionJson: String, for contactId: String) -> Bool {
        guard let data = sessionJson.data(using: .utf8) else { return false }
        let key = "session_\(contactId)"
        return save(data, forKey: key, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    /// Load a session JSON string for a specific contact
    /// - Parameter contactId: The contact/user ID
    /// - Returns: JSON string of the serialized session, or nil if not found
    func loadSessionJson(for contactId: String) -> String? {
        let key = "session_\(contactId)"
        guard let data = load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a session for a specific contact
    /// - Parameter contactId: The contact/user ID
    func deleteSession(for contactId: String) {
        let key = "session_\(contactId)"
        delete(forKey: key)
    }

    /// Load all saved session IDs
    /// - Returns: Array of contact IDs that have saved sessions
    func loadAllSessionIds() -> [String] {
        // Note: Keychain doesn't have a direct way to list all keys
        // We'll need to track session IDs separately or use a different approach
        // For now, return empty array - we'll track sessions in Core Data
        return []
    }
    
    // MARK: - Generic Data Storage (for archived sessions, etc.)
    
    /// Save generic data to Keychain
    func saveData(_ data: Data, forKey key: String) -> Bool {
        return save(data, forKey: key, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }
    
    /// Load generic data from Keychain
    func loadData(forKey key: String) -> Data? {
        return load(forKey: key)
    }
    
    /// Delete generic data from Keychain
    func deleteData(forKey key: String) {
        delete(forKey: key)
    }

    // MARK: - Generic Helpers
    private func save(_ data: Data, forKey key: String, accessible: CFString) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
