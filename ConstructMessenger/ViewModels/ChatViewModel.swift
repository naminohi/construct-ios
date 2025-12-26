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
    private var viewContext: NSManagedObjectContext?

    init(chat: Chat) {
        self.chat = chat
        setupSubscribers()
        checkExistingSession()  // ✅ FIXED: Check if session already exists
        fetchRecipientPublicKey()
    }

    func setContext(_ context: NSManagedObjectContext) {
        Log.debug("🔧 Setting viewContext for ChatViewModel", category: "ChatViewModel")
        self.viewContext = context
        loadMessages()
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
        guard let context = viewContext else {
            Log.error("❌ loadMessages: viewContext is nil", category: "ChatViewModel")
            return
        }

        Log.debug("📥 Loading messages for chat \(chat.id ?? "unknown")", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        if let fetchedMessages = try? context.fetch(fetchRequest) {
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
            let message = ChatMessage(
                id: UUID().uuidString,
                from: currentUserId,
                to: recipientId,
                ephemeralPublicKey: components.ephemeralPublicKey,  // Binary 32 bytes
                messageNumber: components.messageNumber,
                content: components.content,  // Base64(nonce || ciphertext_with_tag)
                timestamp: UInt64(Date().timeIntervalSince1970)
            )

            saveMessage(message, decryptedContent: text, isSentByMe: true, status: .sending)
            wsManager.send(.sendMessage(message))

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
                self.recipientBundle = (data.identityPublic, data.signedPrekeyPublic, data.signature, data.verifyingKey)
                guard let currentUserId = SessionManager.shared.currentUserId else { return }

                // Determine who is the initiator.
                let isInitiator = currentUserId < data.userId

                do {
                    // Create a new bundle with the suiteId.
                    let bundleWithSuite = (
                        identityPublic: self.recipientBundle!.identityPublic,
                        signedPrekeyPublic: self.recipientBundle!.signedPrekeyPublic,
                        signature: self.recipientBundle!.signature,
                        verifyingKey: self.recipientBundle!.verifyingKey,
                        suiteId: "1" // Hardcoded suiteId
                    )
                    try CryptoManager.shared.initializeSession(for: data.userId, recipientBundle: bundleWithSuite)

                    // ✅ FIXED: Mark session as ready
                    isSessionReady = true
                    errorMessage = nil
                    Log.info("Session initialized successfully", category: "ChatViewModel")

                    // ✅ FIXED: Process any pending messages
                    processPendingMessages()

                } catch {
                    errorMessage = "Failed to initialize secure session: \(error.localizedDescription)"
                    Log.error("Failed to initialize secure session: \(error.localizedDescription)", category: "ChatViewModel")
                    isSessionReady = false
                }
            }
        case .message(let msg):
            if msg.from == chat.otherUser?.id {
                handleIncomingMessage(msg)
            }
        case .ack(let data):
            handleAck(messageId: data.messageId, status: data.status)
        case .error(let data):
            self.errorMessage = data.message
        default:
            break
        }
    }
    
    private func handleAck(messageId: String, status: String) {
        updateMessageStatus(messageId: messageId, status: status == "delivered" ? .delivered : .sent)
    }
    
    private func handleIncomingMessage(_ message: ChatMessage) {
        do {
            let decryptedText = try CryptoManager.shared.decryptMessage(message)
            saveMessage(message, decryptedContent: decryptedText, isSentByMe: false, status: .delivered)
        } catch {
            Log.error("Error decrypting message: \(String(describing: error))", category: "ChatViewModel")
        }
    }

    // MARK: - Core Data Operations
    private func saveMessage(_ message: ChatMessage, decryptedContent: String, isSentByMe: Bool, status: DeliveryStatus) {
        guard let context = viewContext else {
            Log.error("❌ saveMessage: viewContext is nil", category: "ChatViewModel")
            return
        }

        Log.debug("💾 Saving message \(message.id), isSentByMe: \(isSentByMe), status: \(status)", category: "ChatViewModel")

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id)

        if let existing = try? context.fetch(fetchRequest).first {
            Log.debug("📝 Updating existing message \(message.id)", category: "ChatViewModel")
            existing.deliveryStatus = status
        } else {
            Log.debug("✨ Creating new message \(message.id)", category: "ChatViewModel")
            let newMessage = Message(context: context)
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
            try context.save()
            Log.debug("✅ Message saved to Core Data", category: "ChatViewModel")
            loadMessages()
            Log.debug("📊 After loadMessages: \(messages.count) messages", category: "ChatViewModel")
        } catch {
            Log.error("Failed to save or update message: \(error.localizedDescription)", category: "ChatViewModel")
        }
    }
    
    private func updateMessageStatus(messageId: String, status: DeliveryStatus) {
        guard let context = viewContext else { return }

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)

        if let message = try? context.fetch(fetchRequest).first {
            message.deliveryStatus = status
            try? context.save()
            loadMessages()
        }
    }
}
