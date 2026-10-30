import AppKit
import SwiftUI

struct ActionEditor: View {
    let action: MapperAction
    var shortcutNames: [String]
    var onChange: (MapperAction) -> Void
    var onTest: () -> Void
    var onRefreshShortcuts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Action", selection: kindBinding) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            editor
            Button("Try Action") { onTest() }
                .disabled(!canTry(action))
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch action {
        case .keyboard(let command):
            keyboardEditor(command)
        case .media(let key):
            Picker("Media key", selection: Binding(
                get: { key },
                set: { onChange(.media($0)) }
            )) {
                ForEach(MediaKey.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        case .mouseClick(let button, let clicks):
            Picker("Button", selection: Binding(
                get: { button },
                set: { onChange(.mouseClick($0, clicks: clicks)) }
            )) {
                ForEach(MouseButtonKind.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Stepper("Clicks: \(clicks)", value: Binding(
                get: { clicks },
                set: { onChange(.mouseClick(button, clicks: min(4, max(1, $0)))) }
            ), in: 1...4)
        case .mouseScroll(let dx, let dy):
            numberField("Horizontal", value: dx) { onChange(.mouseScroll(dx: $0, dy: dy)) }
            numberField("Vertical", value: dy) { onChange(.mouseScroll(dx: dx, dy: $0)) }
            Text("Positive vertical scrolls up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .mouseMove(let dx, let dy):
            numberField("X pixels / second", value: dx) { onChange(.mouseMove(dx: $0, dy: dy)) }
            numberField("Y pixels / second", value: dy) { onChange(.mouseMove(dx: dx, dy: $0)) }
            Text("Positive Y moves the pointer down. The nudge repeats while the button is held.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .typeText(let text):
            TextField("Snippet", text: Binding(
                get: { text },
                set: { onChange(.typeText(String($0.prefix(ProfileSanitizer.maxSnippetLength)))) }
            ), axis: .vertical)
            .lineLimit(3...6)
        case .shortcut(let name):
            TextField("Shortcut name", text: Binding(
                get: { name },
                set: { onChange(.shortcut(name: String($0.prefix(ProfileSanitizer.maxShortcutLength)))) }
            ))
            if !shortcutNames.isEmpty {
                Picker("On this Mac", selection: Binding(
                    get: { name },
                    set: { onChange(.shortcut(name: $0)) }
                )) {
                    Text("Choose").tag("")
                    ForEach(shortcutNames, id: \.self) { shortcut in
                        Text(shortcut).tag(shortcut)
                    }
                }
            }
            Button("Refresh Shortcut List", action: onRefreshShortcuts)
            Text("The name is passed as one argument to the shortcuts tool. It is not a shell command.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .launchApp(let launch):
            TextField("Bundle id", text: Binding(
                get: { launch.bundleIdentifier ?? "" },
                set: { onChange(.launchApp(AppLaunch(bundleIdentifier: $0, path: launch.path))) }
            ))
            TextField("Or .app path", text: Binding(
                get: { launch.path ?? "" },
                set: { onChange(.launchApp(AppLaunch(bundleIdentifier: launch.bundleIdentifier, path: $0))) }
            ))
            Text("Use a bundle id such as com.apple.TextEdit, or an absolute path ending in .app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func keyboardEditor(_ command: KeyboardCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(command.steps.enumerated()), id: \.offset) { index, step in
                HStack {
                    Picker("Key", selection: Binding(
                        get: { step.keyCode },
                        set: { code in
                            var copy = command
                            copy.steps[index].keyCode = code
                            onChange(.keyboard(copy))
                        }
                    )) {
                        ForEach(KeyCatalog.entries, id: \.keyCode) { entry in
                            Text(entry.display).tag(entry.keyCode)
                        }
                    }
                }
                KeyCaptureField { code, modifiers in
                    var copy = command
                    guard copy.steps.indices.contains(index) else { return }
                    copy.steps[index].keyCode = code
                    copy.steps[index].modifiers = modifiers
                    onChange(.keyboard(copy))
                }
                .frame(height: 28)
                modifierToggles(step: step) { modifiers in
                    var copy = command
                    copy.steps[index].modifiers = modifiers
                    onChange(.keyboard(copy))
                }
                if command.steps.count > 1 {
                    Button("Remove Step") {
                        var copy = command
                        copy.steps.remove(at: index)
                        onChange(.keyboard(copy))
                    }
                }
            }
            Toggle("Hold while the button is held", isOn: Binding(
                get: { command.holdLast },
                set: { hold in
                    var copy = command
                    copy.holdLast = hold
                    onChange(.keyboard(copy))
                }
            ))
            Button("Add Step") {
                var copy = command
                copy.steps.append(KeyStep(named: "space"))
                onChange(.keyboard(copy))
            }
            .disabled(command.steps.count >= 8)
            Text("Click “Key” then press a key on your keyboard. This field does not watch other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func modifierToggles(step: KeyStep, onChange modifiersChanged: @escaping (KeyModifiers) -> Void) -> some View {
        let flags: [(String, KeyModifiers)] = [
            ("⌘", .command), ("⇧", .shift), ("⌥", .option), ("⌃", .control), ("fn", .function)
        ]
        return HStack {
            ForEach(flags, id: \.0) { label, flag in
                Toggle(label, isOn: Binding(
                    get: { step.modifiers.contains(flag) },
                    set: { on in
                        var mods = step.modifiers
                        if on { mods.insert(flag) } else { mods.remove(flag) }
                        modifiersChanged(mods)
                    }
                ))
                .toggleStyle(.button)
            }
        }
    }

    private func numberField(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
            TextField(title, value: Binding(
                get: { value },
                set: { set($0.isFinite ? min(4000, max(-4000, $0)) : 0) }
            ), format: .number)
            .frame(minWidth: 72, idealWidth: 90, maxWidth: 120)
        }
    }

    private func canTry(_ action: MapperAction) -> Bool {
        switch action {
        case .launchApp(let launch):
            return !launch.isEmpty
        case .shortcut(let name):
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { ActionKind(action) },
            set: { onChange($0.defaultAction) }
        )
    }
}

private enum ActionKind: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard"
    case media = "Media Key"
    case mouseClick = "Mouse Click"
    case mouseScroll = "Scroll"
    case mouseMove = "Pointer Nudge"
    case typeText = "Text Snippet"
    case shortcut = "Shortcut"
    case launchApp = "Open App"

    var id: String { rawValue }

    init(_ action: MapperAction) {
        switch action {
        case .keyboard: self = .keyboard
        case .media: self = .media
        case .mouseClick: self = .mouseClick
        case .mouseScroll: self = .mouseScroll
        case .mouseMove: self = .mouseMove
        case .typeText: self = .typeText
        case .shortcut: self = .shortcut
        case .launchApp: self = .launchApp
        }
    }

    var defaultAction: MapperAction {
        switch self {
        case .keyboard: return .keyboard(.tap("space"))
        case .media: return .media(.playPause)
        case .mouseClick: return .mouseClick(.left, clicks: 1)
        case .mouseScroll: return .mouseScroll(dx: 0, dy: 40)
        case .mouseMove: return .mouseMove(dx: 0, dy: -400)
        case .typeText: return .typeText("")
        case .shortcut: return .shortcut(name: "")
        case .launchApp: return .launchApp(AppLaunch(bundleIdentifier: "com.apple.TextEdit"))
        }
    }
}

struct KeyCaptureField: NSViewRepresentable {
    var onKey: (UInt16, KeyModifiers) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKey = onKey
    }
}

final class KeyCaptureNSView: NSView {
    var onKey: ((UInt16, KeyModifiers) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        let text = "Click here, then press a key"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        text.draw(at: NSPoint(x: 8, y: 6), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    private func record(_ event: NSEvent) {
        var modifiers = KeyModifiers()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        // Arrows, function keys, and navigation keys report .function even when Fn is not held.
        if event.modifierFlags.contains(.function), !Self.ignoresFunctionFlag(event.keyCode) {
            modifiers.insert(.function)
        }
        onKey?(event.keyCode, modifiers)
    }

    private static func ignoresFunctionFlag(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120, 122:
            return true
        case 64, 79, 80:
            return true
        case 114, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }
}
