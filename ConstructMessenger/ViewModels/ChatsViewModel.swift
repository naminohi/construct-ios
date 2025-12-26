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
        context.delete(chat)
        try? context.save()
    }

    // MARK: - Handle Server Messages
    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .searchResults(let data):
            searchResults = data.users
            isSearching = false

        case .message(let msg):
            handleIncomingMessage(msg)
            
        case .error(let data):
            searchError = data.message
            isSearching = false

        default:
            break
        }
    }

    private func handleIncomingMessage(_ message: ChatMessage) {
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

        guard let decryptedContent = try? CryptoManager.shared.decryptMessage(message) else {
            print("❌ ChatsViewModel: Failed to decrypt incoming message \(message.id)")
            return
        }

        saveMessage(for: chat, with: message, decryptedContent: decryptedContent)

        chat.lastMessageText = decryptedContent
        chat.lastMessageTime = Date(timeIntervalSince1970: TimeInterval(message.timestamp))

        try? context.save()
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
