#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
import CoreGraphics
import CryptoKit
import Foundation
import PDFKit

struct PDFThumbnail: @unchecked Sendable {
    let image: PlatformImage
    let pageIndex: Int
}

/// Lazy thumbnail generation for the overview grid. Thumbnails are a
/// disposable presentation cache and are never consumed by PDF export.
actor PDFThumbnailProvider {
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private var memoryCache: [String: PDFThumbnail] = [:]

    init(
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slide Learning/Thumbnails", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    func thumbnail(
        sourceURL: URL,
        pageIndex: Int,
        size: CGSize,
        scale: CGFloat = 2
    ) async throws -> PDFThumbnail {
        try Task.checkCancellation()
        guard pageIndex >= 0, size.width > 0, size.height > 0, scale > 0 else {
            throw PDFThumbnailError.invalidRequest
        }

        let cacheURL = cacheURL(sourceURL: sourceURL, pageIndex: pageIndex, size: size, scale: scale)
        let cacheKey = cacheURL.lastPathComponent
        if let thumbnail = memoryCache[cacheKey] {
            return thumbnail
        }
        if let image = cachedImage(at: cacheURL) {
            let thumbnail = PDFThumbnail(image: image, pageIndex: pageIndex)
            memoryCache[cacheKey] = thumbnail
            return thumbnail
        }

        // Keep PDFKit work off the main actor. The provider is an actor, so
        // duplicate requests are naturally serialized and cannot corrupt the
        // on-disk cache.
        let result: PDFThumbnail = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: sourceURL),
                  pageIndex < document.pageCount,
                  let page = document.page(at: pageIndex) else {
                throw PDFThumbnailError.unreadableSource
            }
            let thumbnailSize = CGSize(width: size.width * scale, height: size.height * scale)
            guard let image = page.thumbnail(of: thumbnailSize, for: .cropBox) as PlatformImage? else {
                throw PDFThumbnailError.renderFailed
            }
            return PDFThumbnail(image: image, pageIndex: pageIndex)
        }.value

        try Task.checkCancellation()
        try store(result.image, at: cacheURL)
        memoryCache[cacheKey] = result
        return result
    }

    func removeCachedThumbnails(for sourceURL: URL) {
        let prefix = cachePrefix(for: sourceURL)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            memoryCache.removeValue(forKey: entry.lastPathComponent)
            try? fileManager.removeItem(at: entry)
        }
    }

    private func cacheURL(sourceURL: URL, pageIndex: Int, size: CGSize, scale: CGFloat) -> URL {
        let key = "\(sourceURL.path)|\(sourceFingerprint(sourceURL))|\(pageIndex)|\(size.width)x\(size.height)|\(scale)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(cachePrefix(for: sourceURL))\(digest).png")
    }

    private func cachePrefix(for sourceURL: URL) -> String {
        let digest = SHA256.hash(data: Data(sourceURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(digest)-"
    }

    private func sourceFingerprint(_ sourceURL: URL) -> String {
        guard let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate else {
            return "unknown"
        }
        return "\(size)-\(modified.timeIntervalSince1970)"
    }

    private func cachedImage(at url: URL) -> PlatformImage? {
        #if canImport(AppKit)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    private func store(_ image: PlatformImage, at url: URL) throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        #if canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw PDFThumbnailError.renderFailed
        }
        #else
        guard let data = image.pngData() else { throw PDFThumbnailError.renderFailed }
        #endif
        try data.write(to: url, options: .atomic)
    }
}

typealias PDFThumbnailService = PDFThumbnailProvider

enum PDFThumbnailError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case unreadableSource
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The thumbnail request is invalid."
        case .unreadableSource: "The source PDF could not be opened."
        case .renderFailed: "The slide thumbnail could not be rendered."
        }
    }
}
