import Foundation
import CoreGraphics
import PDFKit

struct PDFValidationResult: Sendable, Equatable {
    let pageCount: Int
}

protocol PDFValidating: Sendable {
    func validate(_ url: URL) async throws -> PDFValidationResult
}

/// Validates the complete source document before it becomes a project.
///
/// Validation intentionally rejects every encrypted document, including one
/// that PDFKit happens to unlock with an empty password. Password handling is
/// outside the scope of the application.
struct PDFKitValidator: PDFValidating {
    func validate(_ url: URL) async throws -> PDFValidationResult {
        try await Task.detached(priority: .userInitiated) {
            try validateSynchronously(url)
        }.value
    }

    private func validateSynchronously(_ url: URL) throws -> PDFValidationResult {
        let fileManager = FileManager.default
        guard url.isFileURL,
              fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw ProjectError.invalidPDF
        }

        guard let cgDocument = CGPDFDocument(url as CFURL) else {
            throw ProjectError.invalidPDF
        }

        // `isEncrypted` must be checked independently of `isLocked`: PDFKit
        // may automatically unlock an encrypted PDF whose user password is
        // empty, while the product still rejects encrypted sources.
        guard !cgDocument.isEncrypted,
              cgDocument.isUnlocked else {
            throw ProjectError.encryptedPDF
        }

        let cgCount = cgDocument.numberOfPages
        guard cgCount <= Int.max else {
            throw ProjectError.invalidPDF
        }
        guard cgCount > 0 else {
            throw ProjectError.emptyPDF
        }

        guard let document = PDFDocument(url: url) else {
            throw ProjectError.invalidPDF
        }
        guard !document.isEncrypted, !document.isLocked else {
            throw ProjectError.encryptedPDF
        }
        let pdfKitCount = document.pageCount
        guard pdfKitCount > 0, pdfKitCount == cgCount else {
            throw ProjectError.invalidPDF
        }

        for number in 1...cgCount {
            guard let page = cgDocument.page(at: number) else {
                throw ProjectError.invalidPDF
            }
            let media = page.getBoxRect(.mediaBox)
            let crop = page.getBoxRect(.cropBox)
            guard isUsable(media), isUsable(crop) else {
                throw ProjectError.invalidPDF
            }
        }

        return PDFValidationResult(pageCount: pdfKitCount)
    }
}

/// Kept as a source-compatible name for callers that supplied the old default
/// while the PDF worker was still a placeholder.
typealias UnimplementedPDFValidator = PDFKitValidator

private func isUsable(_ rect: CGRect) -> Bool {
    rect != .null && rect != .infinite &&
    rect.origin.x.isFinite && rect.origin.y.isFinite &&
    rect.width.isFinite && rect.height.isFinite &&
    rect.width > 0 && rect.height > 0
}
