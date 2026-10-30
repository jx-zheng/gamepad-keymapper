import Foundation

/// US-ANSI virtual key codes used by `CGEvent` keyboard events.
/// Names are the on-disk spelling in profile JSON (`"key": "c"`).
enum KeyCatalog {
    struct Entry: Equatable {
        var name: String
        var keyCode: UInt16
        var display: String
    }

    static let entries: [Entry] = {
        var list: [Entry] = []
        func add(_ name: String, _ code: UInt16, _ display: String? = nil) {
            list.append(Entry(name: name, keyCode: code, display: display ?? name))
        }

        let letters: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5),
            ("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11), ("q", 12),
            ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31),
            ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40),
            ("n", 45), ("m", 46)
        ]
        for (name, code) in letters {
            add(name, code, name.uppercased())
        }

        let digits: [(String, UInt16)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23),
            ("6", 22), ("7", 26), ("8", 28), ("9", 25), ("0", 29)
        ]
        for (name, code) in digits {
            add(name, code)
        }

        add("return", 36, "Return")
        add("tab", 48, "Tab")
        add("space", 49, "Space")
        add("delete", 51, "Delete")
        add("escape", 53, "Escape")
        add("command", 55, "Command")
        add("shift", 56, "Shift")
        add("capsLock", 57, "Caps Lock")
        add("option", 58, "Option")
        add("control", 59, "Control")
        add("function", 63, "Fn")
        add("f1", 122, "F1")
        add("f2", 120, "F2")
        add("f3", 99, "F3")
        add("f4", 118, "F4")
        add("f5", 96, "F5")
        add("f6", 97, "F6")
        add("f7", 98, "F7")
        add("f8", 100, "F8")
        add("f9", 101, "F9")
        add("f10", 109, "F10")
        add("f11", 103, "F11")
        add("f12", 111, "F12")
        add("home", 115, "Home")
        add("pageUp", 116, "Page Up")
        add("forwardDelete", 117, "Forward Delete")
        add("end", 119, "End")
        add("pageDown", 121, "Page Down")
        add("leftArrow", 123, "Left Arrow")
        add("rightArrow", 124, "Right Arrow")
        add("downArrow", 125, "Down Arrow")
        add("upArrow", 126, "Up Arrow")
        add("minus", 27, "-")
        add("equal", 24, "=")
        add("leftBracket", 33, "[")
        add("rightBracket", 30, "]")
        add("backslash", 42, "\\")
        add("semicolon", 41, ";")
        add("quote", 39, "'")
        add("comma", 43, ",")
        add("period", 47, ".")
        add("slash", 44, "/")
        add("grave", 50, "`")
        return list
    }()

    static func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    static func entry(code: UInt16) -> Entry? {
        entries.first { $0.keyCode == code }
    }

    static func require(_ name: String) -> Entry {
        guard let entry = entry(named: name) else {
            preconditionFailure("Unknown key catalog name \(name)")
        }
        return entry
    }

    static func chordLabel(keyCode: UInt16, modifiers: KeyModifiers) -> String {
        let key = entry(code: keyCode)?.display ?? "key \(keyCode)"
        return modifiers.symbolPrefix + key
    }
}

struct KeyModifiers: OptionSet, Equatable, Hashable {
    var rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
    static let function = KeyModifiers(rawValue: 1 << 4)

    private static let encodeOrder: [(KeyModifiers, String)] = [
        (.control, "control"),
        (.option, "option"),
        (.shift, "shift"),
        (.command, "command"),
        (.function, "function")
    ]

    var symbolPrefix: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        if contains(.function) { text += "fn " }
        return text
    }

    var names: [String] {
        Self.encodeOrder.compactMap { flag, name in contains(flag) ? name : nil }
    }
}

extension KeyModifiers: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let names = try container.decode([String].self)
        var value = KeyModifiers()
        for name in names {
            switch name {
            case "command": value.insert(.command)
            case "shift": value.insert(.shift)
            case "option": value.insert(.option)
            case "control": value.insert(.control)
            case "function": value.insert(.function)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown modifier \(name)"
                )
            }
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(names)
    }
}

struct KeyStep: Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: KeyModifiers
    var delayMilliseconds: Int

    init(keyCode: UInt16, modifiers: KeyModifiers = [], delayMilliseconds: Int = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.delayMilliseconds = delayMilliseconds
    }

    init(named name: String, modifiers: KeyModifiers = [], delayMilliseconds: Int = 0) {
        self.init(
            keyCode: KeyCatalog.require(name).keyCode,
            modifiers: modifiers,
            delayMilliseconds: delayMilliseconds
        )
    }
}

extension KeyStep: Codable {
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
        case delayMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let spelling = try container.decode(String.self, forKey: .key)
        if let entry = KeyCatalog.entry(named: spelling) {
            keyCode = entry.keyCode
        } else if let code = UInt16(spelling), String(code) == spelling {
            keyCode = code
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .key,
                in: container,
                debugDescription: "Unknown key \(spelling)"
            )
        }
        modifiers = try container.decodeIfPresent(KeyModifiers.self, forKey: .modifiers) ?? []
        delayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .delayMilliseconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let entry = KeyCatalog.entry(code: keyCode) {
            try container.encode(entry.name, forKey: .key)
        } else {
            try container.encode(String(keyCode), forKey: .key)
        }
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(delayMilliseconds, forKey: .delayMilliseconds)
    }
}

/// One or more keystrokes. `holdLast` keeps the final step down until the controller button is released.
struct KeyboardCommand: Equatable, Hashable, Codable {
    var steps: [KeyStep]
    var holdLast: Bool

    init(steps: [KeyStep], holdLast: Bool) {
        self.steps = steps
        self.holdLast = holdLast
    }

    static func tap(_ name: String, modifiers: KeyModifiers = []) -> KeyboardCommand {
        KeyboardCommand(steps: [KeyStep(named: name, modifiers: modifiers)], holdLast: false)
    }

    static func hold(_ name: String, modifiers: KeyModifiers = []) -> KeyboardCommand {
        KeyboardCommand(steps: [KeyStep(named: name, modifiers: modifiers)], holdLast: true)
    }
}
