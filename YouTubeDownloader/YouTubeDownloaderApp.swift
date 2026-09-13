import SwiftUI

@main
struct YouTubeDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, idealWidth: 850, minHeight: 590, idealHeight: 590)
        }
        .windowResizability(.contentMinSize)
    }
}

/// A direct reference to the main window, set once from `ContentView` as
/// soon as it's available. `NSApp.windows` was tried at quit time instead —
/// by then (at least when quit arrives as a remote Apple Event, as it does
/// via `osascript`/Dock/menu) it no longer lists the real SwiftUI-managed
/// window at all, only an unrelated hidden 500×500 placeholder — so scanning
/// it there silently found nothing and the "remember size?" prompt never
/// fired. Holding the reference from earlier sidesteps that entirely.
enum MainWindowHolder {
    static var window: NSWindow?
}

/// Asks, on quit, whether to remember a window size the user dragged to a
/// different shape — but only if they actually resized it this run, so
/// quitting without touching the window never nags.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// This is a single-window utility app — closing that window (the red
    /// traffic light) should quit the app like Calculator or Preview do,
    /// not leave it running with no visible window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let window = MainWindowHolder.window else { return .terminateNow }

        let defaults = UserDefaults.standard
        let lastWidth = defaults.double(forKey: "lastAppliedWindowWidth")
        let lastHeight = defaults.double(forKey: "lastAppliedWindowHeight")
        let current = window.frame.size

        let changed = abs(current.width - lastWidth) > 2 || abs(current.height - lastHeight) > 2
        guard changed else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = tr("Запомнить размер окна?")
        alert.informativeText = trf("Вы изменили размер окна — использовать этот размер (%d×%d) при следующем запуске?",
                                     Int(current.width), Int(current.height))
        alert.addButton(withTitle: tr("Запомнить"))
        alert.addButton(withTitle: tr("Не запоминать"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            defaults.set(Double(current.width), forKey: "rememberedWindowWidth")
            defaults.set(Double(current.height), forKey: "rememberedWindowHeight")
        } else {
            defaults.removeObject(forKey: "rememberedWindowWidth")
            defaults.removeObject(forKey: "rememberedWindowHeight")
        }
        return .terminateNow
    }
}
