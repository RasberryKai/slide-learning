import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var model: AppViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            await model.flushActiveProject()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
