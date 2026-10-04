import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.screen {
            case .recentProjects:
                RecentProjectsView(model: model)
            case .project:
                if let project = model.activeProject {
                    ProjectWorkspaceView(
                        model: project,
                        thumbnailProvider: PDFWorkerThumbnailAdapter(store: model.store, provider: model.thumbnailProvider),
                        exporter: PDFWorkerExportAdapter()
                    )
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
        .onReceive(NotificationCenter.default.publisher(for: .slideLearningCloseProject)) { _ in
            model.closeProject()
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
