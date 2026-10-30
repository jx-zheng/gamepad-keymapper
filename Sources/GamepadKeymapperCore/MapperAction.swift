import Foundation

enum MouseButtonKind: String, Equatable, Hashable, Codable, CaseIterable {
    case left
    case right
    case middle

    var displayName: String {
        switch self {
        case .left: return "Left click"
        case .right: return "Right click"
        case .middle: return "Middle click"
        }
    }
}

enum MediaKey: String, Equatable, Hashable, Codable, CaseIterable {
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    var displayName: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        }
    }
}

struct AppLaunch: Equatable, Hashable, Codable {
    var bundleIdentifier: String?
    var path: String?

    init(bundleIdentifier: String? = nil, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }

    var isEmpty: Bool {
        let bundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let file = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundle.isEmpty && file.isEmpty
    }

    var summary: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "Open \(bundleIdentifier)"
        }
        if let path, !path.isEmpty {
            return "Open \(path)"
        }
        return "Open app"
    }
}

enum MapperAction: Equatable, Hashable {
    case keyboard(KeyboardCommand)
    case media(MediaKey)
    case mouseClick(MouseButtonKind, clicks: Int)
    case mouseScroll(dx: Double, dy: Double)
    case mouseMove(dx: Double, dy: Double)
    case typeText(String)
    case shortcut(name: String)
    case launchApp(AppLaunch)

    /// When true, the action starts on press and stops on release (mouse drag, held keys).
    var sustainsWhileHeld: Bool {
        switch self {
        case .keyboard(let command):
            return command.holdLast
        case .mouseClick(_, let clicks):
            return clicks <= 1
        case .mouseMove:
            return true
        case .media, .mouseScroll, .typeText, .shortcut, .launchApp:
            return false
        }
    }

    var summary: String {
        switch self {
        case .keyboard(let command):
            let parts = command.steps.map {
                KeyCatalog.chordLabel(keyCode: $0.keyCode, modifiers: $0.modifiers)
            }
            let joined = parts.isEmpty ? "Keyboard" : parts.joined(separator: " then ")
            return command.holdLast ? joined + " (hold)" : joined
        case .media(let key):
            return key.displayName
        case .mouseClick(let button, let clicks):
            return clicks <= 1 ? button.displayName : "\(button.displayName) ×\(clicks)"
        case .mouseScroll(let dx, let dy):
            return String(format: "Scroll %.0f, %.0f", dx, dy)
        case .mouseMove(let dx, let dy):
            return String(format: "Move %.0f, %.0f", dx, dy)
        case .typeText(let text):
            let shown = text.count > 28 ? String(text.prefix(28)) + "…" : text
            return "Type “\(shown)”"
        case .shortcut(let name):
            return "Shortcut “\(name)”"
        case .launchApp(let launch):
            return launch.summary
        }
    }
}

extension MapperAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case holdLast
        case steps
        case key
        case button
        case clicks
        case dx
        case dy
        case text
        case name
        case bundleIdentifier
        case path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "keyboard":
            let steps = try container.decodeIfPresent([KeyStep].self, forKey: .steps) ?? []
            let holdLast = try container.decodeIfPresent(Bool.self, forKey: .holdLast) ?? false
            self = .keyboard(KeyboardCommand(steps: steps, holdLast: holdLast))
        case "media":
            self = .media(try container.decode(MediaKey.self, forKey: .key))
        case "mouseClick":
            let button = try container.decode(MouseButtonKind.self, forKey: .button)
            let clicks = try container.decodeIfPresent(Int.self, forKey: .clicks) ?? 1
            self = .mouseClick(button, clicks: max(1, clicks))
        case "mouseScroll":
            let dx = try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0
            let dy = try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
            self = .mouseScroll(dx: dx, dy: dy)
        case "mouseMove":
            let dx = try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0
            let dy = try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
            self = .mouseMove(dx: dx, dy: dy)
        case "typeText":
            self = .typeText(try container.decode(String.self, forKey: .text))
        case "shortcut":
            self = .shortcut(name: try container.decode(String.self, forKey: .name))
        case "launchApp":
            let bundle = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            let path = try container.decodeIfPresent(String.self, forKey: .path)
            self = .launchApp(AppLaunch(bundleIdentifier: bundle, path: path))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyboard(let command):
            try container.encode("keyboard", forKey: .type)
            try container.encode(command.holdLast, forKey: .holdLast)
            try container.encode(command.steps, forKey: .steps)
        case .media(let key):
            try container.encode("media", forKey: .type)
            try container.encode(key, forKey: .key)
        case .mouseClick(let button, let clicks):
            try container.encode("mouseClick", forKey: .type)
            try container.encode(button, forKey: .button)
            try container.encode(clicks, forKey: .clicks)
        case .mouseScroll(let dx, let dy):
            try container.encode("mouseScroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .mouseMove(let dx, let dy):
            try container.encode("mouseMove", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .typeText(let text):
            try container.encode("typeText", forKey: .type)
            try container.encode(text, forKey: .text)
        case .shortcut(let name):
            try container.encode("shortcut", forKey: .type)
            try container.encode(name, forKey: .name)
        case .launchApp(let launch):
            try container.encode("launchApp", forKey: .type)
            try container.encodeIfPresent(launch.bundleIdentifier, forKey: .bundleIdentifier)
            try container.encodeIfPresent(launch.path, forKey: .path)
        }
    }
}
