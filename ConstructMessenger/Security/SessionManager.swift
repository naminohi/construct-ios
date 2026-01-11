//
//  SessionManager.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import Foundation

class SessionManager {
    static let shared = SessionManager()
    private init() {}

    var currentUserId: String? {
        KeychainManager.shared.loadUserId()
    }

    var sessionToken: String? {
        KeychainManager.shared.loadSessionToken()
    }

    // ✅ FIXED: Get session expiration timestamp
    var sessionExpires: Date? {
        guard let timestamp = UserDefaults.standard.object(forKey: UserDefaultsKey.sessionExpires.key) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    // ✅ FIXED: Check if session is valid (not expired)
    var isSessionValid: Bool {
        guard sessionToken != nil, currentUserId != nil else { return false }

        // Check expiration (with 5-minute buffer)
        guard let expires = sessionExpires else { return false }
        let bufferTime: TimeInterval = 5 * 60  // 5 minutes
        return Date().addingTimeInterval(bufferTime) < expires
    }

    // ✅ FIXED: Save session with expiration timestamp
    func saveSession(userId: String, token: String, expires: Int64) {
        KeychainManager.shared.saveUserId(userId)
        KeychainManager.shared.saveSessionToken(token)
        // Save expiration timestamp
        UserDefaults.standard.set(TimeInterval(expires), forKey: UserDefaultsKey.sessionExpires.key)
        print("✅ Session saved - expires at: \(Date(timeIntervalSince1970: TimeInterval(expires)))")
    }

    func clearSession() {
        KeychainManager.shared.deleteSessionToken()
        // Clear expiration timestamp
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.sessionExpires.key)
    }
}
