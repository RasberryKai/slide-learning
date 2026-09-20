import SwiftUI

struct SlideGridView: View {
    @ObservedObject var model: ProjectViewModel
    let thumbnailProvider: any SlideThumbnailProviding

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { viewport in
                // Keep the single-column sidebar scrollable within the window.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.visibleSlides) { slide in
                                SlideCellView(
                                    slide: slide,
                                    pageCount: model.totalCount,
                                    isFocused: model.project.viewPreferences.focusedPageIndex == slide.pageIndex,
                                    width: model.project.viewPreferences.thumbnailSize.width,
                                    thumbnailProvider: thumbnailProvider,
                                    project: model.project,
                                    focus: { model.dispatch(.focus(pageIndex: slide.pageIndex)) },
                                    setSelected: { model.dispatch(.setSelection(pageIndex: slide.pageIndex, selected: $0)) }
                                )
                                .id(slide.pageIndex)
                            }
                        }
                    }
                    .frame(width: max(1, viewport.size.width - 40), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                }
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .scrollIndicators(.automatic)
                .onChange(of: model.project.viewPreferences.focusedPageIndex) { _, focused in
                    guard let focused else { return }
                    DispatchQueue.main.async { scrollProxy.scrollTo(focused, anchor: .center) }
                }
            }
        }
        .overlay {
            if model.visibleSlides.isEmpty {
                ContentUnavailableView("No selected slides", systemImage: "checkmark.circle", description: Text("Select slides in the All view to see them here."))
            }
        }
    }
}
