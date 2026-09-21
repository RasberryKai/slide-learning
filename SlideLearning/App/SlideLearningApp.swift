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
        .commands {
            SlideCommands()
        }
    }
}

private struct CopySlideActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var copySlide: (() -> Void)? {
        get { self[CopySlideActionKey.self] }
        set { self[CopySlideActionKey.self] = newValue }
    }
}

private struct SlideCommands: Commands {
    @FocusedValue(\.copySlide) private var copySlide

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Copy Slide", action: { copySlide?() })
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(copySlide == nil)
        }
    }
}
