import Combine
import Foundation

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published private(set) var project: Project
    @Published private(set) var isSaving = false
    @Published var error: ProjectError?

    private let store: ProjectStore
    private var saveTask: Task<Void, Never>?

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
    }

    var selectedCount: Int { project.selectedCount }
    var totalCount: Int { project.pageCount }
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
        let pendingSave = saveTask
        saveTask = nil
        pendingSave?.cancel()
        await pendingSave?.value

        let project = project
        isSaving = true
        do {
            try await store.save(project)
            isSaving = false
            error = nil
            return true
        } catch let error as ProjectError {
            self.error = error
            isSaving = false
            return false
        } catch {
            self.error = .storageFailed(error.localizedDescription)
            isSaving = false
            return false
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = project
        isSaving = true
        saveTask = Task { [weak self, store] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try await store.save(snapshot)
                await MainActor.run {
                    self?.isSaving = false
                    self?.error = nil
                }
            } catch is CancellationError {
                return
            } catch let error as ProjectError {
                await MainActor.run { self?.error = error; self?.isSaving = false }
            } catch {
                await MainActor.run { self?.error = .storageFailed(error.localizedDescription); self?.isSaving = false }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
