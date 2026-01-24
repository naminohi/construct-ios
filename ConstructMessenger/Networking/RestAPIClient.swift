//
//  RestAPIClient.swift
//  Construct Messenger
//
//  Created on 26.12.2025.
//

import Foundation

/// REST API client for authentication and account management
/// Implements the new REST API endpoints from Phase 2.5 migration
class RestAPIClient {
    static let shared = RestAPIClient()

    private let session: URLSession
    private let longPollingSession: URLSession
    private var baseURL: String {
        APIConstants.activeServerURL
    }

    // Track which server URL is currently working
    private var workingServerURL: String?

    // Reference to connection status manager
    private let connectionStatusManager = ConnectionStatusManager.shared

    private init() {
        // Regular session for standard requests
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConstants.connectionTimeout
        config.timeoutIntervalForResource = APIConstants.connectionTimeout * 2
        self.session = URLSession(configuration: config)
        
        // Separate session for long polling with increased timeouts
        let longPollingConfig = URLSessionConfiguration.default
        longPollingConfig.timeoutIntervalForRequest = APIConstants.longPollingTimeout
        longPollingConfig.timeoutIntervalForResource = APIConstants.longPollingResourceTimeout
        self.longPollingSession = URLSession(configuration: longPollingConfig)
    }
    
    // Get list of server URLs to try (with fallback)
    private func getServerURLsToTry() -> [String] {
        // If we have a working URL, try it first
        if let working = workingServerURL {
            var urls = [working]
            // Add other URLs as fallbacks
            for url in ServerConfig.serverURLs where url != working {
                urls.append(url)
            }
            return urls
        }
        // Otherwise try all URLs in order
        return ServerConfig.serverURLs
    }
    
    // MARK: - Authentication Endpoints
    
    /// Register a new user
    /// POST /api/v1/auth/register
    func register(username: String, password: String, publicKey: UploadableKeyBundle) async throws -> RegisterSuccessData {
        let endpoint = "/api/v1/auth/register"
        
        // Server expects camelCase format
        let requestBody: [String: Any] = [
            "username": username,
            "password": password,
            "keyBundle": [
                "masterIdentityKey": publicKey.masterIdentityKey,
                "bundleData": publicKey.bundleData,
                "signature": publicKey.signature
            ]
        ]
        
        let response: AuthResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )
        
        // Convert to client format
        return RegisterSuccessData(
            userId: response.userId,
            username: username,
            sessionToken: response.accessToken,
            expires: response.expiresAt
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
        
        let response: AuthResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )
        
        // ✅ DEBUG: Log response details
        Log.info("📥 Login response received:", category: "Network")
        Log.info("   userId: \(response.userId)", category: "Network")
        Log.info("   accessToken length: \(response.accessToken.count)", category: "Network")
        Log.info("   expiresAt: \(response.expiresAt) (raw value)", category: "Network")
        
        // Check if expiresAt is in seconds or milliseconds
        let expiresDate: Date
        if response.expiresAt > 1_000_000_000_000 {
            // Milliseconds
            expiresDate = Date(timeIntervalSince1970: TimeInterval(response.expiresAt) / 1000.0)
            Log.info("   Interpreting as milliseconds", category: "Network")
        } else {
            // Seconds
            expiresDate = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
            Log.info("   Interpreting as seconds", category: "Network")
        }
        Log.info("   Expires at: \(expiresDate)", category: "Network")
        Log.info("   Expires in: \(Int(expiresDate.timeIntervalSinceNow / 60)) minutes", category: "Network")
        
        // Convert to client format
        return LoginSuccessData(
            userId: response.userId,
            username: username,
            sessionToken: response.accessToken,
            expires: response.expiresAt
        )
    }
    
    /// Logout current session
    /// POST /api/v1/auth/logout
    func logout(sessionToken: String) async throws {
        let endpoint = "/api/v1/auth/logout"
        let requestBody: [String: Any] = [
            "all_devices": false
        ]
        
        let _: EmptyResponse = try await performRequest(
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
        
        let _: EmptyResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }
    
    // MARK: - Messaging Endpoints
    
    /// Send a message
    /// POST /api/v1/messages
    func sendMessage(
        recipientId: String,
        ephemeralPublicKey: Data,
        messageNumber: UInt32,
        content: String,
        timestamp: UInt64,
        suiteId: UInt16
    ) async throws -> SendMessageResponse {
        let endpoint = "/api/v1/messages"

        // Build flat request body (server uses serde rename_all = "camelCase")
        // Server expects: recipientId, suiteId, ephemeralPublicKey (base64), messageNumber, previousChainLength, ciphertext
        let requestBody: [String: Any] = [
            "recipientId": recipientId,
            "suiteId": suiteId,
            "ephemeralPublicKey": ephemeralPublicKey.base64EncodedString(),
            "messageNumber": messageNumber,
            "previousChainLength": 0,  // TODO: Get from Double Ratchet state if needed
            "ciphertext": content  // content from EncryptedMessageComponents is already Base64(nonce || ciphertext_with_tag)
        ]

        Log.debug("📤 Sending message to \(recipientId), suiteId: \(suiteId), msgNum: \(messageNumber)", category: "Network")

        let response: SendMessageResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )

        return response
    }
    
    /// Poll for new messages (long polling)
    /// GET /api/v1/messages?since=<id>&timeout=30
    func pollMessages(sinceId: String? = nil, timeout: Int = 30) async throws -> PollMessagesResponse {
        var endpoint = "/api/v1/messages"
        
        // ✅ DEBUG: Log polling parameters
        if let sinceId = sinceId {
            Log.info("📡 Polling messages with since=\(sinceId)", category: "Network")
        } else {
            Log.info("📡 Polling messages without since parameter (first request)", category: "Network")
        }
        
        // Build query parameters with proper URL encoding
        var queryItems: [URLQueryItem] = []
        if let sinceId = sinceId {
            queryItems.append(URLQueryItem(name: "since", value: sinceId))
        }
        queryItems.append(URLQueryItem(name: "timeout", value: String(timeout)))
        
        if !queryItems.isEmpty {
            var components = URLComponents(string: endpoint)
            components?.queryItems = queryItems
            if let queryString = components?.url?.query {
                endpoint += "?" + queryString
            }
        }
        
        Log.info("📡 Final endpoint: \(endpoint)", category: "Network")
        
        // Use longer timeout for long polling
        let response: PollMessagesResponse = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil,
            requiresAuth: true,
            timeout: TimeInterval(timeout + 5),
            isLongPolling: true
        )
        
        // ✅ DEBUG: Log response details
        Log.info("📥 Received \(response.messages.count) messages", category: "Network")
        if let nextSince = response.nextSince {
            Log.info("   nextSince: \(nextSince)", category: "Network")
        } else {
            Log.info("   nextSince: nil", category: "Network")
        }
        Log.info("   hasMore: \(response.hasMore ?? false)", category: "Network")
        
        return response
    }
    
    // MARK: - Key Management Endpoints
    
    /// Get public key bundle for a user
    /// GET /api/v1/users/:id/public-key
    /// Returns: Array with [KeyBundleObject, username]
    func getPublicKey(userId: String) async throws -> PublicKeyBundleData {
        let endpoint = "/api/v1/users/\(userId)/public-key"

        // API returns an array: [{bundleData, masterIdentityKey, signature}, "username"]
        let response: PublicKeyBundleArrayResponse = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil,
            requiresAuth: true
        )

        // Parse the bundleData (base64 encoded JSON)
        guard let bundleDataString = response.keyBundle.bundleData,
              let bundleDataDecoded = Data(base64Encoded: bundleDataString) else {
            Log.error("❌ Failed to decode bundleData from base64", category: "Network")
            throw NetworkError.decodingFailed
        }

        let bundleContent: KeyBundleContent
        do {
            bundleContent = try JSONDecoder().decode(KeyBundleContent.self, from: bundleDataDecoded)
        } catch {
            Log.error("❌ Failed to parse bundleData JSON: \(error)", category: "Network")
            throw NetworkError.decodingFailed
        }

        // Get the first suite (we use suiteId: 1)
        guard let firstSuite = bundleContent.supportedSuites.first else {
            Log.error("❌ No supported suites in key bundle", category: "Network")
            throw NetworkError.decodingFailed
        }

        // Convert server response to client format
        return PublicKeyBundleData(
            userId: bundleContent.userId,
            username: response.username,
            identityPublic: firstSuite.identityKey,
            signedPrekeyPublic: firstSuite.signedPrekey,
            signature: firstSuite.signedPrekeySignature,
            verifyingKey: response.keyBundle.masterIdentityKey,
            suiteId: UInt16(firstSuite.suiteId)
        )
    }
    
    /// Rotate prekeys
    /// POST /api/v1/keys/rotate
    func rotatePrekeys(keyBundle: UploadableKeyBundle) async throws {
        let endpoint = "/api/v1/keys/rotate"
        
        let requestBody: [String: Any] = [
            "key_bundle": [
                "master_identity_key": keyBundle.masterIdentityKey,
                "bundle_data": keyBundle.bundleData,
                "signature": keyBundle.signature
            ]
        ]
        
        let _: EmptyResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }
    
    // MARK: - Media Endpoints
    
    /// Request upload token for media
    /// POST /api/v1/media/token
    func requestMediaToken() async throws -> MediaTokenData {
        let endpoint = "/api/v1/media/token"
        
        let response: MediaTokenResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: nil,
            requiresAuth: true
        )
        
        // Convert server response to client format
        return MediaTokenData(
            requestId: response.requestId ?? UUID().uuidString,
            uploadToken: response.uploadToken,
            uploadUrl: response.uploadUrl,
            maxFileSize: response.maxFileSize,
            expiresAt: response.expiresAt
        )
    }
    
    // MARK: - Push Notifications Endpoints
    
    /// Register device token for push notifications
    /// POST /api/v1/notifications/register-device
    func registerDeviceToken(token: String) async throws -> DeviceTokenResponse {
        let endpoint = "/api/v1/notifications/register-device"
        
        let body: [String: Any] = [
            "deviceToken": token,
            "platform": "ios"
        ]
        
        let response: DeviceTokenResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: body,
            requiresAuth: true
        )
        
        return response
    }
    
    /// Unregister device token
    /// POST /api/v1/notifications/unregister-device
    func unregisterDeviceToken(token: String) async throws {
        let endpoint = "/api/v1/notifications/unregister-device"
        
        let body: [String: Any] = [
            "deviceToken": token
        ]
        
        // Response is empty on success, so use EmptyResponse
        let _: EmptyResponse = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }
    
    // MARK: - Generic Request Handler

    private func performRequest<T: Codable>(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        requiresAuth: Bool = false,
        timeout: TimeInterval? = nil,
        isLongPolling: Bool = false
    ) async throws -> T {
        let serverURLs = getServerURLsToTry()
        var lastError: Error?
        
        // Try each server URL until one works
        for (index, serverURL) in serverURLs.enumerated() {
            let fullURL = serverURL + endpoint
            Log.info("🌐 REST API \(method) \(endpoint) (attempt \(index + 1)/\(serverURLs.count))", category: "Network")
            Log.info("   Server URL: \(serverURL)", category: "Network")
            Log.info("   Full URL: \(fullURL)", category: "Network")
            
            guard let url = URL(string: fullURL) else {
                Log.error("❌ Invalid URL: \(fullURL)", category: "Network")
                lastError = NetworkError.connectionFailed
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = method
            
            // Set timeout if provided (for long polling)
            if let timeout = timeout {
                request.timeoutInterval = timeout
            }
            
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            
            // Set Host header explicitly to help with DNS resolution
            if let host = url.host {
                request.setValue(host, forHTTPHeaderField: "Host")
                Log.info("📋 Host header: \(host)", category: "Network")
            }
            
            // Add authentication header if required
            if requiresAuth {
                if let token = SessionManager.shared.sessionToken {
                    // ✅ FIX: Trim any whitespace that might have been added
                    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // ✅ DEBUG: Check if token was modified
                    if trimmedToken != token {
                        Log.info("⚠️ Token had whitespace, trimmed (original: \(token.count), trimmed: \(trimmedToken.count))", category: "Network")
                    }
                    
                    // ✅ DEBUG: Log full token for debugging (first and last 20 chars)
                    let tokenPreview = if trimmedToken.count > 40 {
                        "\(trimmedToken.prefix(20))...\(trimmedToken.suffix(20))"
                    } else {
                        trimmedToken
                    }
                    Log.info("🔐 Token preview: \(tokenPreview)", category: "Network")
                    Log.info("   Token length: \(trimmedToken.count) characters", category: "Network")
                    
                    let authHeader = "Bearer \(trimmedToken)"
                    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
                    Log.info("🔐 Added Authorization header (full length: \(authHeader.count))", category: "Network")
                    
                    // Log token expiration status
                    if let expires = SessionManager.shared.sessionExpires {
                        let timeUntilExpiry = expires.timeIntervalSinceNow
                        if timeUntilExpiry > 0 {
                            Log.info("   Token expires in: \(Int(timeUntilExpiry / 60)) minutes", category: "Network")
                        } else {
                            Log.info("⚠️ Token has already expired! (expired \(Int(-timeUntilExpiry / 60)) minutes ago)", category: "Network")
                        }
                    } else {
                        Log.info("⚠️ No expiration info for token", category: "Network")
                    }
                } else {
                    Log.error("❌ No session token available for authenticated request", category: "Network")
                    throw NetworkError.notConnected
                }
            }
            
            // Add request body if provided
            if let body = body {
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                } catch {
                    throw NetworkError.encodingFailed
                }
            }
            
            do {
                // Use appropriate session based on request type
                let activeSession = isLongPolling ? longPollingSession : session
                let (data, response) = try await activeSession.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = NetworkError.connectionFailed
                    continue
                }
                
                Log.info("📡 Response status: \(httpResponse.statusCode) from \(serverURL)", category: "Network")
                
                // Handle error responses
                if httpResponse.statusCode >= 400 {
                    let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                    let errorMessage = errorResponse?.message ?? errorResponse?.error ?? "Server error (status: \(httpResponse.statusCode))"
                    let responseBody = String(data: data, encoding: .utf8)
                    
                    // ✅ FIXED: Handle 401 Unauthorized - token expired or invalid
                    // Don't try fallback servers for 401 - it's an authentication issue, not connectivity
                    if httpResponse.statusCode == 401 {
                        Log.error("❌ Authentication failed (401): \(errorMessage)", category: "Network")
                        
                        // Only clear session if token is actually expired (not just a server error)
                        // Check if token expiration time has passed
                        let shouldClearSession: Bool
                        if let expires = SessionManager.shared.sessionExpires {
                            // Token is expired if current time is past expiration
                            shouldClearSession = Date() >= expires
                            if shouldClearSession {
                                Log.info("⚠️ Token has expired (expired at: \(expires))", category: "Network")
                            } else {
                                Log.info("⚠️ Got 401 but token is not expired yet. May be a server issue.", category: "Network")
                            }
                        } else {
                            // No expiration info - assume token is invalid
                            shouldClearSession = true
                            Log.info("⚠️ Got 401 and no expiration info available", category: "Network")
                        }
                        
                        if shouldClearSession {
                            // Clear session and notify that user needs to re-login
                            // Do this on main thread to avoid race conditions
                            DispatchQueue.main.async {
                                SessionManager.shared.clearSession()
                                NotificationCenter.default.post(name: NSNotification.Name("SessionExpired"), object: nil)
                            }
                            throw NetworkError.serverError(message: "Session expired. Please login again.", responseBody: responseBody)
                        } else {
                            // Token not expired but got 401 - may be server issue
                            // Don't clear session, just throw error
                            throw NetworkError.serverError(message: "Authentication failed: \(errorMessage)", responseBody: responseBody)
                        }
                    }
                    
                    // For other 4xx errors, don't try fallback (it's a client/server error, not connectivity)
                    if httpResponse.statusCode < 500 {
                        throw NetworkError.serverError(message: errorMessage, responseBody: responseBody)
                    }
                    
                    // For 5xx errors, try next server
                    lastError = NetworkError.serverError(message: errorMessage, responseBody: responseBody)
                    continue
                }
                
                // Success! Remember this working server URL
                workingServerURL = serverURL
                Log.info("✅ Successfully connected to: \(serverURL)", category: "Network")

                // Update connection status
                connectionStatusManager.markRequestSucceeded()
                
                // Decode successful response
                do {
                    let decoder = JSONDecoder()
                    // Handle empty response
                    if data.isEmpty {
                        // Try to decode as EmptyResponse for void endpoints
                        if T.self == EmptyResponse.self {
                            return EmptyResponse() as! T
                        }
                    }
                    return try decoder.decode(T.self, from: data)
                } catch {
                    Log.error("❌ Failed to decode response: \(error)", category: "Network")
                    if let responseString = String(data: data, encoding: .utf8) {
                        Log.error("   Response body: \(responseString)", category: "Network")
                    }
                    throw NetworkError.decodingFailed
                }
            } catch let error as NetworkError {
                // Don't retry on certain errors (decoding, encoding, auth)
                if case .decodingFailed = error {
                    throw error
                }
                if case .encodingFailed = error {
                    throw error
                }
                if case .notConnected = error {
                    throw error
                }
                lastError = error
                continue
            } catch let urlError as URLError {
                Log.error("❌ URL Error for \(serverURL): \(urlError.localizedDescription)", category: "Network")
                Log.error("   Code: \(urlError.code.rawValue)", category: "Network")
                
                // ✅ SPECIAL CASE: Long-polling timeout is NORMAL, not an error
                // Long-polling requests are expected to timeout if no new messages arrive
                // Don't treat this as a failure that requires trying other servers
                if isLongPolling && urlError.code == .timedOut {
                    Log.debug("⏱️ Long-polling timeout (normal behavior) - no new messages", category: "Network")
                    // Mark as successful connection (timeout = server is responding, just no messages)
                    connectionStatusManager.markRequestSucceeded()
                    // Return empty response
                    if T.self == PollMessagesResponse.self {
                        return PollMessagesResponse(messages: [], nextSince: nil, hasMore: false) as! T
                    }
                    // For other types, still throw but don't mark as failed connection
                    throw urlError
                }
                
                // Check if this is a connectivity error that might be fixed by trying another server
                switch urlError.code {
                case .cannotFindHost, .cannotConnectToHost, .timedOut:
                    // Try next server
                    lastError = urlError
                    if index < serverURLs.count - 1 {
                        Log.info("🔄 Trying fallback server...", category: "Network")
                        continue
                    }
                    // Last server failed, provide detailed error
                    let message = "Cannot connect to any server. Tried:\n\(serverURLs.map { "- \($0)" }.joined(separator: "\n"))\n\nError: \(urlError.localizedDescription)"
                    throw NetworkError.serverError(message: message, responseBody: nil)
                case .notConnectedToInternet:
                    throw NetworkError.serverError(message: "No internet connection available.", responseBody: nil)
                default:
                    lastError = urlError
                    if index < serverURLs.count - 1 {
                        continue
                    }
                    throw NetworkError.serverError(message: "Network error: \(urlError.localizedDescription)", responseBody: nil)
                }
            } catch {
                Log.error("❌ Network request failed: \(error.localizedDescription)", category: "Network")
                lastError = error
                if index < serverURLs.count - 1 {
                    continue
                }
                throw NetworkError.connectionFailed
            }
        }
        
        // All servers failed - update connection status
        // Mark as critical failure since ALL servers failed to respond
        connectionStatusManager.markRequestFailed(error: "Failed to connect to server", isCritical: true)

        if let lastError = lastError {
            throw lastError
        }
        throw NetworkError.connectionFailed
    }
}

// MARK: - Response Types

/// Server response format for auth endpoints
/// Note: Server returns camelCase, not snake_case
struct AuthResponse: Codable {
    let userId: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64
}

/// Empty response for endpoints that return no data
struct EmptyResponse: Codable {
    init() {}
}

/// Error response from server
struct ErrorResponse: Codable {
    let code: String?
    let error: String?
    let message: String?
}

// MARK: - Messaging Response Types

/// Response from sending a message
struct SendMessageResponse: Codable {
    let messageId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case status
    }
}

/// Response from polling messages
struct PollMessagesResponse: Codable {
    let messages: [ChatMessageResponse]
    let nextSince: String?
    let hasMore: Bool?
    
    enum CodingKeys: String, CodingKey {
        case messages
        case nextSince = "next_since"
        case hasMore = "has_more"
    }
    
    /// Convert to array of ChatMessage
    func toChatMessages() throws -> [ChatMessage] {
        try messages.map { try $0.toChatMessage() }
    }
}

/// Chat message in REST API response format
struct ChatMessageResponse: Codable {
    let id: String
    let from: String  // ✅ SPEC: "from" in JSON
    let to: String  // ✅ SPEC: "to" in JSON
    let ephemeralPublicKey: String?  // ✅ Server sends "ephemeralPublicKey" (camelCase)
    let messageNumber: UInt32?  // ✅ Server sends "messageNumber" (camelCase)
    let content: String  // Base64 encrypted content
    let suiteId: UInt16  // ✅ Server sends "suiteId" (camelCase)
    let timestamp: UInt64
    
    // ✅ No CodingKeys needed - Swift automatically converts camelCase ↔ camelCase
    
    /// Convert to ChatMessage format (with binary ephemeralPublicKey)
    func toChatMessage() throws -> ChatMessage {
        // Parse ephemeral key if present
        let ephemeralKeyData: Data
        if let ephemeralKeyString = ephemeralPublicKey, !ephemeralKeyString.isEmpty {
            guard let keyData = Data(base64Encoded: ephemeralKeyString) else {
                Log.error("❌ Failed to decode ephemeralPublicKey from base64", category: "Network")
                throw NetworkError.decodingFailed
            }
            ephemeralKeyData = keyData
        } else {
            // Use empty data if not present (for compatibility)
            ephemeralKeyData = Data()
            Log.debug("ℹ️ Message has no ephemeralPublicKey, using empty data", category: "Network")
        }
        
        return ChatMessage(
            id: id,
            from: from,
            to: to,
            ephemeralPublicKey: ephemeralKeyData,
            messageNumber: messageNumber ?? 0,
            content: content,
            suiteId: suiteId,
            timestamp: timestamp
        )
    }
}

// MARK: - Key Management Response Types

/// Response from getting public key - API returns array: [KeyBundle, username]
struct PublicKeyBundleArrayResponse: Codable {
    let keyBundle: KeyBundleObject
    let username: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.keyBundle = try container.decode(KeyBundleObject.self)
        self.username = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(keyBundle)
        try container.encode(username)
    }
}

/// Key bundle object from API response
struct KeyBundleObject: Codable {
    let bundleData: String?
    let masterIdentityKey: String
    let signature: String
}

/// Decoded content from bundleData (base64 decoded JSON)
struct KeyBundleContent: Codable {
    let userId: String
    let timestamp: String
    let supportedSuites: [KeyBundleSuite]
}

/// Suite data inside bundleData
struct KeyBundleSuite: Codable {
    let suiteId: Int
    let identityKey: String
    let signedPrekey: String
    let signedPrekeySignature: String
}

// MARK: - Media Response Types

/// Response from requesting media token
struct MediaTokenResponse: Codable {
    let requestId: String?
    let uploadToken: String
    let uploadUrl: String
    let maxFileSize: Int
    let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case uploadToken = "upload_token"
        case uploadUrl = "upload_url"
        case maxFileSize = "max_file_size"
        case expiresAt = "expires_at"
    }
}

// MARK: - Push Notifications Response Types

/// Response from device token registration
struct DeviceTokenResponse: Codable {
    let success: Bool
    let message: String?
}

