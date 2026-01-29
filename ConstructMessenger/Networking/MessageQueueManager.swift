//
//  MessageQueueManager.swift
//  Construct Messenger
//
//  Manages message queue for offline/online scenarios
//

import Foundation
import CoreData
import Combine
import os.log

/// Manages message queue and automatic retry logic for offline scenarios
class MessageQueueManager: ObservableObject {
    static let shared = MessageQueueManager()
    
    private let networkManager = NetworkReachabilityManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?
    
    // Track messages being sent to detect timeouts
    private var pendingSends: [String: Date] = [:] // messageId -> sendTimestamp
    private let pendingSendsQueue = DispatchQueue(label: "MessageQueueManager.pendingSends")
    
    private init() {
        // Skip setup in preview mode
        if !PreviewDetector.isRunningInPreview {
            setupSubscribers()
            startPeriodicCheck()
            Log.info("📦 MessageQueueManager initialized", category: "MessageQueue")
        }
    }
    
    deinit {
        stopPeriodicCheck()
    }
    
    // MARK: - Setup
    
    private func setupSubscribers() {
        // Monitor network reachability (REST API doesn't require WebSocket)
        networkManager.reachabilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReachable in
                if isReachable {
                    Log.info("📡 Network available - checking for queued messages", category: "MessageQueue")
                    self?.processQueuedMessages()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Message Tracking
    
    /// Mark a message as being sent (for timeout detection)
    func markMessageAsSending(_ messageId: String) {
        pendingSendsQueue.async { [weak self] in
            self?.pendingSends[messageId] = Date()
        }
    }
    
    /// Mark a message as successfully sent (remove from pending)
    func markMessageAsSent(_ messageId: String) {
        pendingSendsQueue.async { [weak self] in
            self?.pendingSends.removeValue(forKey: messageId)
        }
    }
    
    /// Mark a message as failed (remove from pending)
    func markMessageAsFailed(_ messageId: String) {
        pendingSendsQueue.async { [weak self] in
            self?.pendingSends.removeValue(forKey: messageId)
        }
    }
    
    // MARK: - Periodic Check
    
    private func startPeriodicCheck() {
        // Check every 5 seconds for stuck messages
        checkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkForStuckMessages()
        }
        Log.info("⏰ Started periodic message queue check", category: "MessageQueue")
    }
    
    private func stopPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// Check for messages that have been stuck in sending state too long
    private func checkForStuckMessages() {
        // Safety check: ensure Core Data is available
        let context = PersistenceController.shared.container.viewContext
        guard context.persistentStoreCoordinator != nil else {
            Log.info("⚠️ Core Data store coordinator unavailable, skipping stuck message check", category: "MessageQueue")
            return
        }
        
        let timeout = APIConstants.messageSendTimeout
        
        // Check pending sends for timeouts
        pendingSendsQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let timedOutIds = self.pendingSends.compactMap { (messageId, timestamp) -> String? in
                if now.timeIntervalSince(timestamp) > timeout {
                    return messageId
                }
                return nil
            }
            
            if !timedOutIds.isEmpty {
                DispatchQueue.main.async {
                    self.handleTimedOutMessages(timedOutIds, context: context)
                }
            }
        }
        
        // Check Core Data for messages stuck in .sending state
        context.perform {
            let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deliveryStatusRaw == %d", DeliveryStatus.sending.rawValue)
            
            if let stuckMessages = try? context.fetch(fetchRequest) {
                let now = Date()
                for message in stuckMessages {
                    // If message has been in sending state for more than timeout, mark as queued
                    let timeSinceSent = now.timeIntervalSince(message.timestamp)
                    if timeSinceSent > timeout {
                        Log.info("⏱️ Message \(message.id) stuck in sending state for \(Int(timeSinceSent))s, marking as queued", category: "MessageQueue")
                        message.deliveryStatus = .queued
                        // Remove from pending sends if present
                        self.markMessageAsFailed(message.id)
                        try? context.save()
                    }
                }
            }
            
            // ✅ FIX: Auto-mark old .sent messages as .delivered to clean up queue
            // Messages in .sent state for > 1 hour are definitely delivered (server confirmed receipt)
            let sentFetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            sentFetchRequest.predicate = NSPredicate(format: "deliveryStatusRaw == %d", DeliveryStatus.sent.rawValue)
            
            if let sentMessages = try? context.fetch(sentFetchRequest) {
                let now = Date()
                let autoDeliverThreshold: TimeInterval = 3600 // 1 hour
                
                for message in sentMessages {
                    let timeSinceSent = now.timeIntervalSince(message.timestamp)
                    
                    // Auto-mark as delivered after 1 hour
                    if timeSinceSent > autoDeliverThreshold {
                        Log.info("✅ Auto-marking message \(message.id) as delivered (sent \(Int(timeSinceSent/60)) minutes ago)", category: "MessageQueue")
                        message.deliveryStatus = .delivered
                        try? context.save()
                    }
                }
            }
        }
    }
    
    private func handleTimedOutMessages(_ messageIds: [String], context: NSManagedObjectContext) {
        context.perform {
            for messageId in messageIds {
                let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)
                
                if let message = try? context.fetch(fetchRequest).first {
                    if message.deliveryStatus == .sending {
                        Log.info("⏱️ Message \(messageId) timed out, marking as queued", category: "MessageQueue")
                        message.deliveryStatus = .queued
                        self.markMessageAsFailed(messageId)
                    }
                }
            }
            
            try? context.save()
            
            // Try to resend if network is available (REST API doesn't require WebSocket)
            if self.networkManager.isReachable {
                self.processQueuedMessages()
            }
        }
    }
    
    // MARK: - Process Queued Messages
    
    /// Process all queued messages (called when network is restored)
    func processQueuedMessages() {
        guard networkManager.isReachable else {
            Log.debug("⏸️ Cannot process queued messages - network not reachable", category: "MessageQueue")
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        guard context.persistentStoreCoordinator != nil else {
            Log.info("⚠️ Core Data store coordinator unavailable, cannot process queued messages", category: "MessageQueue")
            return
        }
        
        context.perform {
            let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deliveryStatusRaw == %d", DeliveryStatus.queued.rawValue)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            fetchRequest.fetchLimit = 10 // Process in batches
            
            guard let queuedMessages = try? context.fetch(fetchRequest), !queuedMessages.isEmpty else {
                return
            }
            
            Log.info("📤 Processing \(queuedMessages.count) queued messages", category: "MessageQueue")
            
            // Post notification for ViewModels to handle resending
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .processQueuedMessages,
                    object: nil,
                    userInfo: ["messageIds": queuedMessages.map { $0.id }]
                )
            }
        }
    }
    
    /// Get count of queued messages
    func getQueuedMessageCount() -> Int {
        let context = PersistenceController.shared.container.viewContext
        guard context.persistentStoreCoordinator != nil else {
            return 0
        }
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deliveryStatusRaw == %d", DeliveryStatus.queued.rawValue)
        
        return (try? context.count(for: fetchRequest)) ?? 0
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let processQueuedMessages = Notification.Name("processQueuedMessages")
}
