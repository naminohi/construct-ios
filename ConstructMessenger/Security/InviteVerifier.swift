//
//  InviteVerifier.swift
//  Construct Messenger
//
//  Created by Copilot on 29.01.2026.
//

import Foundation

/// Verifier for cryptographically secure one-time invite links
///
/// Usage:
/// ```swift
/// let verifier = InviteVerifier()
/// let invite = try verifier.decode(encodedString)
/// let isValid = try await verifier.verify(invite)
/// ```
class InviteVerifier {
    
    // MARK: - Decoding
    
    /// Decode invite from encoded string
    ///
    /// Expected format: Base64-encoded JSON
    ///
    /// - Parameter encoded: Base64-encoded invite string
    /// - Returns: Decoded InviteObject
    /// - Throws: InviteVerificationError
    func decode(_ encoded: String) throws -> InviteObject {
        // Decode Base64 to JSON
        guard let data = Data(base64Encoded: encoded) else {
            throw InviteVerificationError.invalidEncoding
        }
        
        guard let json = String(data: data, encoding: .utf8) else {
            throw InviteVerificationError.invalidUTF8
        }
        
        // Parse JSON to InviteObject
        let invite = try InviteObject.fromJSON(json)
        
        // Validate structure
        try invite.validate()
        
        Log.debug("📥 Decoded invite: jti=\(invite.jti.prefix(8))..., from=\(invite.uuid.prefix(8))...", category: "InviteVerifier")
        
        return invite
    }
    
    // MARK: - Verification
    
    /// Verify invite signature and expiry
    ///
    /// Checks:
    /// 1. Signature is valid (signed by claimed user)
    /// 2. Invite is not expired (TTL check)
    /// 3. (Server-side) JTI not already used
    ///
    /// - Parameters:
    ///   - invite: InviteObject to verify
    ///   - ttl: Time-to-live in seconds (default: 180 = 3 minutes)
    /// - Returns: true if valid
    /// - Throws: InviteVerificationError
    func verify(_ invite: InviteObject, ttl: TimeInterval = 180) async throws -> Bool {
        // Step 1: Check structure validity
        try invite.validate()
        
        // Step 2: Check expiry
        guard !invite.isExpired(ttl: ttl) else {
            Log.info("⚠️ Invite expired: jti=\(invite.jti.prefix(8))...", category: "InviteVerifier")
            throw InviteVerificationError.expired
        }
        
        // Step 3: Fetch sender's public key bundle
        let publicKeyBundle = try await fetchPublicKey(userId: invite.uuid, server: invite.server)
        
        // Step 4: Extract verifying key (Ed25519 public key)
        guard let verifyingKeyData = Data(base64Encoded: publicKeyBundle.verifyingKey) else {
            throw InviteVerificationError.invalidVerifyingKey
        }
        
        // Step 5: Extract signature
        guard let signatureData = Data(base64Encoded: invite.sig) else {
            throw InviteVerificationError.invalidSignature
        }
        
        // Step 6: Get canonical string (same as used for signing)
        let dataToVerify = invite.canonicalString()
        
        // Step 7: Verify signature using Rust core
        let isValid = try verifyInviteSignature(
            data: dataToVerify,
            signature: [UInt8](signatureData),
            verifyingKey: [UInt8](verifyingKeyData)
        )
        
        if isValid {
            Log.info("✅ Invite signature valid: jti=\(invite.jti.prefix(8))...", category: "InviteVerifier")
        } else {
            Log.info("❌ Invalid invite signature: jti=\(invite.jti.prefix(8))...", category: "InviteVerifier")
            throw InviteVerificationError.invalidSignature
        }
        
        return isValid
    }
    
    /// Check if invite has expired (local check only)
    /// - Parameters:
    ///   - invite: InviteObject
    ///   - ttl: Time-to-live in seconds
    /// - Returns: true if expired
    func checkExpiry(_ invite: InviteObject, ttl: TimeInterval = 180) -> Bool {
        return invite.isExpired(ttl: ttl)
    }
    
    // MARK: - Helper Methods
    
    /// Fetch public key bundle from server
    /// - Parameters:
    ///   - userId: User UUID
    ///   - server: Server FQDN
    /// - Returns: Public key bundle
    /// - Throws: InviteVerificationError
    private func fetchPublicKey(userId: String, server: String) async throws -> PublicKeyBundleData {
        // Use CryptoAPI to fetch
        do {
            let bundle = try await CryptoAPI.shared.getPublicKey(userId: userId)
            return bundle
        } catch {
            Log.error("❌ Failed to fetch public key for \(userId): \(error)", category: "InviteVerifier")
            throw InviteVerificationError.publicKeyFetchFailed(error)
        }
    }
}

// MARK: - Errors

enum InviteVerificationError: LocalizedError {
    case invalidEncoding
    case invalidUTF8
    case invalidSignature
    case invalidVerifyingKey
    case expired
    case publicKeyFetchFailed(Error)
    case alreadyUsed
    
    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Invalid Base64 encoding"
        case .invalidUTF8:
            return "Invalid UTF-8 in decoded data"
        case .invalidSignature:
            return "Invalid or tampered signature"
        case .invalidVerifyingKey:
            return "Invalid verifying key format"
        case .expired:
            return "Invite has expired"
        case .publicKeyFetchFailed(let error):
            return "Failed to fetch public key: \(error.localizedDescription)"
        case .alreadyUsed:
            return "Invite already used (JTI conflict)"
        }
    }
}

// MARK: - Encoding Helper

extension InviteObject {
    /// Encode invite to Base64 string for sharing
    /// - Returns: Base64-encoded invite
    /// - Throws: EncodingError
    func encode() throws -> String {
        let json = try toJSON()
        guard let data = json.data(using: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert JSON to UTF-8"
            ))
        }
        return data.base64EncodedString()
    }
}
