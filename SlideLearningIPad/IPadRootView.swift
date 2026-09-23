import SwiftUI

struct IPadRootView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.screen {
            case .recentProjects:
                IPadRecentProjectsView(model: model)
            case .project:
                if let project = model.activeProject {
                    IPadProjectWorkspaceView(
                        model: project,
                        thumbnailProvider: PDFWorkerThumbnailAdapter(
                            store: model.store,
                            provider: model.thumbnailProvider
                        ),
                        exporter: PDFWorkerExportAdapter(),
                        onBack: { model.closeProject() }
                    )
                    .id(project.project.id)
                } else {
                    ProgressView("Opening project…")
                }
            }
        }
        .task { await model.refreshRecentProjects() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await model.flushActiveProject() }
        }
        .alert("Slide Learning", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        ), presenting: model.error) { _ in
            Button("OK") { model.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}
