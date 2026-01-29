//
//  AuthAPI.swift
//  Construct Messenger
//
//  Authentication and account management API
//  Created on 26.01.2026 (Phase 2.1 refactoring)
//

import Foundation

/// Authentication and account management endpoints
class AuthAPI {
    static let shared = AuthAPI()
    
    private let client = RestAPIClient.shared
    
    private init() {}
    
    // MARK: - Authentication Endpoints
    
    /// Register a new user
    /// POST /api/v1/auth/register
    func register(username: String, password: String, publicKey: UploadableKeyBundle) async throws -> RegisterSuccessData {
        let endpoint = "/api/v1/auth/register"
        
        let requestBody: [String: Any] = [
            "username": username,
            "password": password,
            "keyBundle": [
                "masterIdentityKey": publicKey.masterIdentityKey,
                "bundleData": publicKey.bundleData,
                "signature": publicKey.signature
            ]
        ]
        
        let response: AuthResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )
        
        // Calculate expiration timestamp
        let expiresTimestamp: Int64
        if let expiresAt = response.expiresAt {
            expiresTimestamp = expiresAt
        } else if let expiresIn = response.expiresIn {
            let expiresDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            expiresTimestamp = Int64(expiresDate.timeIntervalSince1970)
        } else {
            let expiresDate = Date().addingTimeInterval(3600)
            expiresTimestamp = Int64(expiresDate.timeIntervalSince1970)
        }
        
        return RegisterSuccessData(
            userId: response.userId,
            username: username,
            sessionToken: response.accessToken,
            refreshToken: response.refreshToken,
            expires: expiresTimestamp
        )
    }
    
    /// Login with username and password
    /// POST /api/v1/auth/login
    func login(username: String, password: String) async throws -> LoginSuccessData {
        let endpoint = "/api/v1/auth/login"
        let requestBody: [String: Any] = [
            "username": username,
            "password": password
        ]
        
        let response: AuthResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )
        
        Log.info("📥 Login response received:", category: "Network")
        Log.info("   userId: \(response.userId)", category: "Network")
        Log.info("   accessToken length: \(response.accessToken.count)", category: "Network")
        if let expiresAt = response.expiresAt {
            Log.info("   expiresAt: \(expiresAt) (raw value)", category: "Network")
        } else if let expiresIn = response.expiresIn {
            Log.info("   expiresIn: \(expiresIn) seconds", category: "Network")
        }
        
        // Calculate expiration timestamp
        let expiresTimestamp: Int64
        if let expiresAt = response.expiresAt {
            // Old format: Unix timestamp
            if expiresAt > 1_000_000_000_000 {
                // Milliseconds
                expiresTimestamp = expiresAt / 1000
                Log.info("   Interpreting expiresAt as milliseconds", category: "Network")
            } else {
                // Seconds
                expiresTimestamp = expiresAt
                Log.info("   Interpreting expiresAt as seconds", category: "Network")
            }
        } else if let expiresIn = response.expiresIn {
            // New format: seconds from now
            let expiresDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            expiresTimestamp = Int64(expiresDate.timeIntervalSince1970)
            Log.info("   Calculated expiration from expiresIn", category: "Network")
        } else {
            // Fallback: 1 hour
            let expiresDate = Date().addingTimeInterval(3600)
            expiresTimestamp = Int64(expiresDate.timeIntervalSince1970)
            Log.info("⚠️ No expiration info - defaulting to 1 hour", category: "Network")
        }
        
        let expiresDate = Date(timeIntervalSince1970: TimeInterval(expiresTimestamp))
        Log.info("   Expires at: \(expiresDate)", category: "Network")
        Log.info("   Expires in: \(Int(expiresDate.timeIntervalSinceNow / 60)) minutes", category: "Network")
        
        return LoginSuccessData(
            userId: response.userId,
            username: username,
            sessionToken: response.accessToken,
            refreshToken: response.refreshToken,
            expires: expiresTimestamp
        )
    }
    
    /// Logout current session
    /// POST /api/v1/auth/logout
    func logout(sessionToken: String) async throws {
        let endpoint = "/api/v1/auth/logout"
        let requestBody: [String: Any] = [
            "all_devices": false
        ]
        
        let _: EmptyResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }
    
    /// Delete account
    /// POST /api/v1/auth/delete
    func deleteAccount(sessionToken: String, password: String) async throws {
        let endpoint = "/api/v1/auth/delete"
        let requestBody: [String: Any] = [
            "password": password
        ]
        
        let _: EmptyResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }
    
    /// Refresh access token using refresh token
    /// POST /api/v1/auth/refresh
    func refreshToken(refreshToken: String) async throws -> AuthResponse {
        let endpoint = "/api/v1/auth/refresh"
        
        Log.info("🔄 Refreshing access token", category: "AuthAPI")
        
        let requestBody: [String: Any] = [
            "refreshToken": refreshToken
        ]
        
        let response: AuthResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true  // May use expired access_token (server allows this)
        )
        
        Log.info("✅ Token refreshed successfully (expiresIn: \(response.expiresIn ?? 0)s)", category: "AuthAPI")
        return response
    }
}
