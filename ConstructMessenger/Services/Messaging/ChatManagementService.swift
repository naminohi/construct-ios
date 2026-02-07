//
//  ChatManagementService.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 02.02.2026.
//

import Foundation
import CoreData

/// Manages chat lifecycle: creation from invites and deletion with cleanup
/// Extracted from ChatsViewModel Phase 1.6
@MainActor
class ChatManagementService {
    
    // MARK: - Core Data
    
    private var viewContext: NSManagedObjectContext?
    
    func setContext(_ context: NSManagedObjectContext) {
        self.viewContext = context
    }
    
    // MARK: - Callbacks
    
    /// Called when a new chat is created
    var onChatCreated: ((Chat) -> Void)?
    
    /// Called when a chat is deleted
    var onChatDeleted: ((String) -> Void)?
    
    // MARK: - Chat Creation
    
    /// Start a new chat with a user (from invite link or QR code)
    /// - Parameter user: Public user information from invite
    /// - Returns: Created or existing chat, nil if context is unavailable
    func startChat(with user: PublicUserInfo) -> Chat? {
        guard let context = viewContext else { 
            Log.error("❌ ChatManagementService: No viewContext available", category: "ChatManagementService")
            return nil 
        }
        
        // Check if chat already exists
        let fetchRequest = Chat.fetchRequest()
        let chatOwnerPredicate = fetchRequest.predicate!
        let otherUserPredicate = NSPredicate(format: "otherUser.id == %@", user.id)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [chatOwnerPredicate, otherUserPredicate])
        
        if let existingChat = try? context.fetch(fetchRequest).first {
            Log.debug("ℹ️ Chat already exists with user: \(user.username)", category: "ChatManagementService")
            return existingChat
        }
        
        // Check if User already exists before creating a new one
        let userFetchRequest = User.fetchRequest()
        let userOwnerPredicate = userFetchRequest.predicate!
        let idPredicate = NSPredicate(format: "id == %@", user.id)
        userFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [userOwnerPredicate, idPredicate])
        
        let dbUser: User
        if let existingUser = try? context.fetch(userFetchRequest).first {
            // Use existing user - update username and displayName if they changed
            existingUser.username = user.username
            existingUser.displayName = user.username
            dbUser = existingUser
            Log.debug("Using existing user: id=\(user.id), username=\(user.username), displayName=\(existingUser.displayName)", category: "ChatManagementService")
        } else {
            // Create new user
            dbUser = User(context: context)
            dbUser.id = user.id
            dbUser.username = user.username
            dbUser.displayName = user.username
            dbUser.isSharingWithMe = false
            dbUser.isBlocked = false
            dbUser.amISharingWith = false
            Log.debug("Created new user: id=\(user.id), username=\(user.username), displayName=\(user.username)", category: "ChatManagementService")
        }
        
        // Create new chat
        let chat = Chat(context: context)
        chat.id = UUID().uuidString
        chat.otherUser = dbUser
        
        do {
            try context.save()
            Log.debug("✅ Chat saved successfully", category: "ChatManagementService")
            Log.debug("   chat.id = \(chat.id)", category: "ChatManagementService")
            Log.debug("   chat.otherUser?.id = \(chat.otherUser?.id ?? "nil")", category: "ChatManagementService")
            Log.debug("   chat.otherUser?.username = \(chat.otherUser?.username ?? "nil")", category: "ChatManagementService")
            Log.debug("   chat.otherUser?.displayName = \(chat.otherUser?.displayName ?? "nil")", category: "ChatManagementService")
            
            // Notify via callback
            onChatCreated?(chat)
            
            return chat
        } catch {
            Log.error("❌ Failed to save chat: \(error)", category: "ChatManagementService")
            return nil
        }
    }
    
    // MARK: - Chat Deletion
    
    /// Delete a chat and clean up all associated data
    /// - Parameter chat: Chat to delete
    /// - Note: Deletes messages, archives crypto sessions, clears shared secrets
    func deleteChat(_ chat: Chat) {
        guard let context = viewContext else {
            Log.error("❌ ChatManagementService: No viewContext available", category: "ChatManagementService")
            return
        }
        
        let chatId = chat.id
        
        // Archive crypto session when deleting chat
        // This ensures we don't have orphaned sessions that could cause security issues
        if let userId = chat.otherUser?.id {
            CryptoManager.shared.archiveSession(for: userId, reason: .manualReset)
            Log.info("🗑️ Archived crypto session for user: \(userId)", category: "ChatManagementService")
        }
        
        // Delete the chat (Core Data cascade rules will delete associated messages)
        context.delete(chat)
        
        do {
            try context.save()
            Log.info("✅ Chat deleted successfully: \(chatId)", category: "ChatManagementService")
            
            // Notify via callback
            onChatDeleted?(chatId)
        } catch {
            Log.error("❌ Failed to delete chat: \(error)", category: "ChatManagementService")
        }
    }
}
