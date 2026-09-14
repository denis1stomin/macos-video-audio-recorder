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

    /// Switching to RexGrab via Cmd+Tab activates the app but, unlike a Dock click, doesn't call
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
        newWindow.title = "RexGrab"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        // NSWindow(contentViewController:) doesn't yet reflect SwiftUI's real content size at
        // this point — window.frame is still some AppKit placeholder default. fittingSize forces
        // the layout pass that resolves it to MainWindowView's actual size, so centering below
        // uses the window's real dimensions instead of a stale/default one.
        newWindow.setContentSize(hostingController.view.fittingSize)
        centerOnMainDisplay(newWindow)
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `NSWindow.center()` centers on whichever screen currently has keyboard focus, which at
    /// launch (no window focused yet) isn't reliably the display with the menu bar. This matches
    /// the same "main display" AppState.beginSourceSelection() already preselects via
    /// CGMainDisplayID(), so the window always opens on that one display consistently.
    private func centerOnMainDisplay(_ window: NSWindow) {
        let mainDisplayID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first { screen -> Bool in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == mainDisplayID
        }
        guard let screen = mainScreen ?? NSScreen.main else {
            window.center()
            return
        }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2
        ))
    }
}
