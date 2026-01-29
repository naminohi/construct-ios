//
//  MessageBubble.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isLastInGroup: Bool
    let isSelected: Bool
    let isEditMode: Bool
    let onRetry: ((Message) -> Void)?
    let onReply: ((Message) -> Void)?
    let onDelete: ((Message) -> Void)?
    let onSelect: ((Message) -> Void)?
    let onEnterSelectMode: ((Message) -> Void)?

    @State private var showMessageInfo = false

    init(
        message: Message,
        isLastInGroup: Bool = true,
        isSelected: Bool = false,
        isEditMode: Bool = false,
        onRetry: ((Message) -> Void)? = nil,
        onReply: ((Message) -> Void)? = nil,
        onDelete: ((Message) -> Void)? = nil,
        onSelect: ((Message) -> Void)? = nil,
        onEnterSelectMode: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.isLastInGroup = isLastInGroup
        self.isSelected = isSelected
        self.isEditMode = isEditMode
        self.onRetry = onRetry
        self.onReply = onReply
        self.onDelete = onDelete
        self.onSelect = onSelect
        self.onEnterSelectMode = onEnterSelectMode
    }

    var body: some View {
        // ✅ Check if this is a system message by fromUserId
        if message.fromUserId == "SYSTEM" {
            systemMessageView(message.decryptedContent ?? "System message")
        } else if let content = message.decryptedContent, content.hasPrefix("[SYSTEM]") {
            // ✅ Legacy support for [SYSTEM] prefix
            systemMessageView(content.replacingOccurrences(of: "[SYSTEM]", with: "").trimmingCharacters(in: .whitespaces))
        } else {
            regularMessageView
        }
    }
    
    // MARK: - System Message View
    private func systemMessageView(_ content: String) -> some View {
        HStack {
            Spacer()
            Text(content)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Regular Message View
    private var regularMessageView: some View {
        HStack(spacing: 8) {
            // Selection checkbox in edit mode
            if isEditMode {
                Button {
                    onSelect?(message)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            if message.isSentByMe {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isSentByMe ? .trailing : .leading, spacing: 4) {
                // ✅ Check if this is a profile share message
                if let content = message.decryptedContent,
                   let profileData = parseProfileMessage(content) {
                    // Display profile card
                    ProfileShareBubbleView(profileData: profileData)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                }
                // ✅ Check if this is a media message
                else if let mediaContent = parseMediaMessage(message.decryptedContent) {
                    // Display media message without bubble - just rounded corners
                    MediaMessageView(mediaContent: mediaContent, message: message, isSelected: isSelected)
                } else {
                    // Regular text message with bubble
                    VStack(alignment: .leading, spacing: 0) {
                        // Reply/Quote preview
                        if let replyContent = message.replyToContent {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(message.isSentByMe ? Color.white.opacity(0.5) : Color.blue.opacity(0.5))
                                    .frame(width: 3)

                                Text(replyContent)
                                    .font(.caption)
                                    .foregroundColor(message.isSentByMe ? .white.opacity(0.8) : .secondary)
                                    .lineLimit(2)
                                    .padding(.vertical, 4)
                                    .padding(.trailing, 8)
                            }
                            .padding(.leading, 8)
                            .padding(.top, 8)
                        }

                        // Main message content
                        Text(message.decryptedContent ?? NSLocalizedString("encrypted", comment: "Fallback for encrypted content"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, message.replyToContent != nil ? 4 : 8)
                            .padding(.bottom, message.replyToContent != nil ? 8 : 0)
                    }
                    .background(message.isSentByMe ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.isSentByMe ? .white : .primary)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }

                if isLastInGroup {
                    HStack(spacing: 4) {
                        if message.isSentByMe {
                            deliveryStatusView
                        }

                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: message.isSentByMe ? .trailing : .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditMode {
                    onSelect?(message)
                }
            }

            if !message.isSentByMe {
                Spacer(minLength: 60)
            }
        }
        .contextMenu {
            // Context menu only available when not in edit mode
            if !isEditMode {
                // Reply - только для чужих сообщений или если есть callback
                if let onReply = onReply {
                    Button {
                        onReply(message)
                    } label: {
                        Label("reply", systemImage: "arrowshape.turn.up.left")
                    }
                }

                // Copy text
                Button {
                    UIPasteboard.general.string = message.decryptedContent
                } label: {
                    Label("copy", systemImage: "doc.on.doc")
                }
                
                // Select messages - включить режим выбора нескольких сообщений
                if let onEnterSelectMode = onEnterSelectMode {
                    Button {
                        // Включаем режим выбора и автоматически выделяем это сообщение
                        onEnterSelectMode(message)
                    } label: {
                        Label("select_messages", systemImage: "checkmark.circle")
                    }
                }

                // Message info - только для debug режима
                // ⚠️ SECURITY: This code is completely removed in Release builds via #if DEBUG
                #if DEBUG
                Button {
                    showMessageInfo = true
                } label: {
                    Label("info", systemImage: "info.circle")
                }
                #endif

                Divider()

                // Delete - теперь можно удалять любые сообщения (локально)
                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete(message)
                    } label: {
                        Label("delete", systemImage: "trash")
                    }
                }

                // Retry - только для failed/queued сообщений
                if (message.deliveryStatus == .failed || message.deliveryStatus == .queued),
                   let onRetry = onRetry {
                    Button {
                        onRetry(message)
                    } label: {
                        Label("retry", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        #if DEBUG
        .sheet(isPresented: $showMessageInfo) {
            MessageInfoSheet(message: message)
        }
        #endif
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        let status = message.deliveryStatus

        switch status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)

        case .sent:
            // Один серый чекмарк - сообщение на сервере, но получатель может быть оффлайн
            HStack(spacing: 1) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 14, height: 10)

        case .delivered:
            // Два зеленых чекмарка - сообщение доставлено получателю
            HStack(spacing: -8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .opacity(0.8)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
            }
            .frame(width: 14, height: 10)

        case .queued:
            Button {
                if let onRetry = onRetry {
                    onRetry(message)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "tray")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("retry")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

        case .failed:
            Button {
                if let onRetry = onRetry {
                    onRetry(message)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text("retry")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Media Message Parsing
    
    private func parseProfileMessage(_ content: String) -> ProfileShareData? {
        guard let data = content.data(using: .utf8) else { return nil }
        
        // Check if it looks like a profile message
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = jsonDict["type"] as? String,
           type == "profile" {
            // Try to decode it properly
            return try? JSONDecoder().decode(ProfileShareData.self, from: data)
        }
        return nil
    }
    
    private func parseMediaMessage(_ content: String?) -> MediaMessageContent? {
        guard let content = content,
              let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "media",
              let mediaArray = json["media"] as? [[String: Any]],
              let firstMedia = mediaArray.first else {
            return nil
        }
        
        return MediaMessageContent(
            caption: json["caption"] as? String ?? "",
            media: firstMedia
        )
    }
}

// MARK: - Profile Share Bubble View
struct ProfileShareBubbleView: View {
    let profileData: ProfileShareData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar placeholder or image
                if let avatarData = profileData.avatarData,
                   let imageData = Data(base64Encoded: avatarData),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(profileData.displayName.prefix(1)).uppercased())
                                .font(.title2)
                                .foregroundColor(.blue)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(profileData.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Shared profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Media Message Content
struct MediaMessageContent {
    let caption: String
    let media: [String: Any]
}

// MARK: - Media Message View
struct MediaMessageView: View {
    let mediaContent: MediaMessageContent
    let message: Message
    let isSelected: Bool
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail or placeholder - no bubble, just rounded corners
            if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 250, maxHeight: 250)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .overlay {
                        ProgressView()
                    }
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            }
            
            // Caption if present - displayed below image without bubble
            if !mediaContent.caption.isEmpty {
                Text(mediaContent.caption)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        // ✅ For sender: try to load from local storage
        if message.isSentByMe {
            if let thumbnailData = UserDefaults.standard.data(forKey: "message_thumbnail_\(message.id)"),
               let image = UIImage(data: thumbnailData) {
                thumbnailImage = image
                return
            }
        }
        
        // ✅ For receiver: download and decrypt media
        guard let mediaId = mediaContent.media["mediaId"] as? String,
              let mediaUrl = mediaContent.media["mediaUrl"] as? String,
              let mediaKeyBase64 = mediaContent.media["mediaKey"] as? String else {
            Log.error("❌ Missing media info in message", category: "MediaMessage")
            isLoading = false
            return
        }
        
        isLoading = true
        
        Task {
            do {
                Log.info("📥 Downloading media: \(mediaId)", category: "MediaMessage")
                
                // Download and decrypt (mediaKeyBase64 is String, not Data)
                let imageData = try await MediaUploadService.shared.downloadAndDecryptMedia(
                    mediaUrl: mediaUrl,
                    mediaKeyBase64: mediaKeyBase64
                )
                
                guard let image = UIImage(data: imageData) else {
                    Log.error("❌ Failed to decode image data", category: "MediaMessage")
                    await MainActor.run {
                        isLoading = false
                    }
                    return
                }
                
                // Generate thumbnail
                let thumbnail = generateThumbnail(from: image, maxSize: 250)
                
                await MainActor.run {
                    thumbnailImage = thumbnail
                    isLoading = false
                    Log.info("✅ Media loaded successfully", category: "MediaMessage")
                }
                
            } catch {
                Log.error("❌ Failed to load media: \(error.localizedDescription)", category: "MediaMessage")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func generateThumbnail(from image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let thumbnailSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
    }
}
