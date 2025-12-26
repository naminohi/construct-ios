//
//  NewChatView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var chatsViewModel: ChatsViewModel

    @State private var searchQuery = ""
    @State private var selectedChat: Chat?

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search users...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: searchQuery) { newValue in
                        chatsViewModel.searchUsers(query: newValue)
                    }

                if chatsViewModel.isSearching {
                    ProgressView()
                        .padding()
                }

                List(chatsViewModel.searchResults, id: \.id) { user in
                    Button {
                        if let chat = chatsViewModel.startChat(with: user) {
                            selectedChat = chat
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
