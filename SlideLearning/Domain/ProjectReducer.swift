import Foundation

enum ProjectReducer {
    static func reduce(_ project: inout Project, action: ProjectAction, now: Date = Date()) {
        switch action {
        case .focus(let pageIndex):
            guard valid(pageIndex, in: project) else { return }
            project.viewPreferences.focusedPageIndex = pageIndex

        case .moveFocus(let direction):
            let visible = project.visiblePageIndices
            guard !visible.isEmpty else {
                project.viewPreferences.focusedPageIndex = nil
                return
            }
            guard let focused = project.viewPreferences.focusedPageIndex,
                  let position = visible.firstIndex(of: focused) else {
                project.viewPreferences.focusedPageIndex = direction == .previous ? visible.last : visible.first
                return
            }
            let offset = direction == .previous ? -1 : 1
            let newPosition = position + offset
            guard visible.indices.contains(newPosition) else { return }
            project.viewPreferences.focusedPageIndex = visible[newPosition]

        case .toggleFocusedSelection:
            guard let focused = project.viewPreferences.focusedPageIndex,
                  valid(focused, in: project) else { return }
            setSelection(&project, pageIndex: focused, selected: !project.slides[focused].isSelected)

        case .setSelection(let pageIndex, let selected):
            guard valid(pageIndex, in: project) else { return }
            setSelection(&project, pageIndex: pageIndex, selected: selected)

        case .updateNote(let pageIndex, let text):
            guard valid(pageIndex, in: project) else { return }
            let oldText = project.slides[pageIndex].note
            project.slides[pageIndex].note = text
            if oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project.slides[pageIndex].isSelected = true
            }

        case .setFilter(let filter):
            project.viewPreferences.filter = filter
            normalizeFocus(&project)

        case .setThumbnailSize(let size):
            project.viewPreferences.thumbnailSize = size

        case .setInspectorVisible(let visible):
            project.viewPreferences.inspectorVisible = visible
        }
        project.updatedAt = now
    }

    private static func valid(_ pageIndex: Int, in project: Project) -> Bool {
        project.slides.indices.contains(pageIndex) && project.slides[pageIndex].pageIndex == pageIndex
    }

    private static func setSelection(_ project: inout Project, pageIndex: Int, selected: Bool) {
        let wasFocused = project.viewPreferences.focusedPageIndex == pageIndex
        let oldVisible = project.visiblePageIndices
        project.slides[pageIndex].isSelected = selected

        guard !selected, wasFocused, project.viewPreferences.filter == .selected else { return }
        guard let oldPosition = oldVisible.firstIndex(of: pageIndex) else { return }
        let remaining = oldVisible.filter { project.slides[$0].isSelected }
        if let next = remaining.first(where: { oldVisible.firstIndex(of: $0)! > oldPosition }) {
            project.viewPreferences.focusedPageIndex = next
        } else if let previous = remaining.last(where: { oldVisible.firstIndex(of: $0)! < oldPosition }) {
            project.viewPreferences.focusedPageIndex = previous
        } else {
            project.viewPreferences.focusedPageIndex = nil
        }
    }

    private static func normalizeFocus(_ project: inout Project) {
        let visible = project.visiblePageIndices
        guard !visible.isEmpty else {
            project.viewPreferences.focusedPageIndex = nil
            return
        }
        if let focused = project.viewPreferences.focusedPageIndex, visible.contains(focused) { return }
        project.viewPreferences.focusedPageIndex = visible.first
    }
}
