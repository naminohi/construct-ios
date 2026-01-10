//
//  ProfileShareViewModel.swift
//  Construct Messenger
//
//  ViewModel for managing profile data sharing
//

import Foundation
import CoreData
import Combine

@MainActor
class ProfileShareViewModel: ObservableObject {
    private var viewContext: NSManagedObjectContext?
    private let wsManager = WebSocketManager.shared
    
    func setContext(_ context: NSManagedObjectContext) {
        self.viewContext = context
    }
    
    /// Share profile (displayName and avatar) with another user via E2E encrypted message
    func shareProfile(with userId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let context = viewContext,
              let currentUserId = SessionManager.shared.currentUserId else {
            completion(false, NSLocalizedString("not_authenticated", comment: ""))
            return
        }
        
        // Get current user's profile data
        let userFetchRequest: NSFetchRequest<User> = User.fetchRequest()
        userFetchRequest.predicate = NSPredicate(format: "id == %@", currentUserId)
        
        guard let currentUser = try? context.fetch(userFetchRequest).first else {
            completion(false, NSLocalizedString("user_not_found", comment: ""))
            return
        }
        
        // Prepare profile data
        var avatarDataBase64: String? = nil
        if let avatarData = currentUser.avatarData {
            avatarDataBase64 = avatarData.base64EncodedString()
        }
        
        let profileData = ProfileShareData(
            displayName: currentUser.displayName,
            avatarData: avatarDataBase64,
            timestamp: Int64(Date().timeIntervalSince1970)
        )
        
        // Serialize to JSON
        guard let jsonData = try? JSONEncoder().encode(profileData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(false, NSLocalizedString("failed_to_encode_profile", comment: ""))
            return
        }
        
        // Encrypt and send via E2E message
        do {
            let encryptedComponents = try CryptoManager.shared.encryptMessage(jsonString, for: userId)
            
            let message = ChatMessage(
                id: UUID().uuidString,
                from: currentUserId,
                to: userId,
                ephemeralPublicKey: encryptedComponents.ephemeralPublicKey,
                messageNumber: encryptedComponents.messageNumber,
                content: encryptedComponents.content,
                timestamp: UInt64(Date().timeIntervalSince1970)
            )
            
            wsManager.send(.sendMessage(message))
            
            Log.info("✅ Profile shared with user \(userId)", category: "ProfileShare")
            completion(true, nil)
        } catch {
            Log.error("❌ Failed to share profile: \(error)", category: "ProfileShare")
            completion(false, error.localizedDescription)
        }
    }
    
    /// Handle received profile data from another user
    func handleReceivedProfile(_ profileData: ProfileShareData, from userId: String) {
        guard let context = viewContext else { return }
        
        let userFetchRequest: NSFetchRequest<User> = User.fetchRequest()
        userFetchRequest.predicate = NSPredicate(format: "id == %@", userId)
        
        guard let user = try? context.fetch(userFetchRequest).first else {
            Log.error("❌ User not found for profile update: \(userId)", category: "ProfileShare")
            return
        }
        
        // Update user's display name
        user.displayName = profileData.displayName
        
        // Update avatar if provided
        if let avatarBase64 = profileData.avatarData,
           let avatarData = Data(base64Encoded: avatarBase64) {
            user.avatarData = avatarData
        }
        
        // Mark as sharing with us
        user.isSharingWithMe = true
        user.sharedWithMeAt = Date()
        
        do {
            try context.save()
            Log.info("✅ Profile data updated for user \(userId)", category: "ProfileShare")
        } catch {
            Log.error("❌ Failed to save profile data: \(error)", category: "ProfileShare")
        }
    }
}
