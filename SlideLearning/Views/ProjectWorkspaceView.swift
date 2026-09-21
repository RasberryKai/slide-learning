import AppKit
import SwiftUI

struct ProjectWorkspaceView: View {
    @ObservedObject var model: ProjectViewModel
    var thumbnailProvider: any SlideThumbnailProviding = PlaceholderThumbnailProvider()
    var exporter: any SlideExporting = UnavailableExportService()
    @State private var exportState: ExportState = .idle
    @State private var showingExportResult = false
    @State private var isCopyingSlide = false
    @State private var copyError: String?
    @FocusState private var notesFocused: Bool

    enum ExportState: Equatable {
        case idle
        case exporting
        case success(URL)
        case failure(String)
    }

    private var copySlideAction: (() -> Void)? {
        guard model.project.viewPreferences.focusedPageIndex != nil, !isCopyingSlide else { return nil }
        return { copyCurrentSlide() }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                SlideGridView(model: model, thumbnailProvider: thumbnailProvider)
                    .frame(width: model.project.viewPreferences.thumbnailSize.width + 40)
                Divider()
                InspectorView(model: model, thumbnailProvider: thumbnailProvider, notesFocused: $notesFocused)
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.copySlide, copySlideAction)
        .alert("Could not copy slide", isPresented: Binding(
            get: { copyError != nil },
            set: { if !$0 { copyError = nil } }
        )) {
            Button("OK", role: .cancel) { copyError = nil }
        } message: {
            Text(copyError ?? "")
        }
        .overlay {
            WorkspaceKeyMonitor(
                onMove: { model.dispatch(.moveFocus($0)) },
                onToggle: { model.dispatch(.toggleFocusedSelection) },
                onType: { text in
                    guard let pageIndex = model.project.viewPreferences.focusedPageIndex,
                          let slide = model.project.slides.first(where: { $0.pageIndex == pageIndex }) else { return false }
                    model.dispatch(.setInspectorVisible(true))
                    model.dispatch(.updateNote(pageIndex: pageIndex, text: slide.note + text))
                    notesFocused = true
                    return true
                }
            )
            .frame(width: 0, height: 0)
        }
        .alert("Export complete", isPresented: $showingExportResult) {
            if case .success(let url) = exportState {
                Button("Show in Finder") { SavePanelPresenter.reveal(url) }
            }
            Button("Done", role: .cancel) { }
        } message: {
            if case .success(let url) = exportState {
                Text("Saved \(url.lastPathComponent)")
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { if case .failure = exportState { return true }; return false },
            set: { if !$0 { exportState = .idle } }
        )) {
            Button("Retry") { beginExport() }
            Button("Cancel", role: .cancel) { exportState = .idle }
        } message: {
            if case .failure(let message) = exportState { Text(message) }
        }
        .alert("Could not save project", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        ), presenting: model.error) { _ in
            Button("OK") { model.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button {
                NotificationCenter.default.post(name: .slideLearningCloseProject, object: nil)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Back to Recent Projects")
            Text(model.project.name)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Picker("Show", selection: Binding(
                get: { model.project.viewPreferences.filter },
                set: { model.dispatch(.setFilter($0)) }
            )) {
                Text("All").tag(SlideFilter.all)
                Text("Selected").tag(SlideFilter.selected)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            Picker("Thumbnail size", selection: Binding(
                get: { model.project.viewPreferences.thumbnailSize },
                set: { model.dispatch(.setThumbnailSize($0)) }
            )) {
                Text("Compact").tag(ThumbnailSize.compact)
                Text("Regular").tag(ThumbnailSize.regular)
                Text("Large").tag(ThumbnailSize.large)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 112)
            .help("Thumbnail size")
            Text("\(model.selectedCount) of \(model.totalCount) selected")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                beginExport()
            } label: {
                if exportState == .exporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedCount == 0 || exportState == .exporting)
            .help(model.selectedCount == 0 ? "Select at least one slide to export" : "Export selected slides")
            Button {
                model.dispatch(.setInspectorVisible(!model.project.viewPreferences.inspectorVisible))
            } label: {
                Image(systemName: "rectangle.bottomthird.inset.filled")
            }
            .buttonStyle(.borderless)
            .help(model.project.viewPreferences.inspectorVisible ? "Hide notes" : "Show notes")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func copyCurrentSlide() {
        guard !isCopyingSlide,
              let pageIndex = model.project.viewPreferences.focusedPageIndex else { return }
        // Capture the source page before rendering so navigation cannot change the copy target.
        let project = model.project
        isCopyingSlide = true
        Task { @MainActor in
            defer { isCopyingSlide = false }
            guard let image = await thumbnailProvider.thumbnail(for: project, pageIndex: pageIndex, width: 2000) else {
                copyError = "The slide image could not be rendered. Please try again."
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !pasteboard.writeObjects([image]) {
                copyError = "The slide image could not be written to the clipboard. Please try again."
            }
        }
    }

    private func beginExport() {
        guard model.selectedCount > 0 else { return }
        let baseName = URL(fileURLWithPath: model.project.sourceFilename)
            .deletingPathExtension().lastPathComponent
        let suggested = "\(baseName) – Selected Slides.pdf"
        Task {
            guard let destination = await SavePanelPresenter.choosePDF(suggestedName: suggested) else { return }
            let source = await model.sourceURL()
            exportState = .exporting
            do {
                try await exporter.export(
                    ExportRequest(
                        project: model.project,
                        sourceURL: source,
                        destinationURL: destination,
                        managedProjectsRootURL: await model.managedProjectsRootURL()
                    ),
                    progress: { _ in }
                )
                exportState = .success(destination)
                showingExportResult = true
            } catch let error as ProjectError {
                exportState = .failure(error.localizedDescription)
            } catch {
                exportState = .failure(error.localizedDescription)
            }
        }
    }
}

extension Notification.Name {
    static let slideLearningCloseProject = Notification.Name("SlideLearning.closeProject")
}
