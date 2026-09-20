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
        do { recentProjects = try await store.listRecentProjects() }
        catch let error as ProjectError { self.error = error }
        catch { self.error = .storageFailed(error.localizedDescription) }
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
            await project?.flush()
            guard let self, self.activeProject === project else { return }
            self.activeProject = nil
            self.screen = .recentProjects
            await self.refreshRecentProjects()
            self.pendingCloseFlush = nil
        }
        pendingCloseFlush = flush
    }

    func flushActiveProject() async {
        if let pendingCloseFlush { await pendingCloseFlush.value }
        await activeProject?.flush()
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
