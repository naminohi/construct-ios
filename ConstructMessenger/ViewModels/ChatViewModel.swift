import Foundation
import Combine
import CoreData
import UIKit
import os.log

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var isLoadingMore = false
    @Published var hasMoreMessages = true

    // ✅ FIXED: Track session initialization state
    @Published var isSessionReady = false

    // ✅ FIXED: Queue for pending messages before session is ready
    private var pendingMessages: [(text: String, timestamp: Date)] = []
    
    // ✅ NEW: Track public key fetch timeout
    private var publicKeyFetchTimer: Timer?
    private let publicKeyFetchTimeout: TimeInterval = 10.0 // 10 seconds timeout
    
    // ✅ NEW: Pagination support
    private let initialMessageLimit = 50
    private var oldestLoadedTimestamp: Date?
    private var allLoadedMessageIds: Set<String> = []

    let chat: Chat
    private var recipientBundle: (identityPublic: String, signedPrekeyPublic: String, signature: String, verifyingKey: String)?

    private let connectionStatusManager = ConnectionStatusManager.shared
    private let messageQueueManager = MessageQueueManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var viewContext: NSManagedObjectContext

    // ✅ FIX: Use NSFetchedResultsController for automatic Core Data updates
    private var fetchedResultsController: NSFetchedResultsController<Message>?

    init(chat: Chat, context: NSManagedObjectContext) {
        self.chat = chat
        self.viewContext = context
        Log.debug("🔧 ChatViewModel init: chat.id=\(chat.id), chat.otherUser?.id=\(chat.otherUser?.id ?? "nil"), chat.otherUser?.username=\(chat.otherUser?.username ?? "nil")", category: "ChatViewModel")

        setupFetchedResultsController()  // ✅ Setup FRC first
        setupSubscribers()
        checkExistingSession()  // ✅ FIXED: Check if session already exists
        fetchRecipientPublicKey()

        // Load messages immediately since we have context
        Log.debug("🔧 ChatViewModel initialized with viewContext", category: "ChatViewModel")
        loadMessages()
        
        // Listen for queued messages processing
        setupMessageQueueListener()
    }

    deinit {
        // ✅ FIX: Clean up subscriptions when ViewModel is destroyed
        cancellables.removeAll()
        Log.debug("🔧 ChatViewModel deinitialized", category: "ChatViewModel")
    }

    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        // Observe changes using Combine
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadMessages()
            }
            .store(in: &cancellables)
    }

    private func setupSubscribers() {
        // ✅ Listen for connection status changes (REST API based)
        // Incoming messages are received via long polling in ChatsViewModel
        // and saved to Core Data, then picked up via NSManagedObjectContextObjectsDidChange
        connectionStatusManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .connected {
                    Log.info("✅ Network connected - processing queued messages", category: "ChatViewModel")
                    self?.sendQueuedMessages()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMessageQueueListener() {
        // Listen for queued messages processing requests
        NotificationCenter.default.publisher(for: .processQueuedMessages)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.sendQueuedMessages()
            }
            .store(in: &cancellables)
    }

    // ✅ FIXED: Check if we already have a session for this user
    private func checkExistingSession() {
        guard let userId = chat.otherUser?.id else { return }
        isSessionReady = CryptoManager.shared.hasSession(for: userId)
        if isSessionReady {
            Log.info("Session already exists for user: \(userId)", category: "ChatViewModel")
        }
    }

    private func fetchRecipientPublicKey() {
        guard let userId = chat.otherUser?.id else {
            Log.error("❌ Cannot fetch recipient public key: chat.otherUser?.id is nil", category: "ChatViewModel")
            return
        }
        guard let currentUserId = SessionManager.shared.currentUserId else {
            Log.error("❌ Cannot fetch recipient public key: currentUserId is nil", category: "ChatViewModel")
            return
        }
        Log.debug("🔑 Fetching public key for userId: \(userId), currentUserId: \(currentUserId)", category: "ChatViewModel")

        // 🚫 BLOCK: Cannot send encrypted messages to yourself
        if userId == currentUserId {
            errorMessage = "Cannot send encrypted messages to yourself. Use notes instead."
            Log.debug("Blocked attempt to initialize session with self", category: "ChatViewModel")
            return
        }

        // Don't fetch if session already exists
        if isSessionReady {
            return
        }

        // ✅ NEW: Cancel any existing timer
        publicKeyFetchTimer?.invalidate()
        
        // ✅ NEW: Set timeout timer
        publicKeyFetchTimer = Timer.scheduledTimer(withTimeInterval: publicKeyFetchTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isSessionReady {
                Log.error("⏱️ Timeout waiting for public key bundle from server", category: "ChatViewModel")
                self.errorMessage = "Failed to establish secure connection: server did not respond"
                self.isSessionReady = false
            }
        }

        // ✅ FIXED: Use REST API instead of WebSocket
        Task {
            do {
                let publicKeyBundle = try await RestAPIClient.shared.getPublicKey(userId: userId)
                
                await MainActor.run {
                    self.handlePublicKeyBundle(publicKeyBundle)
                }
            } catch {
                await MainActor.run {
                    Log.error("❌ Failed to fetch public key via REST: \(error.localizedDescription)", category: "ChatViewModel")
                    self.errorMessage = "Failed to fetch public key: \(error.localizedDescription)"
                    self.isSessionReady = false
                }
            }
        }
    }
    
    private func handlePublicKeyBundle(_ data: PublicKeyBundleData) {
        Log.debug("📦 Received publicKeyBundle for userId: \(data.userId), chat.otherUser?.id: \(chat.otherUser?.id ?? "nil"), match: \(data.userId == chat.otherUser?.id)", category: "ChatViewModel")
        if data.userId == chat.otherUser?.id {
            // ✅ Update username if we have the user in Core Data
            if let user = chat.otherUser {
                user.username = data.username
                user.displayName = data.username
                try? viewContext.save()
                Log.info("Updated username for user: \(data.username)", category: "ChatViewModel")
            }

            self.recipientBundle = (data.identityPublic, data.signedPrekeyPublic, data.signature, data.verifyingKey)
            guard SessionManager.shared.currentUserId != nil else { return }
            
            // ✅ FIX: Proactively delete any stale session before starting a new one.
            CryptoManager.shared.deleteSession(for: data.userId)
            Log.info("🗑️ Proactively deleted any existing session for \(data.userId) before initialization.", category: "ChatViewModel")

            // ✅ FIX: If we requested the keys, WE are the initiator
            Log.info("🔑 Received public key bundle - we requested it, so we are INITIATOR", category: "ChatViewModel")

            // ✅ Prevent self-session initialization
            guard let currentUserId = SessionManager.shared.currentUserId else {
                Log.error("❌ Cannot initialize session: currentUserId is nil", category: "ChatViewModel")
                errorMessage = "Cannot initialize session: user not authenticated"
                return
            }
            
            Log.debug("🔍 Session init check - currentUserId: \(currentUserId), recipientId: \(data.userId)", category: "ChatViewModel")
            
            if data.userId == currentUserId {
                Log.error("❌ Cannot initialize session with yourself: \(data.userId) == \(currentUserId)", category: "ChatViewModel")
                errorMessage = "Cannot create a dialog with yourself"
                return
            }

            do {
                let bundleWithSuite = (
                    identityPublic: data.identityPublic,
                    signedPrekeyPublic: data.signedPrekeyPublic,
                    signature: data.signature,
                    verifyingKey: data.verifyingKey,
                    suiteId: String(data.suiteId)
                )
                try CryptoManager.shared.initializeSession(for: data.userId, recipientBundle: bundleWithSuite)

                isSessionReady = true
                errorMessage = nil
                Log.info("✅ Session initialized as INITIATOR for \(data.userId)", category: "ChatViewModel")

                // Process any pending messages
                processPendingMessages()

            } catch {
                let errorMsg = "Failed to initialize secure session: \(error.localizedDescription)"
                errorMessage = errorMsg
                isSessionReady = false
                Log.error("❌ Failed to initialize session: \(error.localizedDescription)", category: "ChatViewModel")
            }
        }
    }

    // ✅ NEW: Load initial messages (last N messages)
    private func loadMessages() {
        Log.debug("📥 Loading initial messages for chat \(chat.id)", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        // Sort by descending timestamp to get the newest messages first
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = initialMessageLimit

        if let fetchedMessages = try? viewContext.fetch(fetchRequest) {
            // Reverse to get chronological order (oldest first)
            messages = Array(fetchedMessages.reversed())
            oldestLoadedTimestamp = messages.first?.timestamp
            allLoadedMessageIds = Set(messages.map { $0.id })
            
            // Check if there are more messages to load
            checkIfHasMoreMessages()
            
            Log.debug("📬 Loaded \(messages.count) messages (most recent)", category: "ChatViewModel")
        } else {
            Log.error("❌ Failed to fetch messages", category: "ChatViewModel")
        }
    }
    
    // ✅ NEW: Load more messages (older messages)
    func loadMoreMessages() {
        guard !isLoadingMore, hasMoreMessages, let oldestTimestamp = oldestLoadedTimestamp else {
            return
        }
        
        isLoadingMore = true
        Log.debug("📥 Loading more messages before \(oldestTimestamp)", category: "ChatViewModel")
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@ AND timestamp < %@", chat, oldestTimestamp as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = initialMessageLimit
        
        if let fetchedMessages = try? viewContext.fetch(fetchRequest) {
            let newMessages = fetchedMessages.filter { !allLoadedMessageIds.contains($0.id) }
            
            if newMessages.isEmpty {
                hasMoreMessages = false
                isLoadingMore = false
                return
            }
            
            // Reverse to get chronological order
            let reversedNewMessages = Array(newMessages.reversed())
            
            // Prepend older messages to the beginning
            messages = reversedNewMessages + messages
            oldestLoadedTimestamp = messages.first?.timestamp
            allLoadedMessageIds.formUnion(Set(newMessages.map { $0.id }))
            
            // Check if there are more messages
            checkIfHasMoreMessages()
            
            Log.debug("📬 Loaded \(newMessages.count) more messages (total: \(messages.count))", category: "ChatViewModel")
        } else {
            Log.error("❌ Failed to fetch more messages", category: "ChatViewModel")
        }
        
        isLoadingMore = false
    }
    
    // ✅ NEW: Check if there are more messages to load
    private func checkIfHasMoreMessages() {
        guard let oldestTimestamp = oldestLoadedTimestamp else {
            hasMoreMessages = false
            return
        }
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@ AND timestamp < %@", chat, oldestTimestamp as NSDate)
        fetchRequest.fetchLimit = 1
        
        hasMoreMessages = (try? viewContext.fetch(fetchRequest).first) != nil
    }
    
    // ✅ NEW: Reload messages when new ones are added (called from Core Data notifications)
    // MARK: - Delete Messages
    
    func deleteMessage(_ message: Message) {
        // ✅ FIX: Check if message is valid and in correct context
        guard !message.isDeleted,
              message.managedObjectContext == viewContext else {
            Log.error("❌ Message is deleted or not in the correct context", category: "ChatViewModel")
            // Remove from array if it's already deleted
            let messageId = message.id
            messages.removeAll { $0.id == messageId }
            return
        }
        
        // ✅ FIX: Get message ID before deletion
        let messageId = message.id
        
        // ✅ FIX: Remove from array BEFORE deleting from context to prevent crash
        messages.removeAll { $0.id == messageId }
        
        viewContext.delete(message)
        
        do {
            try viewContext.save()
            
            // ✅ FIX: Update chat's lastMessageText and lastMessageTime if needed
            if let lastMessage = messages.last {
                chat.lastMessageText = lastMessage.decryptedContent
                chat.lastMessageTime = lastMessage.timestamp
                try? viewContext.save()
            } else {
                // No messages left, clear chat metadata
                chat.lastMessageText = nil
                chat.lastMessageTime = nil
                try? viewContext.save()
            }
            
            Log.info("✅ Message deleted: \(messageId)", category: "ChatViewModel")
        } catch {
            Log.error("❌ Failed to delete message: \(error)", category: "ChatViewModel")
            // Reload messages on error to ensure consistency
            reloadMessages()
        }
    }
    
    func deleteMessages(withIds messageIds: Set<String>) {
        guard !messageIds.isEmpty else { return }
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", messageIds)
        
        guard let messagesToDelete = try? viewContext.fetch(fetchRequest) else {
            Log.error("❌ Failed to fetch messages for deletion", category: "ChatViewModel")
            return
        }
        
        for message in messagesToDelete {
            viewContext.delete(message)
        }
        
        do {
            try viewContext.save()
            
            // ✅ FIX: Immediately remove from messages array to prevent crash
            messages.removeAll { messageIds.contains($0.id) }
            
            // ✅ FIX: Update chat's lastMessageText and lastMessageTime if needed
            if let lastMessage = messages.last {
                chat.lastMessageText = lastMessage.decryptedContent
                chat.lastMessageTime = lastMessage.timestamp
                try? viewContext.save()
            } else {
                // No messages left, clear chat metadata
                chat.lastMessageText = nil
                chat.lastMessageTime = nil
                try? viewContext.save()
            }
            
            Log.info("✅ Deleted \(messagesToDelete.count) messages", category: "ChatViewModel")
        } catch {
            Log.error("❌ Failed to delete messages: \(error)", category: "ChatViewModel")
            // Reload messages on error to ensure consistency
            reloadMessages()
        }
    }
    
    private func reloadMessages() {
        // Check for new messages that were added
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = initialMessageLimit
        
        if let allMessages = try? viewContext.fetch(fetchRequest) {
            let reversedAllMessages = Array(allMessages.reversed())
            let newMessageIds = Set(reversedAllMessages.map { $0.id })
            
            // ✅ Always reload to catch status changes, not just new messages
            // This ensures UI updates when message.deliveryStatus changes
            let hasNewMessages = !newMessageIds.isSubset(of: allLoadedMessageIds)
            let messagesChanged = messages.count != reversedAllMessages.count
            
            if hasNewMessages || messagesChanged {
                messages = reversedAllMessages
                oldestLoadedTimestamp = messages.first?.timestamp
                allLoadedMessageIds = newMessageIds
                checkIfHasMoreMessages()
            } else {
                // ✅ Force refresh by creating new array with same messages
                // This triggers SwiftUI @Published update even if content is same
                messages = Array(reversedAllMessages)
                objectWillChange.send()
            }
        }
    }

    // MARK: - Send Message
    func sendMessage(text: String, images: [UIImage] = [], replyTo: Message? = nil) {
        Log.info("📤 sendMessage called with \(images.count) images", category: "ChatViewModel")

        // Handle images if provided
        if !images.isEmpty {
            sendMediaMessage(images: images, caption: text, replyTo: replyTo)
            return
        }

        // Validate message size
        do {
            try MessageValidator.validateText(text)
        } catch let error as MessageValidationError {
            errorMessage = error.localizedDescription
            Log.error("❌ Message validation failed: \(error.localizedDescription)", category: "ChatViewModel")
            return
        } catch {
            errorMessage = "Failed to validate message: \(error.localizedDescription)"
            Log.error("❌ Unexpected validation error: \(error)", category: "ChatViewModel")
            return
        }

        guard let recipientId = chat.otherUser?.id else {
            Log.error("❌ No recipient ID", category: "ChatViewModel")
            return
        }

        guard let currentUserId = SessionManager.shared.currentUserId else {
            Log.error("❌ No current user ID", category: "ChatViewModel")
            return
        }

        Log.info("📤 Sending to: \(recipientId), from: \(currentUserId)", category: "ChatViewModel")

        // 🚫 BLOCK: Cannot send encrypted messages to yourself
        if recipientId == currentUserId {
            errorMessage = "Cannot send encrypted messages to yourself. Use notes app instead."
            Log.debug("❌ Blocked attempt to send message to self", category: "ChatViewModel")
            return
        }

        // ✅ FIXED: Check if session is ready before sending
        if !isSessionReady {
            // Queue the message to be sent after session initialization
            pendingMessages.append((text: text, timestamp: Date()))
            errorMessage = "Initializing secure connection..."
            Log.info("⏳ Message queued - waiting for session initialization (session ready: \(isSessionReady))", category: "ChatViewModel")
            return
        }

        Log.info("✅ Session is ready, sending via REST API...", category: "ChatViewModel")

        isSending = true
        errorMessage = nil

        do {
            // Encrypt message and get components
            let components = try CryptoManager.shared.encryptMessage(text, for: recipientId)

            // Create ChatMessage with proper format per server spec
            let messageId = UUID().uuidString
            let message = ChatMessage(
                id: messageId,
                from: currentUserId,
                to: recipientId,
                ephemeralPublicKey: components.ephemeralPublicKey,  // Binary 32 bytes
                messageNumber: components.messageNumber,
                content: components.content,  // Base64(nonce || ciphertext_with_tag)
                suiteId: components.suiteId,
                timestamp: UInt64(Date().timeIntervalSince1970)
                
            )

            Log.debug("📤 Sending message with ID: \(messageId)", category: "ChatViewModel")
            Log.debug("   Message number: \(components.messageNumber)", category: "ChatViewModel")
            Log.debug("   Content length: \(message.content.count) bytes", category: "ChatViewModel")

            // Save with .sending status
            saveMessage(
                message,
                decryptedContent: text,
                isSentByMe: true,
                status: .sending,
                replyTo: replyTo,
                suiteId: components.suiteId
            )

            // ✅ Send through REST API (no WebSocket dependency)
            Log.info("📮 Sending message via REST API: \(messageId)", category: "ChatViewModel")
            Task {
                do {
                    let response = try await RestAPIClient.shared.sendMessage(
                        recipientId: recipientId,
                        ephemeralPublicKey: components.ephemeralPublicKey,
                        messageNumber: components.messageNumber,
                        content: components.content,
                        timestamp: message.timestamp,
                        suiteId: components.suiteId
                    )
                    
                    await MainActor.run {
                        // Update message status to sent
                        Log.info("🔄 Updating message status from sending → sent for \(messageId)", category: "ChatViewModel")
                        updateMessageStatus(messageId: messageId, status: .sent)
                        Log.info("✅ Message sent via REST API: \(response.messageId), status: \(response.status)", category: "ChatViewModel")
                    }
                } catch {
                    await MainActor.run {
                        if let networkError = error as? NetworkError,
                           case .serverError(let message, let responseBody) = networkError {
                            Log.error("❌ Failed to send message via REST: \(message)\nResponse: \(responseBody ?? "empty")", category: "ChatViewModel")
                        } else {
                            Log.error("❌ Failed to send message via REST: \(error.localizedDescription)", category: "ChatViewModel")
                        }
                        updateMessageStatus(messageId: messageId, status: .failed)
                        errorMessage = "Failed to send message: \(error.localizedDescription)"
                    }
                }
            }

        } catch {
            // ✅ Session was corrupted and auto-deleted by CryptoManager
            // Reinitialize session and retry
            Log.debug("🔄 Encryption failed, session was deleted. Reinitializing...", category: "ChatViewModel")

            // Delete old session from memory (already done by CryptoManager)
            // Request new public key bundle to reinitialize
            if let toUserId = chat.otherUser?.id {
                Log.info("🔑 Requesting fresh public key bundle for reinitialization", category: "ChatViewModel")

                // Mark session as not ready to trigger reinitialization flow
                isSessionReady = false

                // Queue this message to be sent after session is reinitialized
                pendingMessages.append((text: text, timestamp: Date()))
                errorMessage = "Session expired, reinitializing..."
                Log.info("📝 Message queued for retry after session reinitialization", category: "ChatViewModel")

                // ✅ FIXED: Request fresh public key bundle via REST API
                Task {
                    do {
                        let publicKeyBundle = try await RestAPIClient.shared.getPublicKey(userId: toUserId)
                        await MainActor.run {
                            self.handlePublicKeyBundle(publicKeyBundle)
                        }
                    } catch {
                        await MainActor.run {
                            Log.error("❌ Failed to fetch public key for reinitialization: \(error.localizedDescription)", category: "ChatViewModel")
                            errorMessage = "Failed to reinitialize session: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                errorMessage = "Failed to encrypt message: \(error.localizedDescription)"
                Log.error("Failed to encrypt message: \(error.localizedDescription)", category: "ChatViewModel")
            }
        }
        isSending = false
    }

    // ✅ FIXED: Process pending messages after session is ready
    private func processPendingMessages() {
        guard isSessionReady else { return }

        let messagesToSend = pendingMessages
        pendingMessages.removeAll()

        for pending in messagesToSend {
            Log.info("Processing pending message from queue", category: "ChatViewModel")
            sendMessage(text: pending.text)
        }
    }

    // ✅ FIX: Send all queued messages when connection is restored
    private func sendQueuedMessages() {
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@ AND deliveryStatusRaw == %d", chat, DeliveryStatus.queued.rawValue)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        guard let queuedMessages = try? viewContext.fetch(fetchRequest) else {
            return
        }

        Log.info("📤 Sending \(queuedMessages.count) queued messages", category: "ChatViewModel")

        for message in queuedMessages {
            // Re-encrypt and send
            guard let decryptedText = message.decryptedContent,
                  let recipientId = chat.otherUser?.id,
                  let currentUserId = SessionManager.shared.currentUserId else {
                continue
            }

            do {
                let components = try CryptoManager.shared.encryptMessage(decryptedText, for: recipientId)

                let chatMessage = ChatMessage(
                    id: message.id,
                    from: currentUserId,
                    to: recipientId,
                    ephemeralPublicKey: components.ephemeralPublicKey,
                    messageNumber: components.messageNumber,
                    content: components.content,
                    suiteId: components.suiteId,
                    timestamp: UInt64(message.timestamp.timeIntervalSince1970)
                    
                )

                message.deliveryStatus = .sending
                message.retryCount += 1
                try? viewContext.save()

                // ✅ FIXED: Send via REST API instead of WebSocket
                Task {
                    do {
                        let response = try await RestAPIClient.shared.sendMessage(
                            recipientId: recipientId,
                            ephemeralPublicKey: components.ephemeralPublicKey,
                            messageNumber: components.messageNumber,
                            content: components.content,
                            timestamp: UInt64(message.timestamp.timeIntervalSince1970),
                            suiteId: components.suiteId
                        )
                        
                        await MainActor.run {
                            message.deliveryStatus = .sent
                            try? self.viewContext.save()
                            Log.debug("📮 Re-sent queued message via REST: \(message.id) (attempt \(message.retryCount))", category: "ChatViewModel")
                        }
                    } catch {
                        await MainActor.run {
                            if let networkError = error as? NetworkError,
                               case .serverError(let message, let responseBody) = networkError {
                                Log.error("❌ Failed to re-send queued message via REST: \(message)\nResponse: \(responseBody ?? "empty")", category: "ChatViewModel")
                            } else {
                                Log.error("Failed to re-send queued message via REST: \(error)", category: "ChatViewModel")
                            }
                            message.deliveryStatus = .failed
                            try? self.viewContext.save()
                        }
                    }
                }
                messageQueueManager.markMessageAsSending(message.id)
                Log.debug("📮 Re-sent queued message: \(message.id) (attempt \(message.retryCount))", category: "ChatViewModel")

            } catch {
                Log.error("Failed to re-encrypt queued message: \(error)", category: "ChatViewModel")
                message.deliveryStatus = .failed
                try? viewContext.save()
            }
        }

        // Messages will be reloaded via NotificationCenter observer
    }

    func retryMessage(_ message: Message) {
        // Retry for failed or queued messages
        guard message.canRetry || message.deliveryStatus == .queued else {
            Log.info("Message cannot be retried", category: "ChatViewModel")
            return
        }

        guard let decryptedText = message.decryptedContent else {
            Log.error("Cannot retry - no decrypted content", category: "ChatViewModel")
            return
        }

        // Increment retry count
        message.retryCount += 1
        try? viewContext.save()

        // Re-send the message
        sendMessage(text: decryptedText)
        Log.info("Retrying message (attempt \(message.retryCount))", category: "ChatViewModel")
    }

    // ✅ NOTE: WebSocket removed - using REST API only
    // Incoming messages are received via long polling in ChatsViewModel
    // and saved to Core Data, then picked up via NSManagedObjectContextObjectsDidChange
    // ACKs are received directly from REST API response when sending messages

    // MARK: - Core Data Operations
    // MARK: - Media Messages

    private func sendMediaMessage(images: [UIImage], caption: String, replyTo: Message?) {
        guard let recipientId = chat.otherUser?.id else {
            Log.error("❌ No recipient ID for media message", category: "ChatViewModel")
            errorMessage = "Cannot send media: no recipient"
            return
        }

        guard isSessionReady else {
            errorMessage = "Waiting for secure connection..."
            Log.info("⏳ Media message blocked - session not ready", category: "ChatViewModel")
            return
        }

        isSending = true
        errorMessage = nil

        Task {
            do {
                var mediaDataList: [MediaMessageData] = []
                var thumbnails: [Data] = []  // ✅ Store thumbnails locally for sender

                // Upload each image
                for (index, image) in images.enumerated() {
                    Log.info("📤 Uploading image \(index + 1)/\(images.count)", category: "ChatViewModel")

                    // ✅ Generate thumbnail before upload (for local storage on sender side)
                    let optimized = try MediaOptimizer.optimizeImage(image)
                    if let thumbnail = optimized.thumbnail {
                        thumbnails.append(thumbnail)
                        Log.debug("📸 Generated thumbnail: \(thumbnail.count) bytes", category: "ChatViewModel")
                    }

                    let mediaData = try await MediaUploadService.shared.uploadImage(image, for: recipientId)
                    mediaDataList.append(mediaData)

                    Log.info("✅ Image \(index + 1) uploaded: \(mediaData.mediaId)", category: "ChatViewModel")
                }

                // Build message content with media references
                let messageContent = buildMediaMessageContent(
                    caption: caption,
                    mediaList: mediaDataList
                )

                // Send as regular encrypted message
                await MainActor.run {
                    // ✅ Store thumbnails locally before sending
                    // We'll save them with the message after it's created
                    sendTextMessage(text: messageContent, replyTo: replyTo, localThumbnails: thumbnails)
                }

            } catch {
                await MainActor.run {
                    Log.error("❌ Media upload failed: \(error.localizedDescription)", category: "ChatViewModel")
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func buildMediaMessageContent(caption: String, mediaList: [MediaMessageData]) -> String {
        // Build JSON content for media message
        // Format: {"type":"media","caption":"...","media":[...]}
        // ✅ FIX: Remove thumbnails from JSON to avoid exceeding 64KB limit
        // Thumbnails can be generated client-side from downloaded media
        struct MediaContent: Codable {
            let type: String
            let caption: String
            let media: [MediaMessageDataWithoutThumbnail]
        }
        
        // MediaMessageData without thumbnail to reduce JSON size
        struct MediaMessageDataWithoutThumbnail: Codable {
            let mediaId: String
            let mediaUrl: String
            let mediaKey: String
            let mediaType: String
            let size: Int
            let width: Int?
            let height: Int?
            let duration: TimeInterval?
            let hash: String
            // thumbnail excluded to keep JSON under 64KB
        }
        
        let mediaWithoutThumbnails = mediaList.map { media in
            MediaMessageDataWithoutThumbnail(
                mediaId: media.mediaId,
                mediaUrl: media.mediaUrl,
                mediaKey: media.mediaKey,
                mediaType: media.mediaType,
                size: media.size,
                width: media.width,
                height: media.height,
                duration: media.duration,
                hash: media.hash
            )
        }

        let content = MediaContent(
            type: "media",
            caption: caption,
            media: mediaWithoutThumbnails
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let jsonData = try? encoder.encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Log.error("❌ Failed to encode media message content", category: "ChatViewModel")
            return caption
        }
        
        // ✅ Check JSON size before sending
        let jsonSize = jsonString.utf8.count
        let maxSize = 64 * 1024 // 64KB limit
        if jsonSize > maxSize {
            Log.error("❌ Media message JSON too large: \(jsonSize) bytes (max \(maxSize))", category: "ChatViewModel")
            // Try without some optional fields
            let minimalMedia = mediaWithoutThumbnails.map { media in
                MediaMessageDataWithoutThumbnail(
                    mediaId: media.mediaId,
                    mediaUrl: media.mediaUrl,
                    mediaKey: media.mediaKey,
                    mediaType: media.mediaType,
                    size: media.size,
                    width: nil,  // Remove optional fields
                    height: nil,
                    duration: nil,
                    hash: media.hash
                )
            }
            
            let minimalContent = MediaContent(
                type: "media",
                caption: caption,
                media: minimalMedia
            )
            
            if let minimalJsonData = try? encoder.encode(minimalContent),
               let minimalJsonString = String(data: minimalJsonData, encoding: .utf8),
               minimalJsonString.utf8.count <= maxSize {
                Log.info("✅ Using minimal media message format", category: "ChatViewModel")
                return minimalJsonString
            } else {
                Log.error("❌ Even minimal format exceeds size limit", category: "ChatViewModel")
                return caption
            }
        }
        
        Log.debug("📤 Media message JSON size: \(jsonSize) bytes", category: "ChatViewModel")
        return jsonString
    }

    private func sendTextMessage(text: String, replyTo: Message?, localThumbnails: [Data] = []) {
        // Reuse existing logic for sending text messages
        guard let recipientId = chat.otherUser?.id,
              let currentUserId = SessionManager.shared.currentUserId else {
            isSending = false
            return
        }

        do {
            let components = try CryptoManager.shared.encryptMessage(text, for: recipientId)
            let messageId = UUID().uuidString
            let message = ChatMessage(
                id: messageId,
                from: currentUserId,
                to: recipientId,
                ephemeralPublicKey: components.ephemeralPublicKey,
                messageNumber: components.messageNumber,
                content: components.content,
                suiteId: components.suiteId,
                timestamp: UInt64(Date().timeIntervalSince1970)
                
            )

            saveMessage(message, decryptedContent: text, isSentByMe: true, status: .sending, replyTo: replyTo, localThumbnails: localThumbnails, suiteId: components.suiteId)

            // ✅ Send via REST API (no WebSocket dependency)
            Task {
                do {
                    let response = try await RestAPIClient.shared.sendMessage(
                        recipientId: recipientId,
                        ephemeralPublicKey: components.ephemeralPublicKey,
                        messageNumber: components.messageNumber,
                        content: components.content,
                        timestamp: message.timestamp,
                        suiteId: components.suiteId
                    )
                    
                    await MainActor.run {
                        updateMessageStatus(messageId: message.id, status: .sent)
                        isSending = false
                    }
                } catch {
                    await MainActor.run {
                        if let networkError = error as? NetworkError,
                           case .serverError(let message, let responseBody) = networkError {
                            Log.error("❌ Failed to send message via REST: \(message)\nResponse: \(responseBody ?? "empty")", category: "ChatViewModel")
                        } else {
                            Log.error("❌ Failed to send message via REST: \(error.localizedDescription)", category: "ChatViewModel")
                        }
                        updateMessageStatus(messageId: message.id, status: .failed)
                        errorMessage = "Failed to send message: \(error.localizedDescription)"
                        isSending = false
                    }
                }
            }

        } catch {
            Log.error("❌ Failed to encrypt message: \(error)", category: "ChatViewModel")
            errorMessage = "Failed to encrypt message"
            isSending = false
        }
    }

    private func saveMessage(_ message: ChatMessage, decryptedContent: String, isSentByMe: Bool, status: DeliveryStatus, replyTo: Message? = nil, localThumbnails: [Data] = [], suiteId: UInt16) {
        Log.debug("💾 Saving message \(message.id), isSentByMe: \(isSentByMe), status: \(status)", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id)

        let messageTimestamp = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
        let isNewMessage: Bool
        

        if let existing = try? viewContext.fetch(fetchRequest).first {
            Log.debug("📝 Updating existing message \(message.id)", category: "ChatViewModel")
            existing.deliveryStatus = status
            isNewMessage = false
        } else {
            Log.debug("✨ Creating new message \(message.id)", category: "ChatViewModel")
            let newMessage = Message(context: viewContext)
            newMessage.id = message.id
            newMessage.fromUserId = message.from
            newMessage.toUserId = message.to
            newMessage.encryptedContent = message.content
            newMessage.decryptedContent = decryptedContent
            newMessage.timestamp = messageTimestamp
            newMessage.isSentByMe = isSentByMe
            newMessage.deliveryStatus = status
            newMessage.retryCount = 0  // ✅ FIX: Initialize required field
            newMessage.chat = chat
            newMessage.suiteId = suiteId
            
            // Set reply information
            if let replyMessage = replyTo {
                newMessage.replyToMessageId = replyMessage.id
                newMessage.replyToContent = replyMessage.decryptedContent
            }
            
            // ✅ Store thumbnails locally for media messages (sender side)
            if !localThumbnails.isEmpty {
                // Store first thumbnail in UserDefaults (temporary solution)
                // TODO: Add thumbnailData field to Message entity in Core Data
                if let firstThumbnail = localThumbnails.first {
                    UserDefaults.standard.set(firstThumbnail, forKey: "message_thumbnail_\(message.id)")
                    Log.debug("💾 Stored thumbnail locally for message \(message.id)", category: "ChatViewModel")
                }
            }
            
            isNewMessage = true
        }

        do {
            try viewContext.save()
            
            // ✅ FIX: Update chat's lastMessageText and lastMessageTime when a new message is saved
            // Compare timestamps to ensure we update with the most recent message
            if isNewMessage {
                if let lastTime = chat.lastMessageTime {
                    if messageTimestamp > lastTime {
                        chat.lastMessageText = decryptedContent
                        chat.lastMessageTime = messageTimestamp
                        try viewContext.save()
                        Log.debug("✅ Updated chat.lastMessageText and lastMessageTime", category: "ChatViewModel")
                    }
                } else {
                    // No previous message, always update
                    chat.lastMessageText = decryptedContent
                    chat.lastMessageTime = messageTimestamp
                    try viewContext.save()
                    Log.debug("✅ Updated chat.lastMessageText and lastMessageTime (first message)", category: "ChatViewModel")
                }
            }
            
            Log.debug("✅ Message saved to Core Data", category: "ChatViewModel")
            // Messages will be reloaded via NotificationCenter observer
            reloadMessages()
            Log.debug("📊 After reloadMessages: \(messages.count) messages", category: "ChatViewModel")
        } catch {
            Log.error("Failed to save or update message: \(error.localizedDescription)", category: "ChatViewModel")
        }
    }

    private func updateMessageStatus(messageId: String, status: DeliveryStatus) {
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)

        if let message = try? viewContext.fetch(fetchRequest).first {
            message.deliveryStatus = status
            
            do {
                try viewContext.save()
                // ✅ Force UI update immediately
                objectWillChange.send()
                Log.debug("✅ Updated message status to \(status) for \(messageId)", category: "ChatViewModel")
            } catch {
                Log.error("❌ Failed to save message status: \(error)", category: "ChatViewModel")
            }
        }
    }
}
