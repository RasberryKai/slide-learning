import SwiftUI

struct RecentProjectRow: View {
    let summary: ProjectSummary
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: availabilityIcon)
                .font(.title2)
                .foregroundStyle(summary.availability == .available ? Color.accentColor : .orange)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name).font(.headline)
                Text(summary.sourceFilename)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if summary.availability == .available {
                    Text("\(summary.selectedCount) of \(summary.pageCount) selected  •  Updated \(summary.updatedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if summary.availability == .available {
                Button("Open", action: open)
                    .buttonStyle(.bordered)
            }
            Button("Delete", role: .destructive, action: delete)
                .buttonStyle(.borderless)
                .help("Delete this project")
        }
        .contentShape(Rectangle())
        .onTapGesture { if summary.availability == .available { open() } }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(summary.name), \(summary.pageCount) pages, \(summary.selectedCount) selected")
    }

    private var availabilityIcon: String {
        summary.availability == .available ? "doc.richtext" : "exclamationmark.triangle"
    }

    private var availabilityMessage: String {
        switch summary.availability {
        case .missingProject: "Project files are missing."
        case .missingSource: "The copied source PDF is missing."
        case .unreadableMetadata: "Project metadata cannot be read."
        case .unreadableSource: "The copied source PDF cannot be read."
        case .available: ""
        }
    }
}
