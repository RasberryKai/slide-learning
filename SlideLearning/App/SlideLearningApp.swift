import SwiftUI

@main
struct SlideLearningApp: App {
    @StateObject private var appModel: AppViewModel
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate

    init() {
        let store = ProjectStore(validator: PDFKitValidator())
        _appModel = StateObject(wrappedValue: AppViewModel(store: store))
        applicationDelegate.model = appModel
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: appModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
