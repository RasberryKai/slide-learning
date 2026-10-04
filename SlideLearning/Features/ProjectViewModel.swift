import Combine
import Foundation

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published private(set) var project: Project
    @Published private(set) var isSaving = false
    @Published var error: ProjectError?

    private let store: ProjectStore
    private var baselineProject: Project
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
        self.baselineProject = project
    }

    var selectedCount: Int { project.selectedCount }
    var totalCount: Int { project.pageCount }
    var hasUnsavedChanges: Bool { project != baselineProject }
    func sourceURL() async -> URL { await store.sourceURL(id: project.id) }
    func managedProjectsRootURL() async -> URL { await store.projectsURL }
    var visibleSlides: [SlideState] {
        project.visiblePageIndices.compactMap { project.slides[safe: $0] }
    }

    func dispatch(_ action: ProjectAction) {
        ProjectReducer.reduce(&project, action: action)
        scheduleSave()
    }

    @discardableResult
    func flush() async -> Bool {
        let task = enqueueSave(debounce: false)
        await task.value
        return !hasUnsavedChanges && error == nil
    }

    private func scheduleSave() {
        _ = enqueueSave(debounce: true)
    }

    private func enqueueSave(debounce: Bool) -> Task<Void, Never> {
        let previous = saveTask
        previous?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        isSaving = true
        let task = Task { [weak self] in
            // Cancellation can stop the debounce, but cannot undo a store
            // write already in progress. Wait for it to update the baseline
            // before starting the next write.
            await previous?.value
            if debounce {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            guard !Task.isCancelled, let self else { return }
            await self.saveCurrentProject(generation: generation)
        }
        saveTask = task
        return task
    }

    private func saveCurrentProject(generation: Int) async {
        guard hasUnsavedChanges else {
            if generation == saveGeneration { isSaving = false }
            return
        }
        let snapshot = project
        let expectedProject = baselineProject
        do {
            try await store.save(snapshot, expectedProject: expectedProject)
            baselineProject = snapshot
            error = nil
        } catch let error as ProjectError {
            self.error = error
        } catch {
            self.error = .storageFailed(error.localizedDescription)
        }
        if generation == saveGeneration { isSaving = false }
    }

    /// Reloads the authoritative shared project only when this view model has
    /// no local edits. Dirty notes and preferences remain in memory for an
    /// explicit retry or conflict-resolution flow.
    @discardableResult
    func refreshFromStoreIfClean() async -> Bool {
        guard !hasUnsavedChanges else { return false }
        do {
            let latest = try await store.loadProject(id: project.id)
            guard !hasUnsavedChanges else { return false }
            project = latest
            baselineProject = latest
            error = nil
            return true
        } catch let error as ProjectError {
            self.error = error
            return false
        } catch {
            self.error = .storageFailed(error.localizedDescription)
            return false
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
