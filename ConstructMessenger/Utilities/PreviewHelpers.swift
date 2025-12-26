//
//  PreviewHelpers.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 14.12.2025.
//

import Foundation
import CoreData
import SwiftUI

struct PreviewHelpers {
    /// Creates an in-memory CoreData stack for SwiftUI previews
    static func createPreviewContainer() -> NSPersistentContainer {
        // Try to load model from bundle explicitly
        let container: NSPersistentContainer

        if let modelURL = Bundle.main.url(forResource: "ConstructMessenger", withExtension: "momd"),
           let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) {
            print("✅ Loading CoreData model from bundle")
            container = NSPersistentContainer(name: "ConstructMessenger", managedObjectModel: managedObjectModel)
        } else {
            print("⚠️ Fallback: Loading CoreData model by name")
            container = NSPersistentContainer(name: "ConstructMessenger")
        }

        // Use in-memory store for preview
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("⚠️ Preview CoreData Error: \(error), \(error.userInfo)")
                loadError = error
            } else {
                print("✅ Preview CoreData loaded successfully")
            }
            semaphore.signal()
        }

        // Wait for store to load
        _ = semaphore.wait(timeout: .now() + 5)

        if let error = loadError {
            fatalError("Failed to load preview CoreData: \(error)")
        }

        return container
    }

    /// Creates sample User for preview
    static func createSampleUser(context: NSManagedObjectContext, id: String = "user1", username: String = "john_doe", displayName: String = "John Doe") -> User {
        let user = User(context: context)
        user.id = id
        user.username = username
        user.displayName = displayName
        user.publicKey = "sample_public_key"
        return user
    }

    /// Creates sample Chat for preview
    static func createSampleChat(context: NSManagedObjectContext, with user: User? = nil) -> Chat {
        let chat = Chat(context: context)
        chat.id = UUID().uuidString
        chat.lastMessageText = "Hello! How are you?"
        chat.lastMessageTime = Date()

        if let user = user {
            chat.otherUser = user
        } else {
            chat.otherUser = createSampleUser(context: context)
        }

        return chat
    }

    /// Creates sample Message for preview
    static func createSampleMessage(context: NSManagedObjectContext, chat: Chat, isSentByMe: Bool = false, text: String = "Sample message") -> Message {
        let message = Message(context: context)
        message.id = UUID().uuidString
        message.fromUserId = isSentByMe ? "me" : "other"
        message.toUserId = isSentByMe ? "other" : "me"
        message.encryptedContent = "encrypted_\(text)"
        message.decryptedContent = text
        message.timestamp = Date()
        message.isSentByMe = isSentByMe
        message.deliveryStatus = .delivered
        message.retryCount = 0
        message.chat = chat
        return message
    }
}
