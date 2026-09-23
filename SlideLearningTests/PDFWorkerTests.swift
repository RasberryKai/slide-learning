import CoreGraphics
import CoreText
import Foundation
import PDFKit
import XCTest
#if os(iOS)
@testable import SlideLearningIPad
#else
@testable import SlideLearning
#endif

final class PDFWorkerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlideLearningPDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testValidatorAcceptsPagesAndRejectsCorruptAndEmptyFiles() async throws {
        let valid = try makePDF(pageCount: 2, name: "valid.pdf")
        let result = try await PDFKitValidator().validate(valid)
        XCTAssertEqual(result.pageCount, 2)

        let empty = try makeEmptyPDF(name: "empty.pdf")
        do {
            _ = try await PDFKitValidator().validate(empty)
            XCTFail("Expected empty PDF rejection")
        } catch let error as ProjectError {
            // Core Graphics identifies this as a zero-page document on some
            // macOS releases, while other releases reject the minimal file
            // before exposing its page tree. Both are safe rejection paths.
            XCTAssertTrue(error == .emptyPDF || error == .invalidPDF)
        }

        let corrupt = temporaryDirectory.appendingPathComponent("corrupt.pdf")
        try Data("%PDF-this-is-not-a-document".utf8).write(to: corrupt)
        do {
            _ = try await PDFKitValidator().validate(corrupt)
            XCTFail("Expected corrupt PDF rejection")
        } catch let error as ProjectError {
            XCTAssertEqual(error, .invalidPDF)
        }
    }

    func testExportSortsSelectionAndKeepsNotesOnSeparateTextRegion() async throws {
        let sourceDirectory = try makeProjectDirectory()
        let source = try makePDF(pageCount: 3, name: "source.pdf", directory: sourceDirectory)
        let destination = temporaryDirectory.appendingPathComponent("selected.pdf")
        let result = try await PDFExporter().export(
            PDFExportPlan(
                sourceURL: source,
                managedProjectsRootURL: sourceDirectory.deletingLastPathComponent(),
                selectedPageIndices: [2, 0],
                notesByPageIndex: [0: "Context for first source slide"]
            ),
            to: destination
        )

        XCTAssertEqual(result.outputPageCount, 2)
        let output = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(output.pageCount, 2)
        XCTAssertTrue(output.page(at: 0)?.string?.contains("Source slide 1") == true)
        XCTAssertTrue(output.page(at: 0)?.string?.contains("Context for first source slide") == true)
        XCTAssertTrue(output.page(at: 1)?.string?.contains("Source slide 3") == true)
        XCTAssertFalse(output.page(at: 1)?.string?.contains("Source slide 2") == true)
    }

    func testLongNotesProduceLabeledContinuationPages() async throws {
        let sourceDirectory = try makeProjectDirectory()
        let source = try makePDF(pageCount: 1, name: "source.pdf", directory: sourceDirectory)
        let managedProjectsRoot = sourceDirectory.deletingLastPathComponent()
        let destination = temporaryDirectory.appendingPathComponent("long-notes.pdf")
        let tokens = (0..<1_000).map { "noteToken\($0)" }
        let note = tokens.joined(separator: " ")
        let result = try await PDFExporter().export(
            PDFExportPlan(
                sourceURL: source,
                managedProjectsRootURL: managedProjectsRoot,
                selectedPageIndices: [0],
                notesByPageIndex: [0: note]
            ),
            to: destination
        )

        XCTAssertGreaterThan(result.outputPageCount, 1)
        let output = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertTrue((1..<output.pageCount).contains { output.page(at: $0)?.string?.contains("Notes for source slide 1") == true })
        XCTAssertTrue(output.page(at: 0)?.string?.contains("Source slide 1") == true)
        let searchableText = (0..<output.pageCount).compactMap { output.page(at: $0)?.string }.joined(separator: " ")
        for token in tokens {
            XCTAssertTrue(searchableText.contains(token), "Missing extracted note token: \(token)")
        }
    }

    func testExportRejectsDestinationInsideSourceProjectDirectory() async throws {
        let sourceDirectory = try makeProjectDirectory()
        let source = try makePDF(pageCount: 1, name: "source.pdf", directory: sourceDirectory)
        let managedProjectsRoot = sourceDirectory.deletingLastPathComponent()
        let nestedDestination = temporaryDirectory
            .appendingPathComponent("Project", isDirectory: true)
            .appendingPathComponent(sourceDirectory.lastPathComponent, isDirectory: true)
            .appendingPathComponent("selected.pdf")

        do {
            _ = try await PDFExporter().export(
                PDFExportPlan(
                    sourceURL: source,
                    managedProjectsRootURL: managedProjectsRoot,
                    selectedPageIndices: [0]
                ),
                to: nestedDestination
            )
            XCTFail("Expected internal destination rejection")
        } catch let error as PDFExportError {
            XCTAssertEqual(error, .destinationInsideProject)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedDestination.path))

        let siblingDirectory = temporaryDirectory
            .appendingPathComponent("Project", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        let siblingDestination = siblingDirectory.appendingPathComponent("selected.pdf")
        do {
            _ = try await PDFExporter().export(
                PDFExportPlan(
                    sourceURL: source,
                    managedProjectsRootURL: managedProjectsRoot,
                    selectedPageIndices: [0]
                ),
                to: siblingDestination
            )
            XCTFail("Expected sibling managed-project destination rejection")
        } catch let error as PDFExportError {
            XCTAssertEqual(error, .destinationInsideProject)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: siblingDestination.path))
    }

    func testExternalUUIDNamedSourceMayExportWithoutManagedRoot() async throws {
        let externalDirectory = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try makePDF(pageCount: 1, name: "source.pdf", directory: externalDirectory)
        let destination = temporaryDirectory.appendingPathComponent("external-export.pdf")

        _ = try await PDFExporter().export(
            PDFExportPlan(sourceURL: source, selectedPageIndices: [0]),
            to: destination
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testMixedPageSizesPreserveOrderGeometryAndSelectableSourceText() async throws {
        let sourceDirectory = try makeProjectDirectory()
        let source = try makeMixedPDF(name: "mixed.pdf", directory: sourceDirectory)
        let destination = temporaryDirectory.appendingPathComponent("mixed-export.pdf")
        let result = try await PDFExporter().export(
            PDFExportPlan(
                sourceURL: source,
                managedProjectsRootURL: sourceDirectory.deletingLastPathComponent(),
                selectedPageIndices: [2, 0, 1]
            ),
            to: destination
        )

        XCTAssertEqual(result.outputPageCount, 3)
        let output = try XCTUnwrap(PDFDocument(url: destination))
        let bounds = (0..<output.pageCount).compactMap { output.page(at: $0)?.bounds(for: .mediaBox) }
        XCTAssertEqual(bounds.map(\.width), [640, 360, 640])
        XCTAssertEqual(bounds.map(\.height), [386, 666, 386])
        XCTAssertTrue(output.page(at: 0)?.string?.contains("Source slide 1") == true)
        XCTAssertTrue(output.page(at: 0)?.string?.contains("Landscape source text") == true)
        XCTAssertTrue(output.page(at: 1)?.string?.contains("Source slide 2") == true)
        XCTAssertTrue(output.page(at: 1)?.string?.contains("Portrait source text") == true)
        XCTAssertTrue(output.page(at: 2)?.string?.contains("Source slide 3") == true)
        XCTAssertTrue(output.page(at: 2)?.string?.contains("Second landscape source text") == true)
        XCTAssertTrue(bounds.allSatisfy { abs($0.height - (($0.width == 360 ? 640 : 360) + 26)) < 0.1 })
    }

    func testThumbnailsRenderAndReloadFromDiskCache() async throws {
        let source = try makePDF(pageCount: 2, name: "thumbnails.pdf")
        let cache = temporaryDirectory.appendingPathComponent("thumbnail-cache")
        let provider = PDFThumbnailProvider(cacheDirectory: cache)
        let first = try await provider.thumbnail(sourceURL: source, pageIndex: 1,
                                                  size: CGSize(width: 160, height: 100))
        XCTAssertEqual(first.pageIndex, 1)
        XCTAssertGreaterThan(first.image.size.width, 0)
        XCTAssertGreaterThan(first.image.size.height, 0)
        let files = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let reloadedProvider = PDFThumbnailProvider(cacheDirectory: cache)
        let reloaded = try await reloadedProvider.thumbnail(sourceURL: source, pageIndex: 1,
                                                            size: CGSize(width: 160, height: 100))
        XCTAssertEqual(reloaded.image.size, first.image.size)
        await reloadedProvider.removeCachedThumbnails(for: source)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    }

    private func makePDF(pageCount: Int, name: String, directory: URL? = nil) throws -> URL {
        guard let testDirectory = temporaryDirectory else {
            throw NSError(domain: "SlideLearningPDFTests", code: 2)
        }
        let outputDirectory = directory ?? testDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: 640, height: 360)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "SlideLearningPDFTests", code: 1)
        }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func makeProjectDirectory() throws -> URL {
        guard let testDirectory = temporaryDirectory else {
            throw NSError(domain: "SlideLearningPDFTests", code: 2)
        }
        let directory = testDirectory.appendingPathComponent("Project").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeMixedPDF(name: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var initialBox = CGRect(x: 0, y: 0, width: 640, height: 360)
        guard let context = CGContext(url as CFURL, mediaBox: &initialBox, nil) else {
            throw NSError(domain: "SlideLearningPDFTests", code: 4)
        }
        let pages: [(CGSize, String)] = [
            (CGSize(width: 640, height: 360), "Landscape source text"),
            (CGSize(width: 360, height: 640), "Portrait source text"),
            (CGSize(width: 640, height: 360), "Second landscape source text")
        ]
        for (size, text) in pages {
            var mediaBox = CGRect(origin: .zero, size: size)
            let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            let attributed = NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(0, attributed.length),
                CGPath(rect: CGRect(x: 20, y: size.height - 50, width: size.width - 40, height: 30), transform: nil),
                nil
            )
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func makeEmptyPDF(name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        var data = Data("%PDF-1.4\n".utf8)
        let catalogOffset = data.count
        data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".utf8))
        let pagesOffset = data.count
        data.append(Data("2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n".utf8))
        let xrefOffset = data.count
        data.append(Data("xref\n0 3\n0000000000 65535 f \n".utf8))
        data.append(Data(String(format: "%010d 00000 n \n", catalogOffset).utf8))
        data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
        data.append(Data("trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        try data.write(to: url)
        return url
    }
}
