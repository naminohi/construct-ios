import Foundation
import Combine
import CoreData
import os.log

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isSending = false
    @Published var errorMessage: String?

    // ✅ FIXED: Track session initialization state
    @Published var isSessionReady = false

    // ✅ FIXED: Queue for pending messages before session is ready
    private var pendingMessages: [(text: String, timestamp: Date)] = []

    let chat: Chat
    private var recipientBundle: (identityPublic: String, signedPrekeyPublic: String, signature: String, verifyingKey: String)?

    private let wsManager = WebSocketManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var viewContext: NSManagedObjectContext

    init(chat: Chat, context: NSManagedObjectContext) {
        self.chat = chat
        self.viewContext = context
        setupSubscribers()
        checkExistingSession()  // ✅ FIXED: Check if session already exists
        fetchRecipientPublicKey()

        // Load messages immediately since we have context
        Log.debug("🔧 ChatViewModel initialized with viewContext", category: "ChatViewModel")
        loadMessages()
    }

    deinit {
        // ✅ FIX: Clean up subscriptions when ViewModel is destroyed
        cancellables.removeAll()
        Log.debug("🔧 ChatViewModel deinitialized", category: "ChatViewModel")
    }

    private func setupSubscribers() {
        wsManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleServerMessage(message)
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
        guard let userId = chat.otherUser?.id else { return }
        guard let currentUserId = SessionManager.shared.currentUserId else { return }

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

        wsManager.send(.getPublicKey(GetPublicKeyData(userId: userId)))
    }

    private func loadMessages() {
        Log.debug("📥 Loading messages for chat \(chat.id ?? "unknown")", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        if let fetchedMessages = try? viewContext.fetch(fetchRequest) {
            messages = fetchedMessages
            Log.debug("📬 Loaded \(fetchedMessages.count) messages", category: "ChatViewModel")
            for (index, msg) in fetchedMessages.enumerated() {
                Log.debug("  Message \(index): id=\(msg.id ?? "nil"), isSentByMe=\(msg.isSentByMe), text=\(msg.decryptedContent?.prefix(20) ?? "nil")", category: "ChatViewModel")
            }
        } else {
            Log.error("❌ Failed to fetch messages", category: "ChatViewModel")
        }
    }

    // MARK: - Send Message
    func sendMessage(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let recipientId = chat.otherUser?.id else { return }
        guard let currentUserId = SessionManager.shared.currentUserId else { return }

        // 🚫 BLOCK: Cannot send encrypted messages to yourself
        if recipientId == currentUserId {
            errorMessage = "Cannot send encrypted messages to yourself. Use notes app instead."
            Log.debug("Blocked attempt to send message to self", category: "ChatViewModel")
            return
        }

        // ✅ FIXED: Check if session is ready before sending
        if !isSessionReady {
            // Queue the message to be sent after session initialization
            pendingMessages.append((text: text, timestamp: Date()))
            errorMessage = "Initializing secure connection..."
            Log.info("Message queued - waiting for session initialization", category: "ChatViewModel")
            return
        }

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
                timestamp: UInt64(Date().timeIntervalSince1970)
            )

            Log.debug("📤 Sending message with ID: \(messageId)", category: "ChatViewModel")
            saveMessage(message, decryptedContent: text, isSentByMe: true, status: .sending)
            wsManager.send(.sendMessage(message))
            Log.debug("📮 Message sent to WebSocket: \(messageId)", category: "ChatViewModel")

        } catch {
            errorMessage = "Failed to encrypt message: \(error.localizedDescription)"
            Log.error("Failed to encrypt message: \(error.localizedDescription)", category: "ChatViewModel")
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

    func retryMessage(_ message: Message) {
        // This needs to be re-thought. Retrying a message in a ratchet is complex.
        // For now, we just re-send the original encrypted content, which will fail to decrypt on the other side.
        // A proper implementation would require re-encrypting the decrypted content.
        Log.info("Message retry is not fully implemented for ratchet protocol.", category: "ChatViewModel")
    }

    // MARK: - Handle Server Messages
    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .publicKeyBundle(let data):
            if data.userId == chat.otherUser?.id {
                // ✅ Update username if we have the user in Core Data
                if let user = chat.otherUser {
                    user.username = data.username
                    user.displayName = data.username
                    try? viewContext.save()
                    Log.info("Updated username for user: \(data.username)", category: "ChatViewModel")
                }

                self.recipientBundle = (data.identityPublic, data.signedPrekeyPublic, data.signature, data.verifyingKey)
                guard let currentUserId = SessionManager.shared.currentUserId else { return }

                // 🔑 Determine who is the initiator (lexicographically smaller UUID)
                let isInitiator = currentUserId < data.userId

                if isInitiator {
                    // ✅ ALICE (initiator): Initialize session immediately
                    do {
                        let bundleWithSuite = (
                            identityPublic: self.recipientBundle!.identityPublic,
                            signedPrekeyPublic: self.recipientBundle!.signedPrekeyPublic,
                            signature: self.recipientBundle!.signature,
                            verifyingKey: self.recipientBundle!.verifyingKey,
                            suiteId: "1"
                        )
                        try CryptoManager.shared.initializeSession(for: data.userId, recipientBundle: bundleWithSuite)

                        isSessionReady = true
                        errorMessage = nil
                        Log.info("✅ Session initialized as INITIATOR for \(data.userId)", category: "ChatViewModel")

                        processPendingMessages()

                    } catch {
                        errorMessage = "Failed to initialize secure session: \(error.localizedDescription)"
                        Log.error("❌ Failed to initialize session as initiator: \(error.localizedDescription)", category: "ChatViewModel")
                        isSessionReady = false
                    }
                } else {
                    // ✅ BOB (responder): Do NOT initialize session here!
                    // Session will be initialized in ChatsViewModel when first message arrives
                    Log.info("📦 Received public key bundle as RESPONDER - waiting for first message to initialize session", category: "ChatViewModel")
                    // Don't set isSessionReady = true yet
                    // ChatsViewModel will handle init_receiving_session when first message arrives
                }
            }
        // ✅ REMOVED: .message handling - ChatsViewModel handles ALL incoming messages
        // ChatViewModel only handles ACKs for sent messages
        case .ack(let data):
            handleAck(messageId: data.messageId, status: data.status)
        case .error(let data):
            self.errorMessage = data.message
        default:
            break
        }
    }
    
    private func handleAck(messageId: String, status: String) {
        Log.debug("📨 Received ACK for message: \(messageId), status: \(status)", category: "ChatViewModel")

        // First, try to find the message by ID
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)

        if let message = try? viewContext.fetch(fetchRequest).first {
            Log.debug("✅ Found message by ID: \(messageId)", category: "ChatViewModel")
            updateMessageStatus(messageId: messageId, status: status == "delivered" ? .delivered : .sent)
        } else {
            Log.debug("❌ Message not found by ID: \(messageId)", category: "ChatViewModel")

            // List all pending messages to debug
            let allMessagesRequest: NSFetchRequest<Message> = Message.fetchRequest()
            allMessagesRequest.predicate = NSPredicate(format: "chat == %@ AND isSentByMe == YES", chat)
            allMessagesRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            if let allMessages = try? viewContext.fetch(allMessagesRequest) {
                Log.debug("📋 All sent messages in this chat:", category: "ChatViewModel")
                for msg in allMessages.prefix(5) {
                    Log.debug("  - ID: \(msg.id ?? "nil"), status: \(msg.deliveryStatus), timestamp: \(msg.timestamp)", category: "ChatViewModel")
                }

                // Try to match by most recent sending message
                if let mostRecentSending = allMessages.first(where: { $0.deliveryStatus == .sending }) {
                    Log.debug("🔄 Assuming ACK is for most recent sending message: \(mostRecentSending.id ?? "nil")", category: "ChatViewModel")
                    mostRecentSending.deliveryStatus = status == "delivered" ? .delivered : .sent
                    try? viewContext.save()
                    loadMessages()
                }
            }
        }
    }

    // ✅ REMOVED: handleIncomingMessage - ChatsViewModel handles ALL incoming messages
    // ChatViewModel only displays messages already saved to Core Data

    // MARK: - Core Data Operations
    private func saveMessage(_ message: ChatMessage, decryptedContent: String, isSentByMe: Bool, status: DeliveryStatus) {
        Log.debug("💾 Saving message \(message.id), isSentByMe: \(isSentByMe), status: \(status)", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id)

        if let existing = try? viewContext.fetch(fetchRequest).first {
            Log.debug("📝 Updating existing message \(message.id)", category: "ChatViewModel")
            existing.deliveryStatus = status
        } else {
            Log.debug("✨ Creating new message \(message.id)", category: "ChatViewModel")
            let newMessage = Message(context: viewContext)
            newMessage.id = message.id
            newMessage.fromUserId = message.from
            newMessage.toUserId = message.to
            newMessage.encryptedContent = message.content
            newMessage.decryptedContent = decryptedContent
            newMessage.timestamp = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
            newMessage.isSentByMe = isSentByMe
            newMessage.deliveryStatus = status
            newMessage.chat = chat
        }

        do {
            try viewContext.save()
            Log.debug("✅ Message saved to Core Data", category: "ChatViewModel")
            loadMessages()
            Log.debug("📊 After loadMessages: \(messages.count) messages", category: "ChatViewModel")
        } catch {
            Log.error("Failed to save or update message: \(error.localizedDescription)", category: "ChatViewModel")
        }
    }

    private func updateMessageStatus(messageId: String, status: DeliveryStatus) {
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)

        if let message = try? viewContext.fetch(fetchRequest).first {
            message.deliveryStatus = status
            try? viewContext.save()
            loadMessages()
        }
    }
}
