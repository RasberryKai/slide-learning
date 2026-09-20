import Foundation

enum ProjectAction: Sendable {
    case focus(pageIndex: Int)
    case moveFocus(FocusDirection)
    case toggleFocusedSelection
    case setSelection(pageIndex: Int, selected: Bool)
    case updateNote(pageIndex: Int, text: String)
    case setFilter(SlideFilter)
    case setThumbnailSize(ThumbnailSize)
    case setInspectorVisible(Bool)
}
