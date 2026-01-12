//
//  MediaOptimizer.swift
//  Construct Messenger
//
//  Optimizes media files before encryption
//  - Images: resize, convert, compress, strip EXIF
//  - Thumbnails: generate 200x200 previews
//

import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Media Optimization Error
enum MediaOptimizationError: LocalizedError {
    case invalidImage
    case conversionFailed
    case thumbnailGenerationFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid or corrupted image"
        case .conversionFailed:
            return "Failed to convert image format"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .unsupportedFormat:
            return "Unsupported media format"
        }
    }
}

// MARK: - Optimized Media
struct OptimizedMedia {
    let data: Data
    let thumbnail: Data?
    let metadata: MediaMetadata
}

// MARK: - Media Metadata
struct MediaMetadata {
    let originalSize: Int
    let optimizedSize: Int
    let width: Int?
    let height: Int?
    let duration: TimeInterval?  // For video/audio
    let mimeType: String
}

// MARK: - Media Optimizer
struct MediaOptimizer {

    // MARK: - Constants

    /// Max image dimension (2048px for long side)
    private static let maxImageDimension: CGFloat = 2048

    /// Thumbnail size (200x200)
    private static let thumbnailSize = CGSize(width: 200, height: 200)

    /// JPEG compression quality (0.8 = 80%)
    private static let jpegQuality: CGFloat = 0.8

    /// Thumbnail JPEG quality (0.7 = 70%, smaller for network)
    private static let thumbnailQuality: CGFloat = 0.7

    // MARK: - Image Optimization

    /// Optimizes an image for upload
    /// - Parameter image: Original UIImage
    /// - Returns: OptimizedMedia with data, thumbnail, and metadata
    /// - Throws: MediaOptimizationError if optimization fails
    static func optimizeImage(_ image: UIImage) throws -> OptimizedMedia {
        let originalData = image.pngData() ?? Data()
        let originalSize = originalData.count

        // 1. Resize if needed (> 4K → 2048px)
        let resizedImage = resizeImage(image, maxDimension: maxImageDimension)

        // 2. Convert to JPEG (strips EXIF automatically on iOS)
        guard let optimizedData = resizedImage.jpegData(compressionQuality: jpegQuality) else {
            throw MediaOptimizationError.conversionFailed
        }

        // 3. Generate thumbnail
        let thumbnail = try generateThumbnail(from: resizedImage)

        // 4. Extract metadata
        let metadata = MediaMetadata(
            originalSize: originalSize,
            optimizedSize: optimizedData.count,
            width: Int(resizedImage.size.width),
            height: Int(resizedImage.size.height),
            duration: nil,
            mimeType: "image/jpeg"
        )

        Log.info("Image optimized: \(originalSize) → \(optimizedData.count) bytes (\(compressionRatio(original: originalSize, optimized: optimizedData.count))% reduction)", category: "MediaOptimizer")

        return OptimizedMedia(
            data: optimizedData,
            thumbnail: thumbnail,
            metadata: metadata
        )
    }

    /// Optimizes an image from file URL
    /// - Parameter url: File URL to image
    /// - Returns: OptimizedMedia
    /// - Throws: MediaOptimizationError if loading or optimization fails
    static func optimizeImage(from url: URL) throws -> OptimizedMedia {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw MediaOptimizationError.invalidImage
        }
        return try optimizeImage(image)
    }

    // MARK: - Image Resizing

    /// Resizes image to fit within maxDimension while preserving aspect ratio
    /// - Parameters:
    ///   - image: Original image
    ///   - maxDimension: Maximum width or height
    /// - Returns: Resized image
    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Check if resize is needed
        guard size.width > maxDimension || size.height > maxDimension else {
            return image  // Already small enough
        }

        // Calculate new size preserving aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            // Landscape or square
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Resize using high-quality rendering
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail (200x200 JPEG, ~10KB)
    /// - Parameter image: Source image
    /// - Returns: Thumbnail JPEG data
    /// - Throws: MediaOptimizationError if generation fails
    static func generateThumbnail(from image: UIImage) throws -> Data {
        // Resize to thumbnail size (aspect-fill, center-cropped)
        let thumbnail = image.resized(to: thumbnailSize, contentMode: .scaleAspectFill)

        // Convert to JPEG with lower quality for smaller size
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: thumbnailQuality) else {
            throw MediaOptimizationError.thumbnailGenerationFailed
        }

        Log.debug("Generated thumbnail: \(thumbnailData.count) bytes", category: "MediaOptimizer")

        return thumbnailData
    }

    /// Generates a thumbnail from video first frame
    /// - Parameter url: Video file URL
    /// - Returns: Thumbnail JPEG data
    /// - Throws: MediaOptimizationError if generation fails
    static func generateVideoThumbnail(from url: URL) throws -> Data {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        // Get first frame at 0 seconds
        let time = CMTime(seconds: 0, preferredTimescale: 60)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            return try generateThumbnail(from: image)
        } catch {
            throw MediaOptimizationError.thumbnailGenerationFailed
        }
    }

    // MARK: - Video Optimization (Future)

    /// Optimizes video (placeholder for future implementation)
    /// TODO: Implement video transcoding (H.265, 1080p, 2-4 Mbps)
    static func optimizeVideo(from url: URL) async throws -> OptimizedMedia {
        // For now, just read original file and generate thumbnail
        let videoData = try Data(contentsOf: url)
        let thumbnail = try generateVideoThumbnail(from: url)

        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.load(.tracks)
        let videoTrack = tracks.first(where: { $0.mediaType == .video })
        let size = try await videoTrack?.load(.naturalSize)

        let metadata = MediaMetadata(
            originalSize: videoData.count,
            optimizedSize: videoData.count,  // Not optimized yet
            width: size.map { Int($0.width) },
            height: size.map { Int($0.height) },
            duration: duration,
            mimeType: "video/mp4"
        )

        return OptimizedMedia(
            data: videoData,
            thumbnail: thumbnail,
            metadata: metadata
        )
    }

    // MARK: - Helper Methods

    /// Calculates compression ratio percentage
    private static func compressionRatio(original: Int, optimized: Int) -> Int {
        guard original > 0 else { return 0 }
        let ratio = Double(original - optimized) / Double(original) * 100
        return Int(ratio)
    }
}

// MARK: - UIImage Extension
extension UIImage {

    /// Resize image to fit within size with content mode
    /// - Parameters:
    ///   - targetSize: Target size
    ///   - contentMode: How to fit (aspectFit or aspectFill)
    /// - Returns: Resized image
    func resized(to targetSize: CGSize, contentMode: UIView.ContentMode = .scaleAspectFit) -> UIImage {
        let size = self.size

        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height

        var newSize: CGSize
        if contentMode == .scaleAspectFit {
            // Fit inside (letterbox/pillarbox)
            let ratio = min(widthRatio, heightRatio)
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        } else {
            // Fill (crop)
            let ratio = max(widthRatio, heightRatio)
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        }

        // Render at target size
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            // Center the image
            let origin = CGPoint(
                x: (targetSize.width - newSize.width) / 2,
                y: (targetSize.height - newSize.height) / 2
            )
            self.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}
