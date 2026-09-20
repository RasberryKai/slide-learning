import AppKit
import SwiftUI

struct WorkspaceKeyMonitor: NSViewRepresentable {
    let onMove: (FocusDirection) -> Void
    let onToggle: () -> Void
    let onType: (String) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.onMove = onMove
        view.onToggle = onToggle
        view.onType = onType
        return view
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.onMove = onMove
        nsView.onToggle = onToggle
        nsView.onType = onType
    }
}

@MainActor
final class KeyMonitorView: NSView {
    var onMove: ((FocusDirection) -> Void)?
    var onToggle: (() -> Void)?
    var onType: ((String) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            removeMonitor()
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.attachedSheet == nil else { return event }
            if self.isEditingText(window.firstResponder) {
                if event.keyCode == 53 { // Escape ends note/text editing.
                    _ = window.makeFirstResponder(nil)
                    return nil
                }
                return event
            }
            // Leave application shortcuts to the normal responder chain.
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return event }
            switch event.keyCode {
            case 49:
                self.onToggle?()
                return nil
            case 123, 126:
                self.onMove?(.previous)
                return nil
            case 124, 125:
                self.onMove?(.next)
                return nil
            default:
                if let text = event.characters, !text.isEmpty,
                   text.unicodeScalars.allSatisfy({
                       !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
                   }), self.onType?(text) == true {
                    return nil
                }
                return event
            }
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    private func isEditingText(_ responder: NSResponder?) -> Bool {
        var current = responder
        while let item = current {
            if item is NSTextView || item is NSTextField { return true }
            current = item.nextResponder
        }
        return false
    }
}
