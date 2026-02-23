//
//  MessagingAPI.swift
//  Construct Messenger
//
//  Messaging API endpoints
//  Created on 26.01.2026 (Phase 2.1 refactoring)
//

import Foundation
import UIKit

/// Messaging endpoints for sending and receiving messages
class MessagingAPI {
    static let shared = MessagingAPI()
    
    private let client = RestAPIClient.shared
    private let sendThrottler = MessageSendThrottler()
    
    private init() {}
    
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
        await sendThrottler.waitForTurn(minIntervalMs: TrafficProtectionConfig.minSendIntervalMs)
        let endpoint = "/api/v1/messages"

        let requestBody: [String: Any] = [
            "recipientId": recipientId,
            "suiteId": suiteId,
            "ephemeralPublicKey": ephemeralPublicKey.base64EncodedString(),
            "messageNumber": messageNumber,
            "previousChainLength": 0,
            "ciphertext": content
        ]

        Log.debug("📤 Sending message to \(recipientId), suiteId: \(suiteId), msgNum: \(messageNumber)", category: "Network")
        
        #if DEBUG
        Log.debug("📤 OUTGOING message details:", category: "Network")
        Log.debug("   ephemeralPublicKey: \(ephemeralPublicKey.count) bytes", category: "Network")
        let ephemeralPreview = ephemeralPublicKey.prefix(16).map { String(format: "%02x", $0) }.joined()
        Log.debug("   ephemeralPublicKey preview: \(ephemeralPreview)...", category: "Network")
        Log.debug("   messageNumber: \(messageNumber)", category: "Network")
        Log.debug("   ciphertext length: \(content.count) chars", category: "Network")
        Log.debug("   ciphertext preview: \(content.prefix(32))...", category: "Network")
        #endif

        let response: SendMessageResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true,
            timeout: APIConstants.messageSendNetworkTimeout,  // Increased timeout for message sending
            maxRetries: APIConstants.maxRetryAttempts  // Auto-retry on transient failures
        )

        return response
    }
    
    /// Poll for new messages (long polling)
    /// GET /api/v1/messages?since=<id>&timeout=30
    func pollMessages(sinceId: String? = nil, timeout: Int = 30) async throws -> PollMessagesResponse {
        var endpoint = "/api/v1/messages"
        
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
        
        let response: PollMessagesResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil,
            requiresAuth: true,
            timeout: TimeInterval(timeout + 5),
            isLongPolling: true
        )
        
        // Only log if there are messages or errors
        if !response.messages.isEmpty {
            Log.info("📥 Received \(response.messages.count) messages", category: "Network")
        }
        
        // Validate nextSince format
        if let nextSince = response.nextSince {
            Log.info("   nextSince: \(nextSince)", category: "Network")
            
            // Validate Redis Stream ID format: "timestamp-sequence" (exactly 2 numeric components)
            let components = nextSince.split(separator: "-")
            let isValid = components.count == 2 && 
                          components[0].allSatisfy { $0.isNumber } &&
                          components[1].allSatisfy { $0.isNumber }
            
            if !isValid {
                Log.error("   ⚠️ nextSince has invalid format (expected timestamp-seq, got \(components.count) components)", category: "Network")
                Log.error("   This looks like UUID! Server should return Redis Stream ID", category: "Network")
            }
        } else {
            Log.info("   nextSince: nil", category: "Network")
            
            // Critical error if we have messages but no nextSince
            if !response.messages.isEmpty {
                Log.error("   ❌ CRITICAL: Messages returned but nextSince is nil!", category: "Network")
            }
        }
        
        Log.info("   hasMore: \(response.hasMore ?? false)", category: "Network")
        
        return response
    }
    
    /// Send END_SESSION control message
    /// POST /api/v1/control
    func sendEndSession(to recipientId: String, reason: String? = nil) async throws -> EndSessionResponse {
        let endpoint = "/api/v1/control"
        
        var requestBody: [String: Any] = [
            "recipientId": recipientId
        ]
        
        if let reason = reason {
            requestBody["reason"] = reason
        }
        
        Log.info("📤 Sending END_SESSION to \(recipientId), reason: \(reason ?? "none")", category: "Network")
        
        let response: EndSessionResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
        
        Log.info("✅ END_SESSION sent successfully, messageId: \(response.messageId)", category: "Network")
        
        return response
    }
}

// MARK: - Send Throttling
private actor MessageSendThrottler {
    private var lastSendNs: UInt64?

    func waitForTurn(minIntervalMs: UInt64) async {
        // Access UIDevice on MainActor (required for Swift 6 concurrency)
        let batteryLevel = await MainActor.run {
            if !UIDevice.current.isBatteryMonitoringEnabled {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            return UIDevice.current.batteryLevel
        }
        
        let adjustedMinIntervalMs: UInt64
        if batteryLevel >= 0, batteryLevel < TrafficProtectionConfig.batteryLevelThreshold {
            adjustedMinIntervalMs = UInt64(Double(minIntervalMs) * TrafficProtectionConfig.lowBatterySendIntervalMultiplier)
        } else {
            adjustedMinIntervalMs = minIntervalMs
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastSendNs {
            let minNs = adjustedMinIntervalMs * 1_000_000
            let earliest = last + minNs
            if now < earliest {
                try? await Task.sleep(nanoseconds: earliest - now)
            }
        }
        lastSendNs = DispatchTime.now().uptimeNanoseconds

        let jitterMs = UInt64.random(in: TrafficProtectionConfig.sendJitterMinMs...TrafficProtectionConfig.sendJitterMaxMs)
        if jitterMs > 0 {
            try? await Task.sleep(nanoseconds: jitterMs * 1_000_000)
        }
    }
}
