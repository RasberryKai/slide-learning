import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct IPadRecentProjectsView: View {
    @ObservedObject var model: AppViewModel
    @State private var showingImporter = false
    @State private var isDropTargeted = false
    @State private var projectToDelete: ProjectSummary?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    libraryHeader
                        .frame(maxWidth: 920)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 28)
                        .padding(.top, 26)
                        .padding(.bottom, 18)

                    if model.recentProjects.isEmpty {
                        ScrollView { emptyState.padding(.horizontal, 28) }
                    } else {
                        List {
                            ForEach(model.recentProjects) { summary in
                                projectCard(summary)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 28))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            guard !isBusy else { return }
                                            projectToDelete = summary
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                            }
                        }
                        .frame(maxWidth: 920)
                        .frame(maxWidth: .infinity)
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .tint(.blue)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isDropTargeted ? Color.blue : Color.clear, lineWidth: 3)
                .padding(10)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted, perform: handleDrop)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result,
                   (error as NSError).code != NSUserCancelledError {
                    model.error = .importFailed(error.localizedDescription)
                }
                return
            }
            guard !isBusy else { return }
            isBusy = true
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                await model.importProject(from: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                isBusy = false
            }
        }
        .alert(
            "Delete project?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            presenting: projectToDelete
        ) { summary in
            Button("Delete", role: .destructive) {
                guard !isBusy else { return }
                isBusy = true
                Task { @MainActor in
                    await model.deleteProject(id: summary.id)
                    isBusy = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { summary in
            Text("This removes \(summary.name) and its copied source PDF. Exported files stay on your device.")
        }
    }

    private var libraryHeader: some View {
        ViewThatFits(in: .horizontal) {
            headerRow
            VStack(alignment: .leading, spacing: 15) {
                headerTitle
                importButton
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 18) {
            headerTitle
            Spacer(minLength: 16)
            importButton
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Slide Learning")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Choose a deck to curate")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var importButton: some View {
        Button {
            guard !isBusy else { return }
            showingImporter = true
        } label: {
            if isBusy {
                ProgressView().controlSize(.regular)
            } else {
                Label("Import PDF", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("slideLearning.importPDF")
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isBusy)
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.blue)
            Text("No projects yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Import a PDF to start selecting slides and adding context notes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            Button("Import PDF") {
                guard !isBusy else { return }
                showingImporter = true
            }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
        .padding(.horizontal, 30)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }

    private func projectCard(_ summary: ProjectSummary) -> some View {
        Button {
            guard summary.availability == .available else { return }
            guard !isBusy else { return }
            isBusy = true
            Task { @MainActor in
                await model.openProject(id: summary.id)
                isBusy = false
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: summary.availability == .available ? "doc.richtext" : "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(summary.availability == .available ? .blue : .orange)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(summary.sourceFilename)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                    if summary.availability == .available {
                        Text("\(summary.selectedCount) of \(summary.pageCount) selected  •  Updated \(summary.updatedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                    } else {
                        Text(availabilityMessage(for: summary))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                if summary.availability == .available {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(17)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slideLearning.project.\(summary.id.uuidString)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.name), \(summary.pageCount) pages, \(summary.selectedCount) selected")
        .contextMenu {
            Button(role: .destructive) {
                guard !isBusy else { return }
                projectToDelete = summary
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }

    private func availabilityMessage(for summary: ProjectSummary) -> String {
        switch summary.availability {
        case .missingProject: "Project files are missing."
        case .missingSource: "The copied source PDF is missing."
        case .unreadableMetadata: "Project metadata cannot be read."
        case .unreadableSource: "The copied source PDF cannot be read."
        case .available: ""
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else {
            model.error = .importFailed("Import one PDF at a time.")
            return true
        }
        guard !isBusy else { return true }
        isBusy = true
        Task { @MainActor in
            guard let url = await temporaryURL(from: provider) else {
                model.error = .invalidPDF
                isBusy = false
                return
            }
            await model.importProject(from: url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            isBusy = false
        }
        return true
    }

    private func temporaryURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let temporaryDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SlideLearningDrop-\(UUID().uuidString)", isDirectory: true)
                let destination = temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
