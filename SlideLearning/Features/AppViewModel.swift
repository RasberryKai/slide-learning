import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    enum Screen: Equatable {
        case recentProjects
        case project(UUID)
    }

    @Published private(set) var recentProjects: [ProjectSummary] = []
    @Published private(set) var screen: Screen = .recentProjects
    @Published private(set) var activeProject: ProjectViewModel?
    @Published private(set) var sharedLibraryStatus: SharedLibraryStatus = .local
    @Published var error: ProjectError?

    let store: ProjectStore
    let thumbnailProvider: PDFThumbnailProvider

    init(
        store: ProjectStore = ProjectStore(),
        thumbnailProvider: PDFThumbnailProvider = PDFThumbnailProvider()
    ) {
        self.store = store
        self.thumbnailProvider = thumbnailProvider
    }

    func refreshRecentProjects() async {
        sharedLibraryStatus = await store.currentSharedLibraryStatus()
        do { recentProjects = try await store.listRecentProjects() }
        catch let error as ProjectError { self.error = error }
        catch { self.error = .storageFailed(error.localizedDescription) }
    }

    /// Re-reads an open project's authoritative metadata when it is clean.
    /// Callers can follow this with `refreshRecentProjects()` to update the
    /// recent index in the same user action.
    func refreshSharedLibrary() async {
        sharedLibraryStatus = await store.currentSharedLibraryStatus()
        _ = await activeProject?.refreshFromStoreIfClean()
    }

    /// UI integration calls this after a directory picker grants access. The
    /// local library is copied into the selected folder and remains intact.
    func selectSharedLibraryFolder(_ url: URL) async {
        guard await flushActiveProjectBeforeLibrarySwitch() else { return }
        do {
            sharedLibraryStatus = try await store.selectSharedLibrary(at: url)
            activeProject = nil
            screen = .recentProjects
            await refreshRecentProjects()
        } catch let error as ProjectError { self.error = error }
        catch { self.error = .storageFailed(error.localizedDescription) }
    }

    /// Restores the bookmark selected on this device. A failed bookmark is
    /// surfaced as `.unavailable`; local projects are not shown as a fallback.
    func restoreSharedLibrary() async {
        guard await flushActiveProjectBeforeLibrarySwitch() else { return }
        sharedLibraryStatus = await store.restoreSharedLibrary()
        if case .unavailable = sharedLibraryStatus { return }
        activeProject = nil
        screen = .recentProjects
        await refreshRecentProjects()
    }

    func clearSharedLibrary() async {
        guard await flushActiveProjectBeforeLibrarySwitch() else { return }
        await store.clearSharedLibrary()
        sharedLibraryStatus = await store.currentSharedLibraryStatus()
        activeProject = nil
        screen = .recentProjects
        await refreshRecentProjects()
    }

    /// Refreshes the active project only when it has no local edits. This is
    /// intended for scene foreground transitions and does not clobber dirty
    /// notes or preferences.
    @discardableResult
    func refreshActiveProjectIfClean() async -> Bool {
        let refreshed = await activeProject?.refreshFromStoreIfClean() ?? true
        if refreshed { await refreshRecentProjects() }
        return refreshed
    }

    func importProject(from url: URL) async {
        do {
            let project = try await store.createProject(from: url)
            let viewModel = ProjectViewModel(project: project, store: store)
            activeProject = viewModel
            screen = .project(project.id)
            await refreshRecentProjects()
        } catch let error as ProjectError { self.error = error }
        catch { self.error = .importFailed(error.localizedDescription) }
    }

    func openProject(id: UUID) async {
        do {
            let project = try await store.openProject(id: id)
            activeProject = ProjectViewModel(project: project, store: store)
            screen = .project(id)
            await refreshRecentProjects()
        } catch let error as ProjectError { self.error = error }
        catch { self.error = .storageFailed(error.localizedDescription) }
    }

    func closeProject() {
        guard pendingCloseFlush == nil else { return }
        let project = activeProject
        let flush = Task { [weak self] in
            let didFlush = await project?.flush() ?? true
            guard let self else { return }
            guard self.activeProject === project else {
                self.pendingCloseFlush = nil
                return
            }
            guard didFlush else {
                // Keep the workspace alive so the user can see the save error
                // and retry after the storage problem is fixed.
                self.pendingCloseFlush = nil
                return
            }
            self.activeProject = nil
            self.screen = .recentProjects
            self.pendingCloseFlush = nil
            await self.refreshRecentProjects()
        }
        pendingCloseFlush = flush
    }

    func flushActiveProject() async {
        if let pendingCloseFlush { await pendingCloseFlush.value }
        await activeProject?.flush()
    }

    private func flushActiveProjectBeforeLibrarySwitch() async -> Bool {
        if let pendingCloseFlush { await pendingCloseFlush.value }
        return await activeProject?.flush() ?? true
    }

    private var pendingCloseFlush: Task<Void, Never>?

    func deleteProject(id: UUID) async {
        do {
            if let pendingCloseFlush { await pendingCloseFlush.value }
            if case .project(id) = screen {
                await activeProject?.flush()
            }
            let source = await store.sourceURL(id: id)
            await thumbnailProvider.removeCachedThumbnails(for: source)
            try await store.deleteProject(id: id)
            if case .project(id) = screen {
                activeProject = nil
                screen = .recentProjects
            }
            await refreshRecentProjects()
        } catch let error as ProjectError { self.error = error }
        catch { self.error = .storageFailed(error.localizedDescription) }
    }
}
