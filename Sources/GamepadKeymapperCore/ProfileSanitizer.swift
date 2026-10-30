import Foundation

/// Limits and cleanup for profile JSON.
///
/// Imported files are data, not code. Counts and byte size are rejected outright.
/// Strings that would be unsafe to pass to Shortcuts or `NSWorkspace` are cleared
/// so they cannot run. Nothing in a profile is interpreted as a shell command.
enum ProfileSanitizer {
    static let maxBytes = 1_048_576
    static let maxProfiles = 40
    static let maxLayers = 12
    static let maxBindings = 96
    static let maxRadialMenus = 6
    static let maxRadialItems = 8
    static let maxBundleIDs = 32
    static let maxNameLength = 80
    static let maxLabelLength = 40
    static let maxSnippetLength = 500
    static let maxShortcutLength = 120
    static let maxPathLength = 512
    static let maxButtonIDLength = 80
    static let maxCategoryLength = 80

    struct Report: Equatable {
        var document: ProfileDocument
        var warnings: [String]
    }

    static func checkByteCount(_ count: Int) throws {
        if count > maxBytes {
            throw ProfileCodecError.message("Profile file is larger than \(maxBytes) bytes.")
        }
    }

    static func sanitize(_ document: ProfileDocument) throws -> Report {
        var warnings: [String] = []
        if document.profiles.count > maxProfiles {
            throw ProfileCodecError.message("A profile file can contain at most \(maxProfiles) profiles.")
        }
        var profiles: [Profile] = []
        var seenProfileIDs: Set<UUID> = []
        for var profile in document.profiles {
            if seenProfileIDs.contains(profile.id) {
                profile.id = UUID()
                warnings.append("Duplicate profile id was replaced.")
            }
            seenProfileIDs.insert(profile.id)
            profiles.append(try sanitizeProfile(&profile, warnings: &warnings))
        }
        return Report(document: ProfileDocument(profiles: profiles), warnings: warnings)
    }

    static func sanitizeSettings(_ settings: AppSettings) -> AppSettings {
        var copy = settings
        copy.debounceMilliseconds = clamp(copy.debounceMilliseconds, 0, 200)
        copy.stickDeadzone = clamp(copy.stickDeadzone, 0, 0.9)
        copy.stickReleaseZone = clamp(copy.stickReleaseZone, 0, copy.stickDeadzone)
        return copy
    }

    private static func sanitizeProfile(_ profile: inout Profile, warnings: inout [String]) throws -> Profile {
        if profile.layers.count > maxLayers {
            throw ProfileCodecError.message("Profile “\(clip(profile.name))” has too many layers.")
        }
        profile.name = clip(profile.name, max: maxNameLength, fallback: "Profile")
        if profile.bundleIdentifiers.count > maxBundleIDs {
            profile.bundleIdentifiers = Array(profile.bundleIdentifiers.prefix(maxBundleIDs))
            warnings.append("Extra app identifiers on “\(profile.name)” were dropped.")
        }
        profile.bundleIdentifiers = profile.bundleIdentifiers.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isBundleIdentifier(trimmed) else {
                warnings.append("Removed an app identifier that is not a bundle id.")
                return nil
            }
            return trimmed
        }
        profile.sticks.left = sanitizeStick(profile.sticks.left)
        profile.sticks.right = sanitizeStick(profile.sticks.right)
        profile.gyro.sensitivity = clamp(profile.gyro.sensitivity, 0, 5000)
        profile.gyro.deadzone = clamp(profile.gyro.deadzone, 0, 2)
        var seenLayerIDs: Set<UUID> = []
        for index in profile.layers.indices {
            if seenLayerIDs.contains(profile.layers[index].id) {
                profile.layers[index].id = UUID()
                warnings.append("Duplicate layer id was replaced.")
            }
            seenLayerIDs.insert(profile.layers[index].id)
            try sanitizeLayer(&profile.layers[index], warnings: &warnings)
        }
        if profile.radialMenus.count > maxRadialMenus {
            throw ProfileCodecError.message("Profile “\(profile.name)” has too many radial menus.")
        }
        var seenMenuIDs: Set<UUID> = []
        for index in profile.radialMenus.indices {
            if seenMenuIDs.contains(profile.radialMenus[index].id) {
                profile.radialMenus[index].id = UUID()
                warnings.append("Duplicate radial menu id was replaced.")
            }
            seenMenuIDs.insert(profile.radialMenus[index].id)
            try sanitizeMenu(&profile.radialMenus[index], warnings: &warnings)
        }
        return profile
    }

    private static func sanitizeLayer(_ layer: inout Layer, warnings: inout [String]) throws {
        if layer.bindings.count > maxBindings {
            throw ProfileCodecError.message("Layer “\(clip(layer.name))” has too many bindings.")
        }
        layer.name = clip(layer.name, max: maxNameLength, fallback: "Layer")
        switch layer.activation {
        case .base:
            break
        case .hold(let button):
            layer.activation = .hold(sanitizeButton(button))
        case .toggle(let button):
            layer.activation = .toggle(sanitizeButton(button))
        }
        var seen: Set<UUID> = []
        for index in layer.bindings.indices {
            if seen.contains(layer.bindings[index].id) {
                layer.bindings[index].id = UUID()
                warnings.append("Duplicate binding id was replaced.")
            }
            seen.insert(layer.bindings[index].id)
            sanitizeBinding(&layer.bindings[index], warnings: &warnings)
        }
    }

    private static func sanitizeMenu(_ menu: inout RadialMenu, warnings: inout [String]) throws {
        if menu.items.count > maxRadialItems {
            throw ProfileCodecError.message("Radial menu “\(clip(menu.name))” has too many items.")
        }
        menu.name = clip(menu.name, max: maxNameLength, fallback: "Radial Menu")
        menu.trigger = sanitizeButton(menu.trigger)
        var seen: Set<UUID> = []
        for index in menu.items.indices {
            if seen.contains(menu.items[index].id) {
                menu.items[index].id = UUID()
                warnings.append("Duplicate radial item id was replaced.")
            }
            seen.insert(menu.items[index].id)
            menu.items[index].label = clip(menu.items[index].label, max: maxLabelLength, fallback: "Item")
            sanitizeAction(&menu.items[index].action, warnings: &warnings)
        }
    }

    private static func sanitizeBinding(_ binding: inout Binding, warnings: inout [String]) {
        binding.button = sanitizeButton(binding.button)
        switch binding.controllerMatch {
        case .any:
            break
        case .productCategory(let category):
            let clean = clip(category, max: maxCategoryLength, fallback: "")
            if clean.isEmpty || !isSingleLine(clean) {
                binding.controllerMatch = .any
                warnings.append("A controller match was reset because its name was not usable.")
            } else {
                binding.controllerMatch = .productCategory(clean)
            }
        }
        sanitizeAction(&binding.action, warnings: &warnings)
    }

    private static func sanitizeAction(_ action: inout MapperAction, warnings: inout [String]) {
        switch action {
        case .keyboard(var command):
            command.steps = command.steps.prefix(8).map { step in
                var copy = step
                if copy.keyCode > 126 { copy.keyCode = 49 }
                copy.delayMilliseconds = min(2_000, max(0, copy.delayMilliseconds))
                return copy
            }
            action = .keyboard(command)
        case .media:
            break
        case .mouseClick(let button, let clicks):
            action = .mouseClick(button, clicks: min(4, max(1, clicks)))
        case .mouseScroll(let dx, let dy):
            action = .mouseScroll(dx: clamp(dx, -4_000, 4_000), dy: clamp(dy, -4_000, 4_000))
        case .mouseMove(let dx, let dy):
            action = .mouseMove(dx: clamp(dx, -4_000, 4_000), dy: clamp(dy, -4_000, 4_000))
        case .typeText(let text):
            var cleaned = ""
            for scalar in text.prefix(maxSnippetLength).unicodeScalars where scalar.value >= 32 || scalar.value == 9 || scalar.value == 10 {
                cleaned.unicodeScalars.append(scalar)
            }
            action = .typeText(cleaned)
        case .shortcut(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if CommandSafety.shortcutsArguments(name: trimmed) == nil {
                action = .shortcut(name: "")
                if !trimmed.isEmpty {
                    warnings.append("Removed a Shortcut name that cannot be passed as a single argument.")
                }
            } else {
                action = .shortcut(name: trimmed)
            }
        case .launchApp(let launch):
            action = .launchApp(sanitizeLaunch(launch, warnings: &warnings))
        }
    }

    private static func sanitizeLaunch(_ launch: AppLaunch, warnings: inout [String]) -> AppLaunch {
        var copy = launch
        if let bundle = copy.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty {
            if isBundleIdentifier(bundle) {
                copy.bundleIdentifier = bundle
            } else {
                copy.bundleIdentifier = nil
                warnings.append("Removed an app bundle id that contained unexpected characters.")
            }
        } else {
            copy.bundleIdentifier = nil
        }
        if let path = copy.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            if isSafeAppPath(path) {
                copy.path = path
            } else {
                copy.path = nil
                warnings.append("Removed an app path that is not an absolute .app bundle.")
            }
        } else {
            copy.path = nil
        }
        return copy
    }

    private static func sanitizeStick(_ mode: StickMode) -> StickMode {
        switch mode {
        case .digital:
            return .digital
        case .mouse(let sensitivity):
            return .mouse(sensitivity: clamp(sensitivity, 0, 5_000))
        case .scroll(let sensitivity):
            return .scroll(sensitivity: clamp(sensitivity, 0, 5_000))
        }
    }

    private static func sanitizeButton(_ button: ControllerButton) -> ControllerButton {
        let id = String(button.id.prefix(maxButtonIDLength))
        if isSingleLine(id), !id.isEmpty, !id.contains("/"), !id.contains("\\") {
            return ControllerButton(id: id)
        }
        return .a
    }

    static func isBundleIdentifier(_ value: String) -> Bool {
        guard value.count >= 3, value.count <= 220, value.contains(".") else { return false }
        guard isSingleLine(value), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func isSafeAppPath(_ path: String) -> Bool {
        guard path.count <= maxPathLength, path.hasPrefix("/"), isSingleLine(path) else { return false }
        guard !path.contains("//") else { return false }
        let parts = path.split(separator: "/")
        guard !parts.contains(".."), !parts.contains(".") else { return false }
        return path.hasSuffix(".app") || path.contains(".app/")
    }

    private static func isSingleLine(_ text: String) -> Bool {
        !text.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }

    private static func clip(_ text: String, max: Int = maxNameLength, fallback: String = "") -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = ""
        for scalar in trimmed.unicodeScalars where scalar.value >= 32 && scalar.value != 127 {
            value.unicodeScalars.append(scalar)
        }
        if value.isEmpty { return fallback }
        if value.count <= max { return value }
        return String(value.prefix(max))
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite else { return low }
        return min(high, max(low, value))
    }
}

enum CommandSafety {
    /// Arguments for `/usr/bin/shortcuts`. Nil when the name must not be executed.
    /// The name is one argv element. It is never interpolated into a shell command.
    static func shortcutsArguments(name: String) -> [String]? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= ProfileSanitizer.maxShortcutLength else { return nil }
        guard !trimmed.hasPrefix("-") else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        return ["run", trimmed]
    }
}
