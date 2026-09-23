import Foundation

@MainActor
protocol SlideThumbnailProviding {
    func thumbnail(for project: Project, pageIndex: Int, width: Double) async -> PlatformImage?
}

struct PlaceholderThumbnailProvider: SlideThumbnailProviding {
    func thumbnail(for project: Project, pageIndex: Int, width: Double) async -> PlatformImage? { nil }
}

/// UI-facing adapter. The PDF worker remains responsible for PDFKit and cache details.
@MainActor
struct PDFWorkerThumbnailAdapter: SlideThumbnailProviding {
    let store: ProjectStore
    let provider: PDFThumbnailProvider

    init(store: ProjectStore, provider: PDFThumbnailProvider = PDFThumbnailProvider()) {
        self.store = store
        self.provider = provider
    }

    func thumbnail(for project: Project, pageIndex: Int, width: Double) async -> PlatformImage? {
        do {
            let source = await store.sourceURL(id: project.id)
            let result = try await provider.thumbnail(
                sourceURL: source,
                pageIndex: pageIndex,
                size: CGSize(width: width, height: width * 0.62)
            )
            return result.image
        } catch {
            return nil
        }
    }
}

struct ExportRequest: Sendable {
    let project: Project
    let sourceURL: URL
    let destinationURL: URL
    let managedProjectsRootURL: URL?

    init(project: Project, sourceURL: URL, destinationURL: URL, managedProjectsRootURL: URL? = nil) {
        self.project = project
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.managedProjectsRootURL = managedProjectsRootURL
    }
}

@MainActor
protocol SlideExporting {
    func export(_ request: ExportRequest, progress: @escaping @Sendable (Double) -> Void) async throws
}

struct UnavailableExportService: SlideExporting {
    func export(_ request: ExportRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw ProjectError.storageFailed("The PDF export service is not available yet.")
    }
}

@MainActor
struct PDFWorkerExportAdapter: SlideExporting {
    let exporter: PDFExporter

    init(exporter: PDFExporter = PDFExporter()) { self.exporter = exporter }

    func export(_ request: ExportRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        let selected = request.project.slides.filter(\.isSelected).map(\.pageIndex).sorted()
        let notes = Dictionary(uniqueKeysWithValues: request.project.slides.compactMap { slide in
            slide.note.isEmpty ? nil : (slide.pageIndex, slide.note)
        })
        progress(0)
        _ = try await exporter.export(
            PDFExportPlan(
                sourceURL: request.sourceURL,
                managedProjectsRootURL: request.managedProjectsRootURL,
                selectedPageIndices: selected,
                notesByPageIndex: notes
            ),
            to: request.destinationURL
        )
        progress(1)
    }
}
