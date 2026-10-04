import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct IPadRecentProjectsView: View {
    @ObservedObject var model: AppViewModel
    @State private var showingImporter = false
    @State private var showingFolderImporter = false
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

                    sharedLibraryStatus
                        .frame(maxWidth: 920)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

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
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result,
                   (error as NSError).code != NSUserCancelledError {
                    model.error = .storageFailed(error.localizedDescription)
                }
                return
            }
            chooseSharedFolder(url)
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

    private var libraryHeader: some View {
        ViewThatFits(in: .horizontal) {
            headerRow
            VStack(alignment: .leading, spacing: 15) {
                headerTitle
                HStack(spacing: 10) {
                    sharedFolderButton
                    importButton
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 18) {
            headerTitle
            Spacer(minLength: 16)
            sharedFolderButton
            importButton
        }
    }

    private var sharedFolderButton: some View {
        Button {
            guard !isBusy else { return }
            showingFolderImporter = true
        } label: {
            Label(
                model.sharedLibraryStatus.isShared ? "Change Shared Folder" : "Choose iCloud Folder",
                systemImage: "folder.badge.cloud"
            )
            .font(.headline)
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("slideLearning.chooseSharedFolder")
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBusy)
        .help("Choose the iCloud Drive / Slide Learning folder shared with your other device")
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

    @ViewBuilder
    private var sharedLibraryStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: sharedLibraryIcon)
                    .foregroundStyle(sharedLibraryTint)
                Text(sharedLibraryTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
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
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityLabel("Refresh shared library")
                .help("Refresh projects and check for changes from another device")
                .disabled(isBusy)
            }
            Text(sharedLibraryMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
            if let url = model.sharedLibraryStatus.sharedURL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.52))
                    .textSelection(.enabled)
                    .lineLimit(2)
            } else if case .local = model.sharedLibraryStatus {
                Text(localLibraryPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.52))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            if model.sharedLibraryStatus.isShared == false {
                Button {
                    showingFolderImporter = true
                } label: {
                    Label("Choose iCloud Folder", systemImage: "folder.badge.cloud")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(15)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
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
        case .local: .white.opacity(0.65)
        case .shared: .blue
        case .needsSelection: .orange
        case .unavailable: .red
        }
    }

    private var sharedLibraryMessage: String {
        switch model.sharedLibraryStatus {
        case .local:
            return "Projects currently stay on this iPad. Choose the same folder inside iCloud Drive on both devices to work across them."
        case .shared:
            return "This device reads and writes the selected folder. Choose the same iCloud Drive / Slide Learning folder on your Mac."
        case .needsSelection:
            return "Create or select a folder named Slide Learning inside iCloud Drive. Choose that same folder on your Mac and iPad. Existing local projects stay as a backup while they are copied."
        case .unavailable(let message):
            return "The previously selected shared folder cannot be opened. Choose it again; the local library is not being used silently. \(message)"
        }
    }

    private var localLibraryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slide Learning", isDirectory: true)
            .path
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.blue)
            Text("No projects yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(emptyStateMessage)
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

    private var emptyStateMessage: String {
        if model.sharedLibraryStatus.isShared {
            return "Import a PDF to start selecting slides and adding context notes. The project will be available on devices using this shared folder."
        }
        return "Choose the same folder inside iCloud Drive on both devices, then import a PDF to start selecting slides and adding context notes."
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

    private func deleteMessage(for summary: ProjectSummary) -> String {
        if model.sharedLibraryStatus.isShared {
            return "This removes \(summary.name) and its PDF and notes from the selected shared folder for every device using that folder. Exported files stay on your device."
        }
        return "This removes \(summary.name) and its copied source PDF from this device. Exported files stay on your device."
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
