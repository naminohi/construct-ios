//
//  ProtocolTypes.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import Foundation

// MARK: - Message
struct ChatMessage: Codable, Identifiable {
    let id: String
    let from: String
    let to: String

    // Double Ratchet fields (per API_V3_SPEC.md section 5.2.6)
    let ephemeralPublicKey: Data  // Binary 32 bytes (dh_public_key from EncryptedRatchetMessage)
    let messageNumber: UInt32  // message_number from EncryptedRatchetMessage
    let content: String  // Base64 encrypted content (ciphertext from EncryptedRatchetMessage)

    let timestamp: UInt64
}

// MARK: - Public User Info
struct PublicUserInfo: Codable, Identifiable {
    let id: String
    let username: String
    let avatarUrl: String?
    let bio: String?
}

// MARK: - Key Bundles
struct RegistrationBundle: Codable {
    let identityPublic: String
    let signedPrekeyPublic: String
    let signature: String
    let verifyingKey: String
    let suiteId: String // Changed from suiteID to match snake_case -> camelCase conversion
}

struct SignedPrekeyUpdate: Codable {
    let newPrekeyPublic: String
    let signature: String
}

