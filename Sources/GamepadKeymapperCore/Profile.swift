import Foundation

enum StickSide: String, Equatable, Codable {
    case left
    case right

    func buttonID(_ direction: CardinalDirection) -> String {
        let prefix = self == .left ? "leftStick" : "rightStick"
        switch direction {
        case .up: return prefix + "Up"
        case .down: return prefix + "Down"
        case .left: return prefix + "Left"
        case .right: return prefix + "Right"
        }
    }
}

enum StickMode: Equatable, Hashable {
    case digital
    /// Pointer pixels per second at full deflection, after deadzone shaping.
    case mouse(sensitivity: Double)
    /// Scroll pixels per second at full deflection.
    case scroll(sensitivity: Double)
}

extension StickMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sensitivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "digital":
            self = .digital
        case "mouse":
            self = .mouse(sensitivity: try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 16)
        case "scroll":
            self = .scroll(sensitivity: try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 6)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown stick mode"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .digital:
            try container.encode("digital", forKey: .type)
        case .mouse(let sensitivity):
            try container.encode("mouse", forKey: .type)
            try container.encode(sensitivity, forKey: .sensitivity)
        case .scroll(let sensitivity):
            try container.encode("scroll", forKey: .type)
            try container.encode(sensitivity, forKey: .sensitivity)
        }
    }
}

struct StickConfig: Equatable, Hashable, Codable {
    var left: StickMode
    var right: StickMode

    static let digital = StickConfig(left: .digital, right: .digital)
}

enum GyroActivation: Equatable, Hashable {
    case always
    case whileHeld(ControllerButton)
}

extension GyroActivation: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case button
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "always":
            self = .always
        case "whileHeld":
            self = .whileHeld(try container.decode(ControllerButton.self, forKey: .button))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown gyro activation"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:
            try container.encode("always", forKey: .type)
        case .whileHeld(let button):
            try container.encode("whileHeld", forKey: .type)
            try container.encode(button, forKey: .button)
        }
    }

    func isActive(held: Set<String>) -> Bool {
        switch self {
        case .always:
            return true
        case .whileHeld(let button):
            return held.contains(button.id)
        }
    }
}

struct GyroSettings: Equatable, Hashable, Codable {
    /// Pixels per second at 1 radian/second of rotation, before invert.
    var enabled: Bool
    var sensitivity: Double
    var deadzone: Double
    var invertX: Bool
    var invertY: Bool
    var activation: GyroActivation

    static let off = GyroSettings(
        enabled: false,
        sensitivity: 800,
        deadzone: 0.12,
        invertX: false,
        invertY: false,
        activation: .whileHeld(.leftTrigger)
    )
}

enum LayerActivation: Equatable, Hashable {
    case base
    case hold(ControllerButton)
    case toggle(ControllerButton)

    var activator: ControllerButton? {
        switch self {
        case .base:
            return nil
        case .hold(let button), .toggle(let button):
            return button
        }
    }
}

extension LayerActivation: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case button
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "base":
            self = .base
        case "hold":
            self = .hold(try container.decode(ControllerButton.self, forKey: .button))
        case "toggle":
            self = .toggle(try container.decode(ControllerButton.self, forKey: .button))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown layer activation"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .base:
            try container.encode("base", forKey: .type)
        case .hold(let button):
            try container.encode("hold", forKey: .type)
            try container.encode(button, forKey: .button)
        case .toggle(let button):
            try container.encode("toggle", forKey: .type)
            try container.encode(button, forKey: .button)
        }
    }
}

struct ButtonBinding: Equatable, Hashable, Identifiable, Codable {
    var id: UUID
    var button: ControllerButton
    var action: MapperAction

    init(id: UUID = UUID(), button: ControllerButton, action: MapperAction) {
        self.id = id
        self.button = button
        self.action = action
    }
}

struct Layer: Equatable, Hashable, Identifiable, Codable {
    var id: UUID
    var name: String
    var activation: LayerActivation
    /// When false, a button with no binding on this layer does nothing instead of using a lower layer.
    var allowsFallthrough: Bool
    var bindings: [ButtonBinding]

    init(
        id: UUID = UUID(),
        name: String,
        activation: LayerActivation,
        allowsFallthrough: Bool = true,
        bindings: [ButtonBinding] = []
    ) {
        self.id = id
        self.name = name
        self.activation = activation
        self.allowsFallthrough = allowsFallthrough
        self.bindings = bindings
    }
}

enum RadialSelectionSource: String, Equatable, Hashable, Codable, CaseIterable {
    case leftStick
    case rightStick
    case dpad

    var displayName: String {
        switch self {
        case .leftStick: return "Left Stick"
        case .rightStick: return "Right Stick"
        case .dpad: return "D-Pad"
        }
    }

    func matches(side: StickSide) -> Bool {
        switch (self, side) {
        case (.leftStick, .left), (.rightStick, .right):
            return true
        default:
            return false
        }
    }
}

struct RadialItem: Equatable, Hashable, Identifiable, Codable {
    var id: UUID
    var label: String
    var action: MapperAction

    init(id: UUID = UUID(), label: String, action: MapperAction) {
        self.id = id
        self.label = label
        self.action = action
    }
}

struct RadialMenu: Equatable, Hashable, Identifiable, Codable {
    var id: UUID
    var name: String
    var trigger: ControllerButton
    var selection: RadialSelectionSource
    var items: [RadialItem]

    init(
        id: UUID = UUID(),
        name: String,
        trigger: ControllerButton,
        selection: RadialSelectionSource = .dpad,
        items: [RadialItem] = []
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.selection = selection
        self.items = items
    }
}

struct Profile: Equatable, Hashable, Identifiable, Codable {
    var id: UUID
    var name: String
    var isDefault: Bool
    var enabled: Bool
    /// Bundle ids that auto-select this profile when that app is frontmost. Empty means manual / fallback only.
    var bundleIdentifiers: [String]
    var layers: [Layer]
    var radialMenus: [RadialMenu]
    var sticks: StickConfig
    var gyro: GyroSettings

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool,
        enabled: Bool = true,
        bundleIdentifiers: [String] = [],
        layers: [Layer],
        radialMenus: [RadialMenu] = [],
        sticks: StickConfig = .digital,
        gyro: GyroSettings = .off
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.enabled = enabled
        self.bundleIdentifiers = bundleIdentifiers
        self.layers = layers
        self.radialMenus = radialMenus
        self.sticks = sticks
        self.gyro = gyro
    }

    var layerActivatorIDs: Set<String> {
        Set(layers.compactMap { $0.activation.activator?.id })
    }

    func validationWarnings() -> [String] {
        var warnings: [String] = []
        let bases = layers.filter {
            if case .base = $0.activation { return true }
            return false
        }
        if bases.isEmpty {
            warnings.append("Add a base layer so buttons work without a modifier.")
        } else if bases.count > 1 {
            warnings.append("More than one layer is marked as the base.")
        }
        var seenActivators: [String: String] = [:]
        for layer in layers {
            guard let activator = layer.activation.activator else { continue }
            if let previous = seenActivators[activator.id] {
                warnings.append("\(activator.displayName) activates both “\(previous)” and “\(layer.name)”.")
            } else {
                seenActivators[activator.id] = layer.name
            }
        }
        for menu in radialMenus {
            if menu.items.isEmpty {
                warnings.append("Radial menu “\(menu.name)” has no items.")
            }
            if layerActivatorIDs.contains(menu.trigger.id) {
                warnings.append("\(menu.trigger.displayName) is both a layer modifier and the “\(menu.name)” radial trigger. The radial menu wins.")
            }
        }
        return warnings
    }

    /// Empty profile for Add Profile: Base only, no bindings and no radial menu.
    static func blank(name: String, isDefault: Bool) -> Profile {
        Profile(
            name: name,
            isDefault: isDefault,
            layers: [Layer(name: "Base", activation: .base)],
            radialMenus: [],
            sticks: .digital,
            gyro: .off
        )
    }

    /// A usable starter profile: clicks on the face buttons and arrow keys on the D-pad.
    static func starter(name: String, isDefault: Bool) -> Profile {
        let base = Layer(
            name: "Base",
            activation: .base,
            bindings: [
                ButtonBinding(button: .a, action: .mouseClick(.left, clicks: 1)),
                ButtonBinding(button: .b, action: .mouseClick(.right, clicks: 1)),
                ButtonBinding(button: .dpadUp, action: .keyboard(.hold("upArrow"))),
                ButtonBinding(button: .dpadDown, action: .keyboard(.hold("downArrow"))),
                ButtonBinding(button: .dpadLeft, action: .keyboard(.hold("leftArrow"))),
                ButtonBinding(button: .dpadRight, action: .keyboard(.hold("rightArrow")))
            ]
        )
        return Profile(
            name: name,
            isDefault: isDefault,
            layers: [base],
            sticks: StickConfig(left: .mouse(sensitivity: 960), right: .scroll(sensitivity: 360)),
            gyro: .off
        )
    }
}

struct ProfileDocument: Equatable, Hashable, Codable {
    static let formatIdentifier = "gamepad-keymapper.profiles"
    static let currentVersion = 1

    var format: String
    var version: Int
    var profiles: [Profile]

    init(profiles: [Profile]) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.profiles = profiles
    }

    /// Folds imported profiles into this document.
    ///
    /// A profile whose id is already present replaces that profile, or is skipped when the
    /// contents already match. New ids are appended. This does not mint a second copy.
    func merging(_ incoming: ProfileDocument) -> ProfileDocument {
        var profiles = self.profiles
        for profile in incoming.profiles {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                if profiles[index] != profile {
                    profiles[index] = profile
                }
            } else {
                profiles.append(profile)
            }
        }
        return ProfileDocument(profiles: profiles)
    }
}

struct AppSettings: Equatable, Codable {
    var mappingEnabled: Bool
    var debounceMilliseconds: Double
    var stickDeadzone: Double
    var stickReleaseZone: Double
    var profileOverrideID: UUID?
    var didFinishOnboarding: Bool
    var launchAtLogin: Bool
    var verboseLogging: Bool

    static let initial = AppSettings(
        mappingEnabled: true,
        debounceMilliseconds: 15,
        stickDeadzone: 0.28,
        stickReleaseZone: 0.20,
        profileOverrideID: nil,
        didFinishOnboarding: false,
        launchAtLogin: false,
        verboseLogging: false
    )
}
