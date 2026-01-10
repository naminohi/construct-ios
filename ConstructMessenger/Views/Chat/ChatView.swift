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
    @StateObject private var viewModel: ChatViewModel  // ✅ FIX: StateObject persists across view updates
    @State private var messageText = ""
    @State private var replyingTo: Message?
    @State private var showingUserProfile = false
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var hasScrolledToBottom = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isEditMode = false
    @State private var selectedMessages: Set<String> = []

    init(chat: Chat, context: NSManagedObjectContext) {
        // ✅ FIX: Use StateObject initializer to create ViewModel only once
        _viewModel = StateObject(wrappedValue: ChatViewModel(chat: chat, context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 0) {
                                MessageBubble(
                                    message: message,
                                    isLastInGroup: isLastInGroup(message, at: index, in: filteredMessages),
                                    isSelected: selectedMessages.contains(message.id),
                                    isEditMode: isEditMode,
                                    onRetry: { msg in
                                        viewModel.retryMessage(msg)
                                    },
                                    onReply: { msg in
                                        replyingTo = msg
                                    },
                                    onDelete: { msg in
                                        deleteMessage(msg)
                                    },
                                    onSelect: { msg in
                                        toggleMessageSelection(msg)
                                    },
                                    onEnterSelectMode: { msg in
                                        withAnimation {
                                            isEditMode = true
                                            isSearchActive = false
                                            searchText = ""
                                            // Автоматически выделить сообщение, на которое нажали
                                            selectedMessages.insert(msg.id)
                                        }
                                    }
                                )
                                .id(message.id)

                                // Add spacing after each message
                                if index < filteredMessages.count - 1 {
                                    Spacer()
                                        .frame(height: spacingAfterMessage(at: index, in: filteredMessages))
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        GeometryReader { geometry in
                            Color.clear.onAppear {
                                // Store proxy for later use
                                scrollProxy = proxy
                            }
                        }
                    )
                }
                .onAppear {
                    scrollProxy = proxy
                    if AppConstants.enableDebugLogging {
                        print("ChatView appeared with \(viewModel.messages.count) messages")
                    }
                    // Reset scroll state when view appears
                    hasScrolledToBottom = false
                    // Scroll to bottom on first appear if we have messages
                    // Use multiple attempts to ensure scroll happens even if messages load asynchronously
                    scrollToBottomIfNeeded(proxy: proxy, delay: 0.3)
                    scrollToBottomIfNeeded(proxy: proxy, delay: 0.6)
                }
                .onChange(of: viewModel.messages.count) { count in
                    if AppConstants.enableDebugLogging {
                        print("ChatView: messages count changed to \(count)")
                    }
                    // Scroll to bottom when messages are first loaded
                    if !hasScrolledToBottom && !isSearchActive && !viewModel.messages.isEmpty {
                        // First load - scroll to bottom
                        scrollToBottomIfNeeded(proxy: proxy, delay: 0.2)
                    } else if hasScrolledToBottom && !isSearchActive && !viewModel.messages.isEmpty {
                        // New message arrived - scroll to bottom (only if we were already at bottom)
                        scrollToBottomIfNeeded(proxy: proxy, delay: 0.1)
                    }
                }
                .onChange(of: searchText) { newValue in
                    // When search changes, scroll to first matching message
                    if !newValue.isEmpty, !filteredMessages.isEmpty, let firstMatch = filteredMessages.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(firstMatch.id, anchor: .center)
                            }
                        }
                    } else if newValue.isEmpty {
                        // When search is cleared, scroll back to bottom
                        hasScrolledToBottom = false
                        scrollToBottomIfNeeded(proxy: proxy, delay: 0.1)
                    }
                }
                .onChange(of: isSearchActive) { active in
                    if active {
                        // When search is activated, exit edit mode
                        if isEditMode {
                            isEditMode = false
                            selectedMessages.removeAll()
                        }
                    } else {
                        // When search is dismissed, scroll back to bottom
                        searchText = ""
                        hasScrolledToBottom = false
                        scrollToBottomIfNeeded(proxy: proxy, delay: 0.1)
                    }
                }
                .onChange(of: isEditMode) { editMode in
                    if editMode {
                        // When edit mode is activated, exit search
                        if isSearchActive {
                            isSearchActive = false
                            searchText = ""
                        }
                    }
                }
            }
            
            deleteButtonBar
            
            messageInputView
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: toolbarContent)
        .overlay(alignment: .top, content: searchOverlay)
        .sheet(isPresented: $showingUserProfile) {
            if let user = viewModel.chat.otherUser {
                UserProfileView(user: user)
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.isSending {
            statusBannerRow(text: "sending", color: .secondary)
        } else if !viewModel.isSessionReady {
            statusBannerRow(text: "initializing_secure_connection", color: .orange, showProgress: true)
        } else if !WebSocketManager.shared.isConnected {
            statusBannerRow(text: "not_connected_to_server", color: .red)
        }
    }
    
    @ViewBuilder
    private func statusBannerRow(text: String, color: Color, showProgress: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showProgress {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(color)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
    }
    
    @ViewBuilder
    private var deleteButtonBar: some View {
        if isEditMode && !selectedMessages.isEmpty {
            HStack {
                Button(role: .destructive) {
                    deleteSelectedMessages()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("delete_selected")
                    }
                    .foregroundColor(.red)
                }
                Spacer()
                Text("\(selectedMessages.count) \(selectedMessages.count == 1 ? "message_selected" : "messages_selected")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
        }
    }
    
    private var messageInputView: some View {
        MessageInputView(
            text: $messageText,
            isSending: viewModel.isSending,
            replyingTo: replyingTo,
            onSend: {
                viewModel.sendMessage(text: messageText, replyTo: replyingTo)
                messageText = ""
                replyingTo = nil
            },
            onCancelReply: {
                replyingTo = nil
            }
        )
        .disabled(isEditMode)
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                showingUserProfile = true
            } label: {
                VStack(spacing: 2) {
                    Text(viewModel.chat.otherUser?.displayName ?? NSLocalizedString("chat", comment: "Default chat title"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let username = viewModel.chat.otherUser?.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            toolbarTrailingButtons
        }
    }
    
    @ViewBuilder
    private var toolbarTrailingButtons: some View {
        HStack(spacing: 12) {
            if !isEditMode {
                Button {
                    withAnimation {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
                }
            }
            
            if isEditMode {
                Button {
                    withAnimation {
                        isEditMode = false
                        selectedMessages.removeAll()
                    }
                } label: {
                    Text("done")
                }
            }
        }
    }
    
    @ViewBuilder
    private func searchOverlay() -> some View {
        if isSearchActive {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TextField("search_messages", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    Button {
                        withAnimation {
                            isSearchActive = false
                            searchText = ""
                        }
                    } label: {
                        Text("cancel")
                    }
                }
                .padding()
                .background(Color(.systemBackground).shadow(color: .black.opacity(0.1), radius: 2, y: 1))
                Spacer()
            }
        }
    }

    // MARK: - Computed Properties
    
    private var filteredMessages: [Message] {
        if searchText.isEmpty {
            return viewModel.messages
        }
        return viewModel.messages.filter { message in
            message.decryptedContent?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    // MARK: - Actions
    
    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, delay: TimeInterval) {
        guard !isSearchActive, !viewModel.messages.isEmpty else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let lastMessage = viewModel.messages.last {
                withAnimation(.easeOut(duration: delay > 0.2 ? 0.3 : 0.2)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
                if !hasScrolledToBottom {
                    hasScrolledToBottom = true
                }
            }
        }
    }

    private func deleteMessage(_ message: Message) {
        viewContext.delete(message)
        do {
            try viewContext.save()
            Log.info("✅ Message deleted: \(message.id)", category: "ChatView")
        } catch {
            Log.error("❌ Failed to delete message: \(error)", category: "ChatView")
        }
    }
    
    private func toggleMessageSelection(_ message: Message) {
        if selectedMessages.contains(message.id) {
            selectedMessages.remove(message.id)
        } else {
            selectedMessages.insert(message.id)
        }
    }
    
    private func deleteSelectedMessages() {
        guard !selectedMessages.isEmpty else { return }
        
        for messageId in selectedMessages {
            let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", messageId)
            
            if let message = try? viewContext.fetch(fetchRequest).first {
                viewContext.delete(message)
            }
        }
        
        do {
            try viewContext.save()
            Log.info("✅ Deleted \(selectedMessages.count) messages", category: "ChatView")
            withAnimation {
                selectedMessages.removeAll()
                isEditMode = false
            }
        } catch {
            Log.error("❌ Failed to delete selected messages: \(error)", category: "ChatView")
        }
    }

    // MARK: - Message Grouping Logic

    /// Determines if a message is the last in a group of consecutive messages from the same sender
    private func isLastInGroup(_ message: Message, at index: Int, in messages: [Message]) -> Bool {
        // If this is the last message, it's always the last in its group
        guard index < messages.count - 1 else {
            return true
        }

        let nextMessage = messages[index + 1]

        // Different sender = end of group
        if message.isSentByMe != nextMessage.isSentByMe {
            return true
        }

        // If more than 5 minutes apart, start a new group
        let timeDifference = nextMessage.timestamp.timeIntervalSince(message.timestamp)
        if timeDifference > 300 { // 5 minutes
            return true
        }

        return false
    }

    /// Returns appropriate spacing after a message
    private func spacingAfterMessage(at index: Int, in messages: [Message]) -> CGFloat {
        let message = messages[index]

        // If this is the last in group, use larger spacing
        if isLastInGroup(message, at: index, in: messages) {
            return 12
        }

        // Otherwise, use compact spacing within the group
        return 4
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
        ChatView(chat: chat, context: context)
            .environment(\.managedObjectContext, context)
    }
}

