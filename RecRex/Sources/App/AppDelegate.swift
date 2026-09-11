import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()
    private var window: NSWindow?
    private var stageCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
        stageCancellable = appState.$stage
            .removeDuplicates()
            .sink { [weak self] stage in
                if stage == .recording {
                    self?.window?.orderOut(nil)
                }
            }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    /// Switching to RecRex via Cmd+Tab activates the app but, unlike a Dock click, doesn't call
    /// `applicationShouldHandleReopen` — so without this, Cmd+Tab during recording would bring
    /// the app to the foreground with no window to show (the window is hidden while recording).
    func applicationDidBecomeActive(_ notification: Notification) {
        if window?.isVisible != true {
            showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingController = NSHostingController(rootView: RootView(appState: appState))
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "RecRex"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}
