import Foundation

/// A logical control on a gamepad.
///
/// Standard ids cover the controls GameController exposes for Joy-Con, Switch Pro,
/// DualSense / DualShock, and Xbox pads. Virtual stick directions (`leftStickUp`, …)
/// are produced by the digital stick mode. Names the system reports that are not in
/// the standard set are stored as `gc:<element name>`.
struct ControllerButton: Hashable, Equatable, Codable {
    var id: String

    init(id: String) {
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        id = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    static let a = ControllerButton(id: "a")
    static let b = ControllerButton(id: "b")
    static let x = ControllerButton(id: "x")
    static let y = ControllerButton(id: "y")
    static let leftShoulder = ControllerButton(id: "leftShoulder")
    static let rightShoulder = ControllerButton(id: "rightShoulder")
    static let leftTrigger = ControllerButton(id: "leftTrigger")
    static let rightTrigger = ControllerButton(id: "rightTrigger")
    static let leftStickClick = ControllerButton(id: "leftStickClick")
    static let rightStickClick = ControllerButton(id: "rightStickClick")
    static let dpadUp = ControllerButton(id: "dpadUp")
    static let dpadDown = ControllerButton(id: "dpadDown")
    static let dpadLeft = ControllerButton(id: "dpadLeft")
    static let dpadRight = ControllerButton(id: "dpadRight")
    static let menu = ControllerButton(id: "menu")
    static let options = ControllerButton(id: "options")
    static let home = ControllerButton(id: "home")
    static let touchpad = ControllerButton(id: "touchpad")

    static let leftStickUp = ControllerButton(id: "leftStickUp")
    static let leftStickDown = ControllerButton(id: "leftStickDown")
    static let leftStickLeft = ControllerButton(id: "leftStickLeft")
    static let leftStickRight = ControllerButton(id: "leftStickRight")
    static let rightStickUp = ControllerButton(id: "rightStickUp")
    static let rightStickDown = ControllerButton(id: "rightStickDown")
    static let rightStickLeft = ControllerButton(id: "rightStickLeft")
    static let rightStickRight = ControllerButton(id: "rightStickRight")

    static func namedGCElement(_ name: String) -> ControllerButton {
        ControllerButton(id: "gc:\(name)")
    }

    /// Shoulder and trigger names GameController uses besides the standard `GCInput…` constants.
    ///
    /// A lone Joy-Con often labels the trigger `ZR` or `ZL` (or an SF Symbol such as `zr.circle`)
    /// instead of `Right Trigger`. Those still have to become `.rightTrigger` / `.leftTrigger`.
    static func standardShoulderOrTrigger(matching name: String) -> ControllerButton? {
        let normalized = name.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        if normalized.contains("zl") || normalized.contains("l2") || normalized.contains("left trigger") || normalized == "lt" {
            return .leftTrigger
        }
        if normalized.contains("zr") || normalized.contains("r2") || normalized.contains("right trigger") || normalized == "rt" {
            return .rightTrigger
        }
        if normalized.contains("left shoulder") || normalized.contains("l1") || normalized == "lb" {
            return .leftShoulder
        }
        if normalized.contains("right shoulder") || normalized.contains("r1") || normalized == "rb" {
            return .rightShoulder
        }
        return nil
    }

    var isAnalogTrigger: Bool {
        id == Self.leftTrigger.id || id == Self.rightTrigger.id
    }

    /// Buttons offered in the editor, in roughly physical order.
    static let catalog: [ControllerButton] = [
        .a, .b, .x, .y,
        .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
        .leftStickClick, .rightStickClick,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
        .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
        .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
        .menu, .options, .home, .touchpad
    ]

    var displayName: String {
        switch id {
        case "a": return "A / Cross"
        case "b": return "B / Circle"
        case "x": return "X / Square"
        case "y": return "Y / Triangle"
        case "leftShoulder": return "L / LB"
        case "rightShoulder": return "R / RB"
        case "leftTrigger": return "ZL / LT"
        case "rightTrigger": return "ZR / RT"
        case "leftStickClick": return "L3"
        case "rightStickClick": return "R3"
        case "dpadUp": return "D-Pad Up"
        case "dpadDown": return "D-Pad Down"
        case "dpadLeft": return "D-Pad Left"
        case "dpadRight": return "D-Pad Right"
        case "menu": return "Menu / +"
        case "options": return "Options / −"
        case "home": return "Home"
        case "touchpad": return "Touchpad"
        case "leftStickUp": return "Left Stick Up"
        case "leftStickDown": return "Left Stick Down"
        case "leftStickLeft": return "Left Stick Left"
        case "leftStickRight": return "Left Stick Right"
        case "rightStickUp": return "Right Stick Up"
        case "rightStickDown": return "Right Stick Down"
        case "rightStickLeft": return "Right Stick Left"
        case "rightStickRight": return "Right Stick Right"
        default:
            if id.hasPrefix("gc:") {
                return String(id.dropFirst(3))
            }
            return id
        }
    }

    var cardinal: CardinalDirection? {
        switch id {
        case "dpadUp": return .up
        case "dpadDown": return .down
        case "dpadLeft": return .left
        case "dpadRight": return .right
        default: return nil
        }
    }
}

enum CardinalDirection: String, Equatable {
    case up, down, left, right
}
