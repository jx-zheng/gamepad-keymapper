import Foundation

/// Built-in profiles that ship with the app and with `Samples/desktop-navigation.json`.
enum SampleProfiles {
    static func document() -> ProfileDocument {
        ProfileDocument(profiles: [desktop(), xcode()])
    }

    static func desktop() -> Profile {
        let baseID = UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000002")!
        let editID = UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000003")!
        let menuID = UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000004")!

        let base = Layer(
            id: baseID,
            name: "Base",
            activation: .base,
            bindings: [
                bind("E4A1C0DE-0001-4000-8000-000000000011", .a, .mouseClick(.left, clicks: 1)),
                bind("E4A1C0DE-0001-4000-8000-000000000012", .b, .mouseClick(.right, clicks: 1)),
                bind("E4A1C0DE-0001-4000-8000-000000000013", .x, .keyboard(.tap("space", modifiers: .command))),
                bind("E4A1C0DE-0001-4000-8000-000000000014", .y, .keyboard(.tap("return"))),
                bind("E4A1C0DE-0001-4000-8000-000000000015", .dpadUp, .keyboard(.hold("upArrow"))),
                bind("E4A1C0DE-0001-4000-8000-000000000016", .dpadDown, .keyboard(.hold("downArrow"))),
                bind("E4A1C0DE-0001-4000-8000-000000000017", .dpadLeft, .keyboard(.hold("leftArrow"))),
                bind("E4A1C0DE-0001-4000-8000-000000000018", .dpadRight, .keyboard(.hold("rightArrow"))),
                bind("E4A1C0DE-0001-4000-8000-000000000019", .rightShoulder, .media(.playPause)),
                bind("E4A1C0DE-0001-4000-8000-00000000001A", .leftStickClick, .media(.mute)),
                bind(
                    "E4A1C0DE-0001-4000-8000-00000000001B",
                    .rightStickClick,
                    .keyboard(.tap("upArrow", modifiers: .control))
                ),
                bind(
                    "E4A1C0DE-0001-4000-8000-00000000001C",
                    .options,
                    .typeText("Hello from Gamepad Keymapper")
                )
            ]
        )

        let editing = Layer(
            id: editID,
            name: "Editing",
            activation: .hold(.leftShoulder),
            allowsFallthrough: true,
            bindings: [
                bind("E4A1C0DE-0001-4000-8000-000000000021", .a, .keyboard(.tap("c", modifiers: .command))),
                bind("E4A1C0DE-0001-4000-8000-000000000022", .b, .keyboard(.tap("v", modifiers: .command))),
                bind("E4A1C0DE-0001-4000-8000-000000000023", .x, .keyboard(.tap("x", modifiers: .command))),
                bind("E4A1C0DE-0001-4000-8000-000000000024", .y, .keyboard(.tap("z", modifiers: .command))),
                bind("E4A1C0DE-0001-4000-8000-000000000025", .dpadUp, .keyboard(.tap("pageUp"))),
                bind("E4A1C0DE-0001-4000-8000-000000000026", .dpadDown, .keyboard(.tap("pageDown")))
            ]
        )

        let radial = RadialMenu(
            id: menuID,
            name: "Quick Actions",
            trigger: .menu,
            selection: .dpad,
            items: [
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000031")!,
                    label: "TextEdit",
                    action: .launchApp(AppLaunch(bundleIdentifier: "com.apple.TextEdit"))
                ),
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000032")!,
                    label: "Safari",
                    action: .launchApp(AppLaunch(bundleIdentifier: "com.apple.Safari"))
                ),
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000033")!,
                    label: "Settings",
                    action: .launchApp(AppLaunch(bundleIdentifier: "com.apple.systempreferences"))
                ),
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000034")!,
                    label: "Play/Pause",
                    action: .media(.playPause)
                ),
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000035")!,
                    label: "Spotlight",
                    action: .keyboard(.tap("space", modifiers: .command))
                ),
                RadialItem(
                    id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000036")!,
                    label: "Snippet",
                    action: .typeText("— ")
                )
            ]
        )

        return Profile(
            id: UUID(uuidString: "E4A1C0DE-0001-4000-8000-000000000001")!,
            name: "Desktop",
            isDefault: true,
            bundleIdentifiers: [],
            layers: [base, editing],
            radialMenus: [radial],
            sticks: StickConfig(left: .mouse(sensitivity: 1080), right: .scroll(sensitivity: 360)),
            gyro: GyroSettings(
                enabled: false,
                sensitivity: 800,
                deadzone: 0.12,
                invertX: false,
                invertY: false,
                activation: .whileHeld(.leftTrigger)
            )
        )
    }

    static func xcode() -> Profile {
        let base = Layer(
            id: UUID(uuidString: "E4A1C0DE-0002-4000-8000-000000000002")!,
            name: "Base",
            activation: .base,
            bindings: [
                bind("E4A1C0DE-0002-4000-8000-000000000011", .a, .keyboard(.tap("r", modifiers: .command))),
                bind("E4A1C0DE-0002-4000-8000-000000000012", .b, .keyboard(.tap("period", modifiers: .command))),
                bind("E4A1C0DE-0002-4000-8000-000000000013", .x, .keyboard(.tap("b", modifiers: .command))),
                bind("E4A1C0DE-0002-4000-8000-000000000014", .y, .keyboard(.tap("slash", modifiers: .command))),
                bind("E4A1C0DE-0002-4000-8000-000000000015", .dpadUp, .keyboard(.hold("upArrow"))),
                bind("E4A1C0DE-0002-4000-8000-000000000016", .dpadDown, .keyboard(.hold("downArrow"))),
                bind("E4A1C0DE-0002-4000-8000-000000000017", .dpadLeft, .keyboard(.hold("leftArrow"))),
                bind("E4A1C0DE-0002-4000-8000-000000000018", .dpadRight, .keyboard(.hold("rightArrow")))
            ]
        )
        let debug = Layer(
            id: UUID(uuidString: "E4A1C0DE-0002-4000-8000-000000000003")!,
            name: "Debug",
            activation: .hold(.leftShoulder),
            allowsFallthrough: true,
            bindings: [
                bind("E4A1C0DE-0002-4000-8000-000000000021", .a, .keyboard(.tap("f6"))),
                bind("E4A1C0DE-0002-4000-8000-000000000022", .b, .keyboard(.tap("f7"))),
                bind("E4A1C0DE-0002-4000-8000-000000000023", .x, .keyboard(.tap("period", modifiers: .command))),
                bind(
                    "E4A1C0DE-0002-4000-8000-000000000024",
                    .y,
                    .keyboard(.tap("o", modifiers: [.command, .shift]))
                )
            ]
        )
        return Profile(
            id: UUID(uuidString: "E4A1C0DE-0002-4000-8000-000000000001")!,
            name: "Xcode",
            isDefault: false,
            bundleIdentifiers: ["com.apple.dt.Xcode"],
            layers: [base, debug],
            sticks: StickConfig(left: .digital, right: .scroll(sensitivity: 240)),
            gyro: .off
        )
    }

    private static func bind(_ id: String, _ button: ControllerButton, _ action: MapperAction) -> Binding {
        Binding(
            id: UUID(uuidString: id)!,
            button: button,
            action: action
        )
    }
}
