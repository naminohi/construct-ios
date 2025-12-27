//
//  ChatsViewModel.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import Foundation
import Combine
import CoreData

@MainActor
class ChatsViewModel: ObservableObject {
    @Published var searchResults: [PublicUserInfo] = []
    @Published var isSearching = false
    @Published var searchError: String?

    private let wsManager = WebSocketManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var viewContext: NSManagedObjectContext?

    // ✅ Store pending first messages from users we don't have sessions with yet
    private var pendingFirstMessages: [String: ChatMessage] = [:]  // [userId: firstMessage]

    init() {
        setupSubscribers()
    }

    func setContext(_ context: NSManagedObjectContext) {
        self.viewContext = context
    }

    private func setupSubscribers() {
        wsManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleServerMessage(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Search Users
    func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        searchError = nil
        wsManager.send(.searchUsers(SearchUsersData(query: query)))
    }

    // MARK: - Start Chat
    func startChat(with user: PublicUserInfo) -> Chat? {
        guard let context = viewContext else { return nil }

        let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "otherUser.id == %@", user.id)

        if let existingChat = try? context.fetch(fetchRequest).first {
            return existingChat
        }

        let dbUser = User(context: context)
        dbUser.id = user.id
        dbUser.username = user.username
        dbUser.displayName = user.username // ✅ FIX: Set required displayName

        let chat = Chat(context: context)
        chat.id = UUID().uuidString
        chat.otherUser = dbUser

        try? context.save()
        return chat
    }

    // MARK: - Delete Chat
    func deleteChat(chat: Chat) {
        guard let context = viewContext else { return }

        // ✅ CRITICAL FIX: Delete crypto session when deleting chat
        if let userId = chat.otherUser?.id {
            CryptoManager.shared.deleteSession(for: userId)
            Log.info("🗑️ Deleted crypto session for user: \(userId)", category: "ChatsViewModel")
        }

        context.delete(chat)
        try? context.save()
    }

    // MARK: - Handle Server Messages
    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .searchResults(let data):
            searchResults = data.users
            isSearching = false

        case .publicKeyBundle(let data):
            handlePublicKeyBundle(data)

        case .message(let msg):
            handleIncomingMessage(msg)

        case .error(let data):
            searchError = data.message
            isSearching = false

        default:
            break
        }
    }

    // MARK: - Handle Public Key Bundle (for receiving session initialization)
    private func handlePublicKeyBundle(_ data: PublicKeyBundleData) {
        // Check if we have a pending first message from this user
        guard let firstMessage = pendingFirstMessages[data.userId] else {
            // No pending message - this bundle was requested for outgoing session (handled in ChatViewModel)
            Log.debug("Received public key bundle for \(data.userId), but no pending first message", category: "ChatsViewModel")
            return
        }

        Log.info("🔑 Received public key bundle for \(data.userId) - initializing receiving session", category: "ChatsViewModel")

        guard let context = viewContext else { return }
        guard let currentUserId = SessionManager.shared.currentUserId else { return }

        // Create bundle tuple
        let bundleWithSuite = (
            identityPublic: data.identityPublic,
            signedPrekeyPublic: data.signedPrekeyPublic,
            signature: data.signature,
            verifyingKey: data.verifyingKey,
            suiteId: "1"
        )

        do {
            // ✅ Initialize receiving session with sender's bundle + first message
            try CryptoManager.shared.initReceivingSession(
                for: data.userId,
                recipientBundle: bundleWithSuite,
                firstMessage: firstMessage
            )

            Log.info("✅ Receiving session initialized for \(data.userId)", category: "ChatsViewModel")

            // Now decrypt the first message
            guard let decryptedContent = try? CryptoManager.shared.decryptMessage(firstMessage) else {
                Log.error("❌ Failed to decrypt first message after session init", category: "ChatsViewModel")
                pendingFirstMessages.removeValue(forKey: data.userId)
                return
            }

            // Find or create chat
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "otherUser.id == %@", data.userId)

            let chat: Chat
            if let existingChat = try? context.fetch(fetchRequest).first {
                chat = existingChat
            } else {
                let newUser = User(context: context)
                newUser.id = data.userId
                newUser.username = data.username
                newUser.displayName = data.username

                let newChat = Chat(context: context)
                newChat.id = UUID().uuidString
                newChat.otherUser = newUser
                chat = newChat
            }

            // Save the message
            saveMessage(for: chat, with: firstMessage, decryptedContent: decryptedContent)

            chat.lastMessageText = decryptedContent
            chat.lastMessageTime = Date(timeIntervalSince1970: TimeInterval(firstMessage.timestamp))

            // Remove from pending
            pendingFirstMessages.removeValue(forKey: data.userId)

            Log.info("✅ First message from \(data.userId) decrypted and saved", category: "ChatsViewModel")

        } catch {
            Log.error("❌ Failed to initialize receiving session: \(error)", category: "ChatsViewModel")
            pendingFirstMessages.removeValue(forKey: data.userId)
        }
    }

    private func handleIncomingMessage(_ message: ChatMessage) {
        Log.debug("📨 ChatsViewModel: Incoming message \(message.id) from \(message.from)", category: "ChatsViewModel")

        guard let context = viewContext,
              let currentUserId = SessionManager.shared.currentUserId else { return }

        let otherUserId = message.from == currentUserId ? message.to : message.from

        let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "otherUser.id == %@", otherUserId)

        let chat: Chat
        if let existingChat = try? context.fetch(fetchRequest).first {
            chat = existingChat
        } else {
            // Create a new user with only the ID (no server-stored metadata)
            let newUser = User(context: context)
            newUser.id = otherUserId
            newUser.username = otherUserId
            newUser.displayName = otherUserId // ✅ FIX: Set required displayName
            // User display info is stored locally only, not fetched from server

            let newChat = Chat(context: context)
            newChat.id = UUID().uuidString
            newChat.otherUser = newUser
            chat = newChat

            // NOTE: If we received a message, session already exists.
            // Don't request public key here - it's for session initialization only!
        }

        // ✅ Check if we have a session for this user
        let hasSession = CryptoManager.shared.hasSession(for: otherUserId)

        let decryptedContent: String
        if !hasSession {
            // 🔑 First message from this user - need to initialize receiving session
            Log.info("📩 First message from \(otherUserId) - requesting public key bundle", category: "ChatsViewModel")

            // Store the first message temporarily
            pendingFirstMessages[otherUserId] = message

            // Request sender's public key bundle from server
            wsManager.send(.getPublicKey(GetPublicKeyData(userId: otherUserId)))

            // Exit early - we'll process this message after receiving the public key bundle
            return
        } else {
            // ✅ Existing session - decrypt normally
            guard let content = try? CryptoManager.shared.decryptMessage(message) else {
                Log.error("❌ ChatsViewModel: Failed to decrypt incoming message \(message.id)", category: "ChatsViewModel")
                return
            }
            decryptedContent = content
        }

        saveMessage(for: chat, with: message, decryptedContent: decryptedContent)

        chat.lastMessageText = decryptedContent
        chat.lastMessageTime = Date(timeIntervalSince1970: TimeInterval(message.timestamp))

        // ✅ REMOVED DUPLICATE: saveMessage() already calls context.save() internally
    }
    
    private func saveMessage(for chat: Chat, with messageData: ChatMessage, decryptedContent: String) {
        guard let context = viewContext else { return }

        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageData.id)

        if (try? context.fetch(fetchRequest).first) != nil {
            return // Already exists
        }

        let message = Message(context: context)
        message.id = messageData.id
        message.fromUserId = messageData.from
        message.toUserId = messageData.to
        message.encryptedContent = messageData.content
        message.decryptedContent = decryptedContent
        message.timestamp = Date(timeIntervalSince1970: TimeInterval(messageData.timestamp))
        message.isSentByMe = false
        message.deliveryStatus = .delivered
        message.retryCount = 0
        message.chat = chat

        do {
            try context.save()
        } catch {
            print("❌ ChatsViewModel: Failed to save message: \(error)")
        }
    }
}
