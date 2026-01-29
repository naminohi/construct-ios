//
//  MediaAPI.swift
//  Construct Messenger
//
//  Media upload/download API
//  Created on 26.01.2026 (Phase 2.1 refactoring)
//  Updated: 29.01.2026 - Full Media Upload API integration
//

import Foundation
import UIKit
import CryptoKit

/// Media upload and download endpoints
class MediaAPI {
    static let shared = MediaAPI()
    
    private let client = RestAPIClient.shared
    
    // ✅ Media Upload API is on messaging-service, not gateway
    private let messagingServiceURL = "https://construct-messaging-service.fly.dev"
    
    private init() {}
    
    // MARK: - Models
    
    struct UploadedMedia {
        let mediaId: String
        let mediaUrl: String
        let encryptionKey: Data  // Raw 32-byte key
        let encryptedData: Data  // Encrypted blob (for calculating hash)
        let hash: String  // SHA-256 hex of encrypted data
        let mimeType: String
        let expiresAt: Int
    }
    
    struct UploadResponse: Codable {
        let mediaId: String
        let expiresAt: Int
    }
    
    // MARK: - Step 1: Request Upload Token
    
    /// Request upload token for media
    /// POST /api/v1/media/token on messaging-service
    func requestMediaToken() async throws -> MediaTokenData {
        let endpoint = "\(messagingServiceURL)/api/v1/media/token"
        
        Log.info("📤 Requesting media upload token from messaging-service", category: "MediaAPI")
        
        // Get JWT token
        guard let token = SessionManager.shared.sessionToken else {
            throw NetworkError.serverError(message: "Not authenticated", responseBody: nil)
        }
        
        // Create request manually (bypass RestAPIClient fallback)
        guard let url = URL(string: endpoint) else {
            throw NetworkError.serverError(message: "Invalid URL", responseBody: nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(URL(string: messagingServiceURL)?.host ?? "construct-messaging-service.fly.dev", forHTTPHeaderField: "Host")
        request.httpBody = "{}".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(message: "Invalid response", responseBody: nil)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw NetworkError.serverError(message: "Server error (status: \(httpResponse.statusCode))", responseBody: body)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(MediaTokenResponse.self, from: data)
        
        Log.info("✅ Received upload token (expires: \(tokenResponse.expiresAt))", category: "MediaAPI")
        
        return MediaTokenData(
            requestId: tokenResponse.requestId ?? UUID().uuidString,
            uploadToken: tokenResponse.uploadToken,
            uploadUrl: tokenResponse.uploadUrl,
            maxFileSize: tokenResponse.maxFileSize,
            expiresAt: tokenResponse.expiresAt
        )
    }
    
    // MARK: - Step 2: Upload Encrypted File
    
    /// Upload encrypted file to media service
    /// - Parameters:
    ///   - encryptedData: Already encrypted file data
    ///   - token: Upload token from requestMediaToken()
    ///   - uploadUrl: Upload URL from token response
    /// - Returns: Media ID and expiration
    func uploadEncryptedFile(
        encryptedData: Data,
        token: String,
        uploadUrl: String
    ) async throws -> UploadResponse {
        guard let url = URL(string: uploadUrl) else {
            throw NetworkError.serverError(message: "Invalid upload URL", responseBody: nil)
        }
        
        Log.info("📤 Uploading encrypted file (\(encryptedData.count) bytes)", category: "MediaAPI")
        
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // 60 seconds for upload
        
        var body = Data()
        
        // Add token field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(token)\r\n".data(using: .utf8)!)
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"encrypted.bin\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(encryptedData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Perform upload
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(message: "Invalid response from upload server", responseBody: nil)
        }
        
        Log.info("📥 Upload response: \(httpResponse.statusCode)", category: "MediaAPI")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw NetworkError.serverError(message: "Unauthorized upload", responseBody: nil)
            } else if httpResponse.statusCode == 413 {
                throw NetworkError.serverError(message: "File too large (max 100MB)", responseBody: nil)
            } else if httpResponse.statusCode == 429 {
                throw NetworkError.serverError(message: "Rate limit exceeded (50 uploads/hour)", responseBody: nil)
            }
            throw NetworkError.serverError(message: "Upload failed: \(httpResponse.statusCode)", responseBody: nil)
        }
        
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        Log.info("✅ Upload successful: mediaId=\(uploadResponse.mediaId)", category: "MediaAPI")
        
        return uploadResponse
    }
    
    // MARK: - Step 3: Download File
    
    /// Download encrypted file from media service
    /// - Parameter mediaUrl: Full media URL (e.g., https://construct-media-service.fly.dev/{mediaId})
    /// - Returns: Encrypted file data
    func downloadEncryptedFile(from mediaUrl: String) async throws -> Data {
        guard let url = URL(string: mediaUrl) else {
            throw NetworkError.serverError(message: "Invalid media URL", responseBody: nil)
        }
        
        let mediaId = url.lastPathComponent
        Log.info("📥 Downloading media: \(mediaId)", category: "MediaAPI")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(message: "Invalid response from media server", responseBody: nil)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw NetworkError.serverError(message: "Media not found or expired", responseBody: nil)
            }
            throw NetworkError.serverError(message: "Download failed: \(httpResponse.statusCode)", responseBody: nil)
        }
        
        Log.info("✅ Downloaded \(data.count) bytes", category: "MediaAPI")
        return data
    }
    
    // MARK: - High-Level: Upload Image
    
    /// Complete workflow: Compress, encrypt, and upload an image
    /// - Parameters:
    ///   - image: UIImage to upload
    ///   - quality: JPEG compression quality (0.0-1.0), default 0.8
    /// - Returns: Upload metadata with encryption key
    func uploadImage(_ image: UIImage, quality: CGFloat = 0.8) async throws -> UploadedMedia {
        // 1. Compress to JPEG
        guard let imageData = image.jpegData(compressionQuality: quality) else {
            throw NetworkError.serverError(message: "Failed to compress image", responseBody: nil)
        }
        Log.info("📸 Image compressed: \(imageData.count) bytes (quality: \(quality))", category: "MediaAPI")
        
        return try await uploadData(imageData, mimeType: "image/jpeg")
    }
    
    /// Complete workflow: Encrypt and upload arbitrary data
    /// - Parameters:
    ///   - data: Data to upload
    ///   - mimeType: MIME type (default: application/octet-stream)
    /// - Returns: Upload metadata with encryption key
    func uploadData(_ data: Data, mimeType: String = "application/octet-stream") async throws -> UploadedMedia {
        // 1. Generate random encryption key (32 bytes for AES-256)
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard result == errSecSuccess else {
            throw NetworkError.serverError(message: "Failed to generate encryption key", responseBody: nil)
        }
        let encryptionKey = Data(keyBytes)
        
        // 2. Encrypt data
        let encryptedData = try encryptWithAES256GCM(data, key: encryptionKey)
        Log.info("🔐 Data encrypted: \(encryptedData.count) bytes", category: "MediaAPI")
        
        // 3. Calculate hash of encrypted data (for server verification)
        let hash = SHA256.hash(data: encryptedData)
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()
        
        // 4. Get upload token
        let tokenData = try await requestMediaToken()
        
        // 5. Upload
        let uploadResponse = try await uploadEncryptedFile(
            encryptedData: encryptedData,
            token: tokenData.uploadToken,
            uploadUrl: tokenData.uploadUrl
        )
        
        // 6. Construct download URL
        let baseUrl = tokenData.uploadUrl.replacingOccurrences(of: "/upload", with: "")
        let downloadUrl = "\(baseUrl)/\(uploadResponse.mediaId)"
        
        return UploadedMedia(
            mediaId: uploadResponse.mediaId,
            mediaUrl: downloadUrl,
            encryptionKey: encryptionKey,
            encryptedData: encryptedData,
            hash: hashHex,
            mimeType: mimeType,
            expiresAt: uploadResponse.expiresAt
        )
    }
    
    // MARK: - High-Level: Download Image
    
    /// Complete workflow: Download and decrypt an image
    /// - Parameters:
    ///   - mediaUrl: Full download URL
    ///   - encryptionKey: Raw encryption key (32 bytes)
    /// - Returns: Decrypted UIImage
    func downloadAndDecryptImage(from mediaUrl: String, encryptionKey: Data) async throws -> UIImage {
        // 1. Download encrypted data
        let encryptedData = try await downloadEncryptedFile(from: mediaUrl)
        
        // 2. Decrypt
        let decryptedData = try decryptWithAES256GCM(encryptedData, key: encryptionKey)
        Log.info("🔓 Image decrypted: \(decryptedData.count) bytes", category: "MediaAPI")
        
        // 3. Convert to UIImage
        guard let image = UIImage(data: decryptedData) else {
            throw NetworkError.serverError(message: "Failed to decode image", responseBody: nil)
        }
        
        return image
    }
    
    // MARK: - Encryption (AES-256-GCM)
    
    private func encryptWithAES256GCM(_ data: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        
        // Combine nonce + ciphertext + tag
        // Format: [12 bytes nonce][N bytes ciphertext][16 bytes tag]
        var combined = Data()
        combined.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)
        
        return combined
    }
    
    private func decryptWithAES256GCM(_ encryptedData: Data, key: Data) throws -> Data {
        // Extract components
        let nonceSize = 12
        let tagSize = 16
        
        guard encryptedData.count >= nonceSize + tagSize else {
            throw NetworkError.serverError(message: "Invalid encrypted data", responseBody: nil)
        }
        
        let nonce = try AES.GCM.Nonce(data: encryptedData.prefix(nonceSize))
        let ciphertext = encryptedData.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedData.suffix(tagSize)
        
        // Reconstruct sealed box
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        // Decrypt
        let symmetricKey = SymmetricKey(data: key)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        return decryptedData
    }
}
