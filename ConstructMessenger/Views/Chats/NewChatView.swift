//
//  NewChatView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI
import CoreData

// ✅ Privacy-focused contact addition
// Global user search was removed for security reasons:
// - Prevents enumeration attacks
// - No metadata leakage about who searches for whom
// - Users control who can add them (QR-code/link sharing only)

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var chatsViewModel: ChatsViewModel

    @State private var showingQRScanner = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var initialContactInfo: ContactInfo?

    init(chatsViewModel: ChatsViewModel, initialContactInfo: ContactInfo? = nil) {
        self.chatsViewModel = chatsViewModel
        _initialContactInfo = State(initialValue: initialContactInfo)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                
            }
            .navigationTitle("new_contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingQRScanner) {
                QRScannerView { contactURL in
                    handleScannedContact(contactURL)
                }
            }
            .alert("error", isPresented: $showingError) {
                Button("ok") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if let contactInfo = initialContactInfo {
                    addContact(userId: contactInfo.userId, username: contactInfo.username)
                    initialContactInfo = nil // Consume the deep link
                }
            }
        }
    }

    private func handleScannedContact(_ urlString: String) {
        print("🔍 NewChatView: Handling scanned URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            // TODO: Show alert to user
            return
        }

        Task {
            do {
                let contactInfo = try await LinkParser.parseContactLink(url)
                print("✅ Parsed contact: userId=\(contactInfo.userId), username=\(contactInfo.username), isDynamic=\(contactInfo.isDynamic)")
                
                await MainActor.run {
                    addContact(userId: contactInfo.userId, username: contactInfo.username)
                    showingQRScanner = false
                    dismiss()
                }
            } catch {
                print("❌ Failed to parse contact link: \(error.localizedDescription)")
                // TODO: Show alert to user with specific error message
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    // Keep scanner closed but show error
                    showingQRScanner = false
                }
            }
        }
    }

    private func addContact(userId: String, username: String) {
        print("📱 NewChatView: Adding contact userId=\(userId), username=\(username)")

        // Start chat with user - let ChatsViewModel handle User creation
        let publicUserInfo = PublicUserInfo(
            id: userId,
            username: username,
            avatarUrl: nil,
            bio: nil
        )
        if let chat = chatsViewModel.startChat(with: publicUserInfo) {
            print("✅ NewChatView: Chat created with @\(username), chat.id=\(chat.id), chat.otherUser?.id=\(chat.otherUser?.id ?? "nil")")
        } else {
            print("❌ NewChatView: Failed to create chat with @\(username)")
        }
    }
}
