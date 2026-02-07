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

        let response: SendMessageResponse = try await client.performRequest(
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
        
        let response: PollMessagesResponse = try await client.performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil,
            requiresAuth: true,
            timeout: TimeInterval(timeout + 5),
            isLongPolling: true
        )
        
        Log.info("📥 Received \(response.messages.count) messages", category: "Network")
        if let nextSince = response.nextSince {
            Log.info("   nextSince: \(nextSince)", category: "Network")
        } else {
            Log.info("   nextSince: nil", category: "Network")
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
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let batteryLevel = UIDevice.current.batteryLevel
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
