import AppKit
import ApplicationServices
import Foundation

enum AccessibilityPermission {
    /// Both checks are required. The radial menu is in-app and works without them;
    /// keyboard and mouse actions are posted with CGEvent and are dropped otherwise.
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let canPost = CGPreflightPostEventAccess()
        return trusted && canPost
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }
}

/// Runs a Shortcut by name. The name is a single argument to `/usr/bin/shortcuts`, never a shell string.
final class ShortcutRunner {
    static let shared = ShortcutRunner()
    private let lock = NSLock()
    private var running = 0
    private let maxRunning = 4

    func run(name: String, status: @escaping (String) -> Void) {
        guard let arguments = CommandSafety.shortcutsArguments(name: name) else {
            status("That Shortcut name can’t be run.")
            return
        }
        let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            status("The Shortcuts command-line tool is not available on this Mac.")
            return
        }
        lock.lock()
        if running >= maxRunning {
            lock.unlock()
            status("Too many Shortcuts are already running.")
            return
        }
        running += 1
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                self.lock.lock()
                self.running -= 1
                self.lock.unlock()
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                status("Couldn’t start that Shortcut.")
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.waitUntilExit()
        }
    }

    func list(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Self.listSync()
            DispatchQueue.main.async {
                completion(names)
            }
        }
    }

    private static func listSync() -> [String] {
        let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return [] }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if process.isRunning { process.terminate() }
        }
        let data = pipe.fileHandleForReading.readData(ofLength: 256 * 1024)
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let name = String(line).trimmingCharacters(in: .whitespaces)
            return CommandSafety.shortcutsArguments(name: name) == nil ? nil : name
        }.prefix(500).map { $0 }
    }
}

enum AppLauncher {
    static func open(_ launch: AppLaunch, status: @escaping (String) -> Void) {
        let workspace = NSWorkspace.shared
        let url: URL?
        if let bundle = launch.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           ProfileSanitizer.isBundleIdentifier(bundle) {
            url = workspace.urlForApplication(withBundleIdentifier: bundle)
        } else if let path = launch.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  ProfileSanitizer.isSafeAppPath(path) {
            url = URL(fileURLWithPath: path)
        } else {
            url = nil
        }
        guard let url, !url.pathComponents.contains("..") else {
            status("Couldn’t find that app.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil {
                status("Couldn’t open \(url.lastPathComponent).")
            }
        }
    }
}

final class FrontmostAppMonitor {
    var onChange: ((String?, String?) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        consider(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.consider(app)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func consider(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        onChange?(app.bundleIdentifier, app.localizedName)
    }
}
