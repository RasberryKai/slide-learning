import SwiftUI
import UniformTypeIdentifiers

struct RecentProjectsView: View {
    @ObservedObject var model: AppViewModel
    @State private var showingImporter = false
    @State private var isDropTargeted = false
    @State private var projectToDelete: ProjectSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.recentProjects.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.recentProjects) { summary in
                        RecentProjectRow(summary: summary, open: {
                            guard summary.availability == .available else { return }
                            Task { await model.openProject(id: summary.id) }
                        }, delete: { projectToDelete = summary })
                        .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: 780, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(8)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted, perform: handleDrop)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                await model.importProject(from: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        .confirmationDialog(
            "Delete project?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            presenting: projectToDelete
        ) { summary in
            Button("Delete", role: .destructive) {
                Task { await model.deleteProject(id: summary.id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { summary in
            Text("This removes \(summary.name) and its copied source PDF. Previously exported files are not affected.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Slide Learning")
                    .font(.largeTitle.weight(.bold))
                Text("Choose a deck to curate")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingImporter = true
            } label: {
                Label("Import PDF", systemImage: "plus")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .help("Import one PDF slide deck")
        }
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No projects yet", systemImage: "rectangle.stack")
        } description: {
            Text("Import a PDF to start selecting slides and adding context notes.")
        } actions: {
            Button("Import PDF") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else {
            model.error = .importFailed("Import one PDF at a time.")
            return true
        }
        Task {
            guard let url = await temporaryURL(from: provider) else {
                model.error = .invalidPDF
                return
            }
            await model.importProject(from: url)
            try? FileManager.default.removeItem(at: url)
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
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SlideLearningDrop-\(UUID().uuidString).pdf")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
