import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RecentProjectsView: View {
    @ObservedObject var model: AppViewModel
    @State private var showingImporter = false
    @State private var isDropTargeted = false
    @State private var projectToDelete: ProjectSummary?
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sharedLibraryStatus
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
            guard !isBusy else { return }
            isBusy = true
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                await model.importProject(from: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                isBusy = false
            }
        }
        .confirmationDialog(
            "Delete project?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
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
            Text(deleteMessage(for: summary))
        }
        .overlay {
            if isBusy {
                ProgressView("Updating library…")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }
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
                showFolderPicker()
            } label: {
                Label(
                    model.sharedLibraryStatus.isShared ? "Change Shared Folder" : "Choose iCloud Folder",
                    systemImage: "folder.badge.cloud"
                )
            }
            .disabled(isBusy)
            .help("Choose the iCloud Drive / Slide Learning folder shared with your other device")
            Button {
                showingImporter = true
            } label: {
                Label("Import PDF", systemImage: "plus")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .help("Import one PDF slide deck")
            .disabled(isBusy)
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var sharedLibraryStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: sharedLibraryIcon)
                    .foregroundStyle(sharedLibraryTint)
                Text(sharedLibraryTitle)
                    .font(.headline)
                Spacer()
                Button {
                    guard !isBusy else { return }
                    isBusy = true
                    Task { @MainActor in
                        await model.refreshSharedLibrary()
                        await model.refreshRecentProjects()
                        isBusy = false
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh projects and check for changes from another device")
                .disabled(isBusy)
            }
            Text(sharedLibraryMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = model.sharedLibraryStatus.sharedURL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else if case .local = model.sharedLibraryStatus {
                Text(localLibraryPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            if model.sharedLibraryStatus.isShared == false {
                Button {
                    showFolderPicker()
                } label: {
                    Label("Choose iCloud Folder", systemImage: "folder.badge.cloud")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 16)
    }

    private var sharedLibraryTitle: String {
        switch model.sharedLibraryStatus {
        case .local: "Local library"
        case .shared: "Shared folder selected"
        case .needsSelection: "Choose a shared folder"
        case .unavailable: "Shared folder unavailable"
        }
    }

    private var sharedLibraryIcon: String {
        switch model.sharedLibraryStatus {
        case .local: "internaldrive"
        case .shared: "folder.badge.cloud"
        case .needsSelection: "folder.badge.plus"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var sharedLibraryTint: Color {
        switch model.sharedLibraryStatus {
        case .local: .secondary
        case .shared: .accentColor
        case .needsSelection: .orange
        case .unavailable: .red
        }
    }

    private var sharedLibraryMessage: String {
        switch model.sharedLibraryStatus {
        case .local:
            return "Projects currently stay on this Mac. Choose the same folder inside iCloud Drive on both devices to work across them."
        case .shared:
            return "This device reads and writes the selected folder. Choose the same iCloud Drive / Slide Learning folder on your iPad."
        case .needsSelection:
            return "Create or select a folder named Slide Learning inside iCloud Drive. Choose that same folder on your Mac and iPad. Existing local projects stay as a backup while they are copied."
        case .unavailable(let message):
            return "The previously selected shared folder cannot be opened. Choose it again; the local library is not being used silently. (message)"
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No projects yet", systemImage: "rectangle.stack")
        } description: {
            Text(emptyStateMessage)
        } actions: {
            Button("Import PDF") { showingImporter = true }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if model.sharedLibraryStatus.isShared {
            return "Import a PDF to start selecting slides and adding context notes. The project will be available on devices using this shared folder."
        }
        return "Choose the same folder inside iCloud Drive on both devices, then import a PDF to start selecting slides and adding context notes."
    }

    private var localLibraryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slide Learning", isDirectory: true)
            .path
    }

    private func chooseSharedFolder(_ url: URL) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            await model.selectSharedLibraryFolder(url)
            await model.refreshSharedLibrary()
            await model.refreshRecentProjects()
            isBusy = false
        }
    }

    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            chooseSharedFolder(url)
        }
    }

    private func deleteMessage(for summary: ProjectSummary) -> String {
        if model.sharedLibraryStatus.isShared {
            return "This removes \(summary.name) and its PDF and notes from the selected shared folder for every device using that folder. Previously exported files are not affected."
        }
        return "This removes \(summary.name) and its copied source PDF from this device. Previously exported files are not affected."
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else {
            model.error = .importFailed("Import one PDF at a time.")
            return true
        }
        guard !isBusy else { return true }
        isBusy = true
        Task {
            guard let url = await temporaryURL(from: provider) else {
                model.error = .invalidPDF
                isBusy = false
                return
            }
            await model.importProject(from: url)
            try? FileManager.default.removeItem(at: url)
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
