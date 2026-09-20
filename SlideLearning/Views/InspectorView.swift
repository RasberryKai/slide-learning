import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: ProjectViewModel
    let thumbnailProvider: any SlideThumbnailProviding
    var notesFocused: FocusState<Bool>.Binding
    @State private var noteSelection: TextSelection?

    var body: some View {
        if let focused = focusedSlide {
            VStack(alignment: .leading, spacing: 0) {
                InspectorPreview(slide: focused, project: model.project, provider: thumbnailProvider)
                    .id(model.project.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
                if model.project.viewPreferences.inspectorVisible {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Notes — Slide \(focused.pageIndex + 1)").font(.headline)
                            Spacer()
                            Text("Esc to return to slides").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Add one or two sentences of context for this slide.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { model.project.slides[focused.pageIndex].note },
                            set: { model.dispatch(.updateNote(pageIndex: focused.pageIndex, text: $0)) }
                        ), selection: $noteSelection)
                        .focused(notesFocused)
                        .onAppear {
                            if notesFocused.wrappedValue {
                                let note = model.project.slides[focused.pageIndex].note
                                noteSelection = TextSelection(insertionPoint: note.endIndex)
                            }
                        }
                        .onChange(of: notesFocused.wrappedValue) { _, isFocused in
                            if isFocused {
                                let note = model.project.slides[focused.pageIndex].note
                                noteSelection = TextSelection(insertionPoint: note.endIndex)
                            }
                        }
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)) }
                        .frame(height: 110)
                        .accessibilityLabel("Notes for slide \(focused.pageIndex + 1)")
                    }
                    .padding(18)
                }
            }
        } else {
            ContentUnavailableView("No slide focused", systemImage: "sidebar.right", description: Text("Select a slide to inspect it."))
        }
    }

    private var focusedSlide: SlideState? {
        guard let index = model.project.viewPreferences.focusedPageIndex else { return nil }
        return model.project.slides.first { $0.pageIndex == index }
    }
}

private struct InspectorPreview: View {
    let slide: SlideState
    let project: Project
    let provider: any SlideThumbnailProviding
    @State private var previews: [Int: NSImage] = [:]

    var body: some View {
        Group {
            if let thumbnail = previews[slide.pageIndex] {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "preview-\(project.id)-\(slide.pageIndex)") {
            // Keep full-size previews ready for the next five slides. Read them
            // directly in body so advancing to a cached slide never shows a placeholder.
            let upcoming = project.slides
                .lazy
                .map(\.pageIndex)
                .filter { $0 > slide.pageIndex }
                .prefix(5)
            let pageIndices = [slide.pageIndex] + Array(upcoming)
            let retainedPages = Set(pageIndices)
            previews = previews.filter { retainedPages.contains($0.key) }

            // Load the focused slide first, then warm the lookahead sequentially.
            // SwiftUI cancels this task when focus changes or the preview disappears.
            for pageIndex in pageIndices {
                guard !Task.isCancelled else { return }
                guard previews[pageIndex] == nil else { continue }
                let rendered = await provider.thumbnail(for: project, pageIndex: pageIndex, width: 1600)
                guard !Task.isCancelled else { return }
                previews[pageIndex] = rendered
            }
        }
    }
}
