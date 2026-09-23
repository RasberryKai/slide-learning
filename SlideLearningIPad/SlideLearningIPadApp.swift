import SwiftUI

@main
struct SlideLearningIPadApp: App {
    @StateObject private var appModel: AppViewModel

    init() {
        let store = ProjectStore(validator: PDFKitValidator())
        _appModel = StateObject(wrappedValue: AppViewModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            IPadRootView(model: appModel)
                .preferredColorScheme(.dark)
        }
    }
}
