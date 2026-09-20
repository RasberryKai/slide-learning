import AppKit
import SwiftUI

struct SlideCellView: View {
    let slide: SlideState
    let pageCount: Int
    let isFocused: Bool
    let width: Double
    let thumbnailProvider: any SlideThumbnailProviding
    let project: Project
    let focus: () -> Void
    let setSelected: (Bool) -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Button(action: focus) {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.richtext")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                        ProgressView().controlSize(.small)
                                    }
                                }
                        }
                    }
                    .frame(width: width, height: width * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isFocused ? Color.accentColor : (slide.isSelected ? Color.primary : Color.secondary.opacity(0.25)), lineWidth: isFocused ? 3 : (slide.isSelected ? 3 : 1))
                }
                .accessibilityLabel("Slide \(slide.pageIndex + 1)")
                .accessibilityHint("Click to focus; selection is controlled separately")
                HStack(spacing: 6) {
                    Button {
                        setSelected(!slide.isSelected)
                    } label: {
                        Image(systemName: slide.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(slide.isSelected ? Color.accentColor : Color.secondary, Color(nsColor: .windowBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(slide.isSelected ? "Deselect slide \(slide.pageIndex + 1)" : "Select slide \(slide.pageIndex + 1)")
                    if !slide.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .help("Has a context note")
                    }
                }
                .padding(7)
            }
            Text("Slide \(slide.pageIndex + 1) of \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: "\(project.id)-\(slide.pageIndex)-\(Int(width))") {
            thumbnail = await thumbnailProvider.thumbnail(for: project, pageIndex: slide.pageIndex, width: width)
        }
    }
}
