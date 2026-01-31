//
//  MediaManager.swift
//  Construct Messenger
//
//  Unified manager for all media operations (upload, download, thumbnails)
//  Extracted from MediaUploadService + ChatsViewModel + ChatViewModel
//  Created on 2026-01-31 (Phase 1.2 Refactoring)
//

import Foundation
import UIKit
import CryptoKit

/// Unified manager for all media operations
@MainActor
class MediaManager {
    
    // MARK: - Singleton
    
    static let shared = MediaManager()
    
    private init() {}
    
    // MARK: - Upload Operations
    
    /// Upload image for chat message
    /// - Parameters:
    ///   - image: UIImage to upload
    ///   - recipientId: User ID to encrypt media key for
    /// - Returns: Media metadata for message content
    func uploadImage(_ image: UIImage, for recipientId: String) async throws -> MediaMessageData {
        Log.info("📤 Uploading image for recipient: \(recipientId)", category: "MediaManager")
        
        // Use MediaAPI to handle compression + encryption + upload
        let uploadResult = try await MediaAPI.shared.uploadImage(image, quality: 0.8)
        Log.info("✅ Image uploaded: \(uploadResult.mediaId)", category: "MediaManager")
        
        // Encrypt media key for recipient using Double Ratchet
        let encryptedMediaKey = try CryptoManager.shared.encryptMediaKey(
            mediaKey: uploadResult.encryptionKey,
            for: recipientId
        )
        
        // Extract image dimensions
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        return MediaMessageData(
            mediaId: uploadResult.mediaId,
            mediaUrl: uploadResult.mediaUrl,
            mediaKey: encryptedMediaKey,
            mediaType: uploadResult.mimeType,
            size: uploadResult.encryptedData.count,
            width: width,
            height: height,
            duration: nil,
            thumbnail: nil,
            hash: uploadResult.hash
        )
    }
    
    /// Upload avatar image (profile sharing)
    /// - Parameter image: Avatar image to upload
    /// - Returns: Avatar upload result with raw encryption key
    func uploadAvatar(_ image: UIImage) async throws -> AvatarUploadResult {
        Log.info("📤 Uploading avatar", category: "MediaManager")
        
        // Use MediaAPI to handle compression + encryption + upload
        let uploadResult = try await MediaAPI.shared.uploadImage(image, quality: 0.8)
        Log.info("✅ Avatar uploaded: \(uploadResult.mediaId)", category: "MediaManager")
        
        // For avatars, return raw base64 key (not Double Ratchet encrypted)
        // The entire profile message will be encrypted with Double Ratchet
        let keyBase64 = uploadResult.encryptionKey.base64EncodedString()
        
        return AvatarUploadResult(
            mediaUrl: uploadResult.mediaUrl,
            encryptionKey: keyBase64,  // Raw base64 key
            mediaId: uploadResult.mediaId,
            hash: uploadResult.hash
        )
    }
    
    // MARK: - Download Operations
    
    /// Download and decrypt media (generic)
    /// - Parameters:
    ///   - mediaUrl: URL to download encrypted media from
    ///   - mediaKeyBase64: Base64-encoded encryption key (raw AES key)
    /// - Returns: Decrypted media data
    func downloadAndDecryptMedia(mediaUrl: String, mediaKeyBase64: String) async throws -> Data {
        Log.info("📥 Downloading media from: \(mediaUrl)", category: "MediaManager")
        
        // Decode media key
        guard let keyData = Data(base64Encoded: mediaKeyBase64) else {
            throw MediaManagerError.invalidMediaKey
        }
        
        // Download encrypted data via MediaAPI
        let encryptedData = try await MediaAPI.shared.downloadEncryptedFile(from: mediaUrl)
        
        // Decrypt using CryptoManager
        let decryptedData = try CryptoManager.shared.decryptMediaData(encryptedData, with: keyData)
        
        Log.info("✅ Media decrypted: \(decryptedData.count) bytes", category: "MediaManager")
        return decryptedData
    }
    
    /// Download and decrypt avatar (profile sharing)
    /// - Parameters:
    ///   - mediaUrl: URL to download encrypted avatar from
    ///   - mediaKeyBase64: Base64-encoded encryption key (raw AES key)
    /// - Returns: Decrypted avatar image data
    func downloadAndDecryptAvatar(mediaUrl: String, mediaKeyBase64: String) async throws -> Data {
        Log.info("📥 Downloading avatar from: \(mediaUrl)", category: "MediaManager")
        
        // Decode media key
        guard let keyData = Data(base64Encoded: mediaKeyBase64) else {
            throw MediaManagerError.invalidMediaKey
        }
        
        // Download encrypted data
        guard let url = URL(string: mediaUrl) else {
            throw MediaManagerError.invalidURL
        }
        
        let (encryptedData, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MediaManagerError.downloadFailed(statusCode)
        }
        
        // Decrypt using CryptoManager
        let decryptedData = try CryptoManager.shared.decryptMediaData(encryptedData, with: keyData)
        
        Log.info("✅ Avatar decrypted: \(decryptedData.count) bytes", category: "MediaManager")
        return decryptedData
    }
    
    // MARK: - Thumbnail Operations
    
    /// Generate thumbnail from UIImage
    /// - Parameters:
    ///   - image: Source image
    ///   - maxSize: Maximum dimension (width or height)
    /// - Returns: Thumbnail image data (JPEG)
    func generateThumbnail(from image: UIImage, maxSize: CGFloat = 250) -> Data? {
        Log.debug("🖼️ Generating thumbnail (maxSize: \(maxSize))", category: "MediaManager")
        
        do {
            let optimized = try MediaOptimizer.generateThumbnail(from: image)
            Log.debug("✅ Thumbnail generated: \(optimized.count) bytes", category: "MediaManager")
            return optimized
        } catch {
            Log.error("❌ Failed to generate thumbnail: \(error)", category: "MediaManager")
            return nil
        }
    }
    
    /// Generate thumbnail from Data
    /// - Parameters:
    ///   - data: Image data
    ///   - maxSize: Maximum dimension (width or height)
    /// - Returns: Thumbnail image data (JPEG)
    func generateThumbnail(from data: Data, maxSize: CGFloat = 250) -> Data? {
        guard let image = UIImage(data: data) else {
            Log.error("❌ Failed to create UIImage from data", category: "MediaManager")
            return nil
        }
        
        return generateThumbnail(from: image, maxSize: maxSize)
    }
    
    /// Generate thumbnail with custom UIImage renderer (for MessageBubble compatibility)
    /// - Parameters:
    ///   - image: Source image
    ///   - maxSize: Maximum dimension
    /// - Returns: Thumbnail UIImage
    func generateThumbnailImage(from image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let scale: CGFloat
        
        if size.width > size.height {
            scale = maxSize / size.width
        } else {
            scale = maxSize / size.height
        }
        
        let thumbnailSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
    }
    
    // MARK: - Thumbnail Storage (UserDefaults - temporary solution)
    
    /// Store thumbnail locally for message
    /// - Parameters:
    ///   - thumbnailData: Thumbnail image data
    ///   - messageId: Message ID to associate with
    func storeThumbnail(_ thumbnailData: Data, for messageId: String) {
        UserDefaults.standard.set(thumbnailData, forKey: "message_thumbnail_\(messageId)")
        Log.debug("💾 Stored thumbnail for message: \(messageId)", category: "MediaManager")
    }
    
    /// Retrieve stored thumbnail for message
    /// - Parameter messageId: Message ID
    /// - Returns: Thumbnail data if exists
    func retrieveThumbnail(for messageId: String) -> Data? {
        return UserDefaults.standard.data(forKey: "message_thumbnail_\(messageId)")
    }
    
    /// Remove stored thumbnail for message
    /// - Parameter messageId: Message ID
    func removeThumbnail(for messageId: String) {
        UserDefaults.standard.removeObject(forKey: "message_thumbnail_\(messageId)")
    }
}

// MARK: - Supporting Types

/// Result of avatar upload
struct AvatarUploadResult {
    let mediaUrl: String
    let encryptionKey: String  // Raw base64 key (not Double Ratchet encrypted)
    let mediaId: String
    let hash: String
}

/// Media manager errors
enum MediaManagerError: LocalizedError {
    case invalidMediaKey
    case invalidURL
    case downloadFailed(Int)  // HTTP status code
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidMediaKey:
            return "Invalid media encryption key"
        case .invalidURL:
            return "Invalid media URL"
        case .downloadFailed(let statusCode):
            return "Download failed with HTTP \(statusCode)"
        case .decryptionFailed:
            return "Failed to decrypt media"
        }
    }
}
