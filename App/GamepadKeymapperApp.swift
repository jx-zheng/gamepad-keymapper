import AppKit
import SwiftUI

@main
struct GamepadKeymapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Gamepad Keymapper", systemImage: "gamecontroller.fill") {
            MenuBarContent()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared?.shutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum EditorWindow {
    private static var controller: NSWindowController?
    private static let windowDelegate = EditorWindowDelegate()

    @MainActor
    static func show(model: AppModel) {
        windowDelegate.model = model
        if let controller {
            if let window = controller.window {
                applyUsableFrame(window, resetIfCramped: true)
            }
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.engine.setDevicesVisible(model.sidebar == .devices)
            return
        }
        let host = NSHostingController(rootView: EditorView().environmentObject(model))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Gamepad Keymapper"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        window.minSize = NSSize(width: EditorMetrics.minimumWidth, height: EditorMetrics.minimumHeight)
        window.setContentSize(NSSize(width: EditorMetrics.defaultWidth, height: EditorMetrics.defaultHeight))
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.engine.setDevicesVisible(model.sidebar == .devices)
    }

    /// Keeps a restored or previously resized window from opening smaller than the layout can show.
    private static func applyUsableFrame(_ window: NSWindow, resetIfCramped: Bool) {
        let minimum = NSSize(width: EditorMetrics.minimumWidth, height: EditorMetrics.minimumHeight)
        window.minSize = minimum
        let content = window.contentRect(forFrameRect: window.frame).size
        let cramped = content.width < minimum.width || content.height < minimum.height
        if resetIfCramped && cramped {
            window.setContentSize(NSSize(width: EditorMetrics.defaultWidth, height: EditorMetrics.defaultHeight))
        }
    }
}

private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    weak var model: AppModel?

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            model?.engine.setDevicesVisible(false)
            model?.disarmCapture()
        }
    }
}
