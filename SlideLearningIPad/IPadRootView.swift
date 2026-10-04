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
        .task {
            await model.restoreSharedLibrary()
            await model.refreshSharedLibrary()
            await model.refreshRecentProjects()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await model.refreshSharedLibrary()
                    await model.refreshRecentProjects()
                }
            case .inactive, .background:
                Task { await model.flushActiveProject() }
            @unknown default:
                break
            }
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
