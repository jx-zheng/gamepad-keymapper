import AppKit
import SwiftUI

@main
struct GamepadKeymapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    /// Loads the shared glyph before the status item so template rendering sticks.
    private let menuBarTemplate: Void = {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
        }
    }()

    var body: some Scene {
        MenuBarExtra("Gamepad Keymapper", image: "MenuBarIcon") {
            MenuBarContent()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The plist is a menu-bar agent. Become a normal app only while the editor
        // window exists, including when it is miniaturized, so the Dock can restore it.
        if EditorWindow.isOpen {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A miniaturized editor reports no visible windows (`flag` is false) but is still open.
        if EditorWindow.isOpen {
            EditorWindow.restoreFromDock()
        }
        return flag || EditorWindow.isOpen
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

    /// True while the editor window is on screen or miniaturized. A closed window is not open.
    static var isOpen: Bool {
        guard let window = controller?.window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    /// Clicking the Dock icon restores the same editor. Miniaturize does not close the window.
    @MainActor
    static func restoreFromDock() {
        guard let window = controller?.window else { return }
        // Stay a regular app so the Dock tile remains the way back.
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    static func show(model: AppModel) {
        windowDelegate.model = model
        // LSUIElement stays true in Info.plist. A regular policy while this window
        // exists (including miniaturized) puts an icon in the Dock. Closing the
        // window, not minimizing it, returns to a menu-bar-only agent.
        NSApp.setActivationPolicy(.regular)
        if let controller {
            if controller.contentViewController == nil {
                controller.contentViewController = makeHost(model)
            }
            if let window = controller.window {
                applyUsableFrame(window, resetIfCramped: true)
            }
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.engine.setDevicesVisible(model.sidebar == .devices)
            return
        }
        let window = NSWindow(contentViewController: makeHost(model))
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

    /// Releases the editor view after the window closes. The window controller stays so the frame can be reused.
    static func releaseContent() {
        controller?.contentViewController = nil
    }

    private static func makeHost(_ model: AppModel) -> NSViewController {
        let host = NSHostingController(rootView: EditorView().environmentObject(model))
        host.sizingOptions = []
        return host
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
        // Close hides the editor and drops the Dock icon. Miniaturize does not
        // send this, so the yellow button leaves a Dock tile that restores the window.
        NSApp.setActivationPolicy(.accessory)
        // Drop the SwiftUI tree. A closed editor should not keep form state or the Devices timer alive.
        EditorWindow.releaseContent()
        Task { @MainActor in
            model?.engine.setDevicesVisible(false)
            model?.disarmCapture()
        }
    }
}
