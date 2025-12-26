//
//  ChatView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI
import CoreData

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var viewModel: ChatViewModel
    @State private var messageText = ""

    init(chat: Chat) {
        self.viewModel = ChatViewModel(chat: chat)
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionStatusBanner()

            if viewModel.isSending {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Sending...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message) { msg in
                                viewModel.retryMessage(msg)
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if AppConstants.enableDebugLogging {
                        print("ChatView appeared with \(viewModel.messages.count) messages")
                    }
                }
                .onChange(of: viewModel.messages.count) { count in
                    if AppConstants.enableDebugLogging {
                        print("ChatView: messages count changed to \(count)")
                    }
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            MessageInputView(
                text: $messageText,
                isSending: viewModel.isSending,
                onSend: {
                    viewModel.sendMessage(text: messageText)
                    messageText = ""
                }
            )
        }
        .navigationTitle(viewModel.chat.otherUser?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setContext(viewContext)
        }
    }
}

#Preview {
    let container = PreviewHelpers.createPreviewContainer()
    let context = container.viewContext

    // Create sample data
    let user = PreviewHelpers.createSampleUser(context: context, username: "alice", displayName: "Alice")
    let chat = PreviewHelpers.createSampleChat(context: context, with: user)

    // Add sample messages
    _ = PreviewHelpers.createSampleMessage(context: context, chat: chat, isSentByMe: false, text: "Hi! How are you?")
    _ = PreviewHelpers.createSampleMessage(context: context, chat: chat, isSentByMe: true, text: "I'm good, thanks!")
    _ = PreviewHelpers.createSampleMessage(context: context, chat: chat, isSentByMe: false, text: "Great to hear!")

    try? context.save()

    return NavigationStack {
        ChatView(chat: chat)
            .environment(\.managedObjectContext, context)
    }
}

