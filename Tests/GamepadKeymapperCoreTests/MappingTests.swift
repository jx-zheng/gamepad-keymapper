import XCTest
@testable import GamepadKeymapperCore

final class MappingTests: XCTestCase {
    func testDebounceIgnoresBounceUntilStable() {
        var debouncer = ButtonDebouncer(interval: 0.015)
        XCTAssertNil(debouncer.ingest(rawPressed: true, time: 0))
        XCTAssertEqual(debouncer.wakeTime(), 0.015)
        XCTAssertNil(debouncer.ingest(rawPressed: false, time: 0.005))
        XCTAssertNil(debouncer.ingest(rawPressed: true, time: 0.010))
        XCTAssertNil(debouncer.poll(time: 0.024))
        XCTAssertEqual(debouncer.poll(time: 0.025), true)
        XCTAssertNil(debouncer.wakeTime())
    }

    func testZeroDebounceCommitsImmediatelyAndDoesNotRepeat() {
        var debouncer = ButtonDebouncer(interval: 0)
        XCTAssertEqual(debouncer.ingest(rawPressed: true, time: 1), true)
        XCTAssertNil(debouncer.ingest(rawPressed: true, time: 1.1))
        XCTAssertEqual(debouncer.ingest(rawPressed: false, time: 1.2), false)
    }

    func testLayerHoldOverridesAndActivatorIsReserved() {
        let profile = layeredProfile(allowsFallthrough: true)
        var interpreter = MappingInterpreter(debounce: 0)
        let base = interpreter.ingestButton(
            controller: "c1", category: "Xbox", button: .a, rawPressed: true, time: 0, profile: profile
        )
        XCTAssertEqual(base, [.actionBegan(.keyboard(.tap("a")))])
        _ = interpreter.ingestButton(
            controller: "c1", category: "Xbox", button: .a, rawPressed: false, time: 0.05, profile: profile
        )

        let shoulder = interpreter.ingestButton(
            controller: "c1", category: "Xbox", button: .leftShoulder, rawPressed: true, time: 0.1, profile: profile
        )
        XCTAssertEqual(shoulder, [.layersChanged])

        let layered = interpreter.ingestButton(
            controller: "c1", category: "Xbox", button: .a, rawPressed: true, time: 0.2, profile: profile
        )
        XCTAssertEqual(layered, [.actionBegan(.keyboard(.tap("c", modifiers: .command)))])

        let fellThrough = interpreter.ingestButton(
            controller: "c1", category: "Xbox", button: .b, rawPressed: true, time: 0.3, profile: profile
        )
        XCTAssertEqual(fellThrough, [.actionBegan(.keyboard(.tap("b")))])
    }

    func testLayerWithoutFallthroughBlocksBase() {
        let profile = layeredProfile(allowsFallthrough: false)
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(
            controller: "c1", category: nil, button: .leftShoulder, rawPressed: true, time: 0, profile: profile
        )
        let blocked = interpreter.ingestButton(
            controller: "c1", category: nil, button: .b, rawPressed: true, time: 0.1, profile: profile
        )
        XCTAssertEqual(blocked, [])
    }

    func testLaterActiveLayerWins() {
        var profile = layeredProfile(allowsFallthrough: true)
        profile.layers.append(Layer(
            name: "Top",
            activation: .hold(.rightShoulder),
            allowsFallthrough: true,
            bindings: [Binding(button: .a, action: .keyboard(.tap("v", modifiers: .command)))]
        ))
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(
            controller: "c1", category: nil, button: .leftShoulder, rawPressed: true, time: 0, profile: profile
        )
        _ = interpreter.ingestButton(
            controller: "c1", category: nil, button: .rightShoulder, rawPressed: true, time: 0.1, profile: profile
        )
        let resolved = interpreter.ingestButton(
            controller: "c1", category: nil, button: .a, rawPressed: true, time: 0.2, profile: profile
        )
        XCTAssertEqual(resolved, [.actionBegan(.keyboard(.tap("v", modifiers: .command)))])
    }

    func testToggleLayerSticksUntilPressedAgain() {
        let toggle = Layer(
            name: "Sticky",
            activation: .toggle(.rightShoulder),
            bindings: [Binding(button: .a, action: .media(.mute))]
        )
        var profile = layeredProfile(allowsFallthrough: true)
        profile.layers.append(toggle)
        var interpreter = MappingInterpreter(debounce: 0)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c1", category: nil, button: .rightShoulder, rawPressed: true, time: 0, profile: profile),
            [.layersChanged]
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c1", category: nil, button: .a, rawPressed: true, time: 0.1, profile: profile),
            [.actionBegan(.media(.mute))]
        )
        _ = interpreter.ingestButton(controller: "c1", category: nil, button: .a, rawPressed: false, time: 0.15, profile: profile)
        _ = interpreter.ingestButton(controller: "c1", category: nil, button: .rightShoulder, rawPressed: false, time: 0.2, profile: profile)
        _ = interpreter.ingestButton(controller: "c1", category: nil, button: .rightShoulder, rawPressed: true, time: 0.3, profile: profile)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c1", category: nil, button: .a, rawPressed: true, time: 0.4, profile: profile),
            [.actionBegan(.keyboard(.tap("a")))]
        )
    }

    func testCategorySpecificBindingBeatsAny() {
        let profile = Profile(
            name: "Match",
            isDefault: true,
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .a, controllerMatch: .any, action: .keyboard(.tap("x"))),
                Binding(button: .a, controllerMatch: .productCategory("DualSense"), action: .keyboard(.tap("c")))
            ])]
        )
        var interpreter = MappingInterpreter(debounce: 0)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "ds", category: "DualSense", button: .a, rawPressed: true, time: 0, profile: profile),
            [.actionBegan(.keyboard(.tap("c")))]
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "xb", category: "Xbox", button: .a, rawPressed: true, time: 0.1, profile: profile),
            [.actionBegan(.keyboard(.tap("x")))]
        )
    }

    func testControllersKeepIndependentHolds() {
        let profile = Profile(
            name: "Clicks",
            isDefault: true,
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .a, action: .mouseClick(.left, clicks: 1))
            ])]
        )
        var interpreter = MappingInterpreter(debounce: 0)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "one", category: "Joy-Con (L)", button: .a, rawPressed: true, time: 0, profile: profile).count,
            1
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "two", category: "Joy-Con (R)", button: .a, rawPressed: true, time: 0.1, profile: profile).count,
            1
        )
        let releaseOne = interpreter.ingestButton(
            controller: "one", category: "Joy-Con (L)", button: .a, rawPressed: false, time: 0.2, profile: profile
        )
        XCTAssertEqual(releaseOne, [.actionEnded(.mouseClick(.left, clicks: 1))])
        XCTAssertFalse(interpreter.isButtonHeld(controller: "one", button: .a))
        XCTAssertTrue(interpreter.isButtonHeld(controller: "two", button: .a))
        let cleared = interpreter.clearController("two")
        XCTAssertEqual(cleared, [.actionEnded(.mouseClick(.left, clicks: 1))])
        XCTAssertFalse(interpreter.isButtonHeld(controller: "two", button: .a))
    }

    func testLayerOnOneControllerDoesNotAffectTheOther() {
        let profile = layeredProfile(allowsFallthrough: true)
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(
            controller: "one", category: nil, button: .leftShoulder, rawPressed: true, time: 0, profile: profile
        )
        let other = interpreter.ingestButton(
            controller: "two", category: nil, button: .a, rawPressed: true, time: 0.1, profile: profile
        )
        XCTAssertEqual(other, [.actionBegan(.keyboard(.tap("a")))])
        let same = interpreter.ingestButton(
            controller: "one", category: nil, button: .a, rawPressed: true, time: 0.2, profile: profile
        )
        XCTAssertEqual(same, [.actionBegan(.keyboard(.tap("c", modifiers: .command)))])
    }

    func testProfileSwitchReleasesHoldWithoutRefiringUntilNextPress() {
        let desktop = Profile(
            name: "Desktop",
            isDefault: true,
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .a, action: .mouseClick(.left, clicks: 1))
            ])]
        )
        let xcode = Profile(
            name: "Xcode",
            isDefault: false,
            bundleIdentifiers: ["com.apple.dt.Xcode"],
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .a, action: .keyboard(.tap("r", modifiers: .command)))
            ])]
        )
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0, profile: desktop)
        XCTAssertEqual(
            interpreter.endSustainedActions(),
            [.actionEnded(.mouseClick(.left, clicks: 1))]
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0.1, profile: xcode),
            []
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: false, time: 0.2, profile: xcode),
            []
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0.3, profile: xcode),
            [.actionBegan(.keyboard(.tap("r", modifiers: .command)))]
        )
    }

    func testSustainedPressAndRelease() {
        let profile = Profile(
            name: "Arrows",
            isDefault: true,
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .dpadLeft, action: .keyboard(.hold("leftArrow")))
            ])]
        )
        var interpreter = MappingInterpreter(debounce: 0)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .dpadLeft, rawPressed: true, time: 0, profile: profile),
            [.actionBegan(.keyboard(.hold("leftArrow")))]
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .dpadLeft, rawPressed: false, time: 0.2, profile: profile),
            [.actionEnded(.keyboard(.hold("leftArrow")))]
        )
    }

    func testDebouncedPressWaitsForPoll() {
        let profile = Profile.starter(name: "S", isDefault: true)
        var interpreter = MappingInterpreter(debounce: 0.02)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 1, profile: profile),
            []
        )
        XCTAssertEqual(interpreter.nextWakeTime(), 1.02)
        let committed = interpreter.poll(time: 1.02, profile: profile)
        XCTAssertEqual(committed, [.actionBegan(.mouseClick(.left, clicks: 1))])
        XCTAssertNil(interpreter.nextWakeTime())
    }

    func testRepeatedEventsStayBounded() {
        let profile = Profile.starter(name: "S", isDefault: true)
        var interpreter = MappingInterpreter(debounce: 0)
        for index in 0..<2_000 {
            _ = interpreter.ingestButton(
                controller: "c",
                category: "DualSense",
                button: .y,
                rawPressed: true,
                time: Double(index),
                profile: profile
            )
        }
        XCTAssertLessThan(interpreter.debugStateCount, 8)
    }

    func testRadialCommitCancelAndStableAim() {
        let profile = SampleProfiles.desktop()
        var interpreter = MappingInterpreter(debounce: 0, stickDeadzone: 0.28)
        let opened = interpreter.ingestButton(
            controller: "c", category: nil, button: .menu, rawPressed: true, time: 0, profile: profile
        )
        guard case .showRadial(let menu, nil) = opened.first else {
            return XCTFail("Expected the radial menu to open")
        }
        XCTAssertEqual(menu.items.count, 6)

        let aimed = interpreter.ingestButton(
            controller: "c", category: nil, button: .dpadRight, rawPressed: true, time: 0.1, profile: profile
        )
        XCTAssertEqual(aimed, [.updateRadial(2)])
        let same = interpreter.ingestButton(
            controller: "c", category: nil, button: .dpadRight, rawPressed: true, time: 0.15, profile: profile
        )
        XCTAssertEqual(same, [])

        let committed = interpreter.ingestButton(
            controller: "c", category: nil, button: .menu, rawPressed: false, time: 0.2, profile: profile
        )
        XCTAssertEqual(committed.first, .hideRadial)
        XCTAssertEqual(
            committed.dropFirst().first,
            .actionBegan(.launchApp(AppLaunch(bundleIdentifier: "com.apple.systempreferences")))
        )
    }

    func testRadialAimDoesNotLeaveALatchedStickDirection() {
        var profile = Profile.starter(name: "Radial", isDefault: true)
        profile.sticks.left = .digital
        profile.layers[0].bindings.append(
            Binding(button: .leftStickUp, action: .keyboard(.hold("upArrow")))
        )
        profile.radialMenus = [RadialMenu(
            name: "Apps",
            trigger: .menu,
            selection: .leftStick,
            items: [RadialItem(label: "Mute", action: .media(.mute))]
        )]
        var interpreter = MappingInterpreter(debounce: 0, stickDeadzone: 0.5, stickReleaseZone: 0.3)
        let pressed = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 0, y: 1, time: 0, profile: profile
        )
        XCTAssertTrue(pressed.contains(.actionBegan(.keyboard(.hold("upArrow")))))
        let opened = interpreter.ingestButton(
            controller: "c", category: nil, button: .menu, rawPressed: true, time: 0.1, profile: profile
        )
        XCTAssertTrue(opened.contains(.actionEnded(.keyboard(.hold("upArrow")))))
        let aiming = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 0, y: 1, time: 0.2, profile: profile
        )
        XCTAssertFalse(aiming.contains(.actionBegan(.keyboard(.hold("upArrow")))))
        _ = interpreter.ingestButton(
            controller: "c", category: nil, button: .menu, rawPressed: false, time: 0.3, profile: profile
        )
        let after = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 0, y: 1, time: 0.4, profile: profile
        )
        XCTAssertFalse(after.contains(.actionBegan(.keyboard(.hold("upArrow")))))
    }

    func testRadialReleaseEndsHeldAction() {
        let profile = SampleProfiles.desktop()
        var interpreter = MappingInterpreter(debounce: 0)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0, profile: profile),
            [.actionBegan(.mouseClick(.left, clicks: 1))]
        )
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: true, time: 0.1, profile: profile)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: false, time: 0.2, profile: profile),
            [.actionEnded(.mouseClick(.left, clicks: 1))]
        )
    }

    func testRadialCancelAndEmptySelection() {
        let profile = SampleProfiles.desktop()
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: true, time: 0, profile: profile)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .b, rawPressed: true, time: 0.1, profile: profile),
            [.hideRadial]
        )

        _ = interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: false, time: 0.15, profile: profile)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .b, rawPressed: false, time: 0.16, profile: profile)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: true, time: 0.3, profile: profile)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: false, time: 0.4, profile: profile),
            [.hideRadial]
        )
    }

    func testRadialStickDoesNotAlsoMoveThePointer() {
        var profile = Profile.starter(name: "Radial", isDefault: true)
        profile.sticks.left = .mouse(sensitivity: 2_000)
        profile.radialMenus = [RadialMenu(
            name: "Apps",
            trigger: .menu,
            selection: .leftStick,
            items: [
                RadialItem(label: "Mute", action: .media(.mute)),
                RadialItem(label: "Next", action: .media(.nextTrack))
            ]
        )]
        var interpreter = MappingInterpreter(debounce: 0, stickDeadzone: 0.2)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .menu, rawPressed: true, time: 0, profile: profile)
        let first = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 0, y: 1, time: 1, profile: profile
        )
        XCTAssertEqual(first, [.updateRadial(0)])
        let second = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 0, y: 1, time: 1.05, profile: profile
        )
        XCTAssertEqual(second, [])
    }

    func testStickPointerScalesWithTimeAndCapsGaps() {
        var profile = Profile.starter(name: "Mouse", isDefault: true)
        profile.sticks.left = .mouse(sensitivity: 1_000)
        var interpreter = MappingInterpreter(debounce: 0, stickDeadzone: 0)
        let first = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 1, y: 0, time: 1, profile: profile
        )
        XCTAssertFalse(first.contains { if case .pointerDelta = $0 { return true }; return false })
        let moved = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 1, y: 0, time: 1.015625, profile: profile
        )
        let movedDelta = pointerDeltas(moved)
        XCTAssertEqual(movedDelta.count, 1)
        XCTAssertEqual(movedDelta[0].0, 15.625, accuracy: 0.0001)
        XCTAssertEqual(movedDelta[0].1, 0, accuracy: 0.0001)
        let capped = interpreter.ingestStick(
            controller: "c", category: nil, side: .left, x: 1, y: 0, time: 8, profile: profile
        )
        let cappedDelta = pointerDeltas(capped)
        XCTAssertEqual(cappedDelta.count, 1)
        XCTAssertEqual(cappedDelta[0].0, 50, accuracy: 0.0001)
    }

    func testStickSamplesStayBounded() {
        var profile = Profile.starter(name: "Mouse", isDefault: true)
        profile.sticks.left = .mouse(sensitivity: 100)
        var interpreter = MappingInterpreter(debounce: 0, stickDeadzone: 0.2)
        for index in 0..<500 {
            _ = interpreter.ingestStick(
                controller: "c",
                category: nil,
                side: .left,
                x: 0.8,
                y: 0,
                time: Double(index) * 0.008,
                profile: profile
            )
        }
        XCTAssertLessThan(interpreter.debugStateCount, 6)
    }

    func testMouseMoveHoldRequestsAPump() {
        let profile = Profile(
            name: "Nudge",
            isDefault: true,
            layers: [Layer(name: "Base", activation: .base, bindings: [
                Binding(button: .dpadUp, action: .mouseMove(dx: 0, dy: -600))
            ])]
        )
        var interpreter = MappingInterpreter(debounce: 0)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .dpadUp, rawPressed: true, time: 0, profile: profile)
        XCTAssertTrue(interpreter.needsPointerPump)
        _ = interpreter.poll(time: 1, profile: profile)
        let pumped = interpreter.poll(time: 1.015625, profile: profile)
        let deltas = pointerDeltas(pumped)
        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].0, 0, accuracy: 0.0001)
        XCTAssertEqual(deltas[0].1, -9.375, accuracy: 0.0001)
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .dpadUp, rawPressed: false, time: 1.1, profile: profile)
        XCTAssertFalse(interpreter.needsPointerPump)
    }

    func testDigitalStickHysteresis() {
        var digitalizer = StickDigitalizer(deadzone: 0.5, releaseZone: 0.3)
        let pressed = digitalizer.update(x: 0, y: 0.6, side: .left)
        XCTAssertEqual(pressed.pressed, [.leftStickUp])
        let held = digitalizer.update(x: 0, y: 0.4, side: .left)
        XCTAssertTrue(held.pressed.isEmpty && held.released.isEmpty)
        let released = digitalizer.update(x: 0, y: 0.2, side: .left)
        XCTAssertEqual(released.released, [.leftStickUp])
    }

    func testGyroDeadzoneAndScale() {
        XCTAssertNil(GyroPointer.delta(
            rotationX: 0.05, rotationY: 0.05, deadzone: 0.12, sensitivity: 800, invertX: false, invertY: false, dt: 0.016
        ))
        let delta = GyroPointer.delta(
            rotationX: 0, rotationY: 1, deadzone: 0.1, sensitivity: 100, invertX: false, invertY: false, dt: 0.1
        )
        XCTAssertEqual(delta?.dx ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(delta?.dy ?? -1, 0, accuracy: 0.0001)
    }

    func testCaptureConsumesOnePress() {
        let profile = Profile.starter(name: "S", isDefault: true)
        var interpreter = MappingInterpreter(debounce: 0)
        interpreter.captureNextPress = true
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0, profile: profile),
            [.captured(.a)]
        )
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0.1, profile: profile),
            []
        )
        _ = interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: false, time: 0.2, profile: profile)
        XCTAssertEqual(
            interpreter.ingestButton(controller: "c", category: nil, button: .a, rawPressed: true, time: 0.3, profile: profile),
            [.actionBegan(.mouseClick(.left, clicks: 1))]
        )
    }

    private func pointerDeltas(_ effects: [EngineEffect]) -> [(Double, Double)] {
        effects.compactMap { effect in
            if case .pointerDelta(let dx, let dy) = effect { return (dx, dy) }
            return nil
        }
    }

    private func layeredProfile(allowsFallthrough: Bool) -> Profile {
        Profile(
            name: "Layers",
            isDefault: true,
            layers: [
                Layer(name: "Base", activation: .base, bindings: [
                    Binding(button: .a, action: .keyboard(.tap("a"))),
                    Binding(button: .b, action: .keyboard(.tap("b"))),
                    Binding(button: .leftShoulder, action: .keyboard(.tap("x")))
                ]),
                Layer(
                    name: "Edit",
                    activation: .hold(.leftShoulder),
                    allowsFallthrough: allowsFallthrough,
                    bindings: [Binding(button: .a, action: .keyboard(.tap("c", modifiers: .command)))]
                )
            ]
        )
    }
}
