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
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.engine.setDevicesVisible(model.sidebar == .devices)
            return
        }
        let host = NSHostingController(rootView: EditorView().environmentObject(model))
        let window = NSWindow(contentViewController: host)
        window.title = "Gamepad Keymapper"
        window.setContentSize(NSSize(width: 1180, height: 740))
        window.minSize = NSSize(width: 1000, height: 640)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.engine.setDevicesVisible(model.sidebar == .devices)
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
