import XCTest
@testable import GamepadKeymapperCore

final class ProfileTests: XCTestCase {
    func testSampleRoundTripsAndSanitizesCleanly() throws {
        let original = SampleProfiles.document()
        let data = try ProfileCodec.encode(original)
        XCTAssertEqual(try ProfileCodec.decode(data), original)
        let imported = try ProfileCodec.importDocument(data)
        XCTAssertEqual(imported.document, original)
        XCTAssertTrue(imported.warnings.isEmpty)
    }

    func testCheckedInSampleMatchesFactory() throws {
        let url = repoRoot().appendingPathComponent("Samples/desktop-navigation.json")
        if ProcessInfo.processInfo.environment["DUMP_SAMPLE"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try ProfileCodec.encode(SampleProfiles.document()).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(decoded, SampleProfiles.document())
    }

    func testProfileSelection() {
        let profiles = SampleProfiles.document().profiles
        XCTAssertEqual(
            ProfileSelector.select(from: profiles, frontmostBundleID: "com.apple.dt.Xcode", overrideID: nil)?.name,
            "Xcode"
        )
        XCTAssertEqual(
            ProfileSelector.select(from: profiles, frontmostBundleID: "COM.APPLE.DT.XCODE", overrideID: nil)?.name,
            "Xcode"
        )
        XCTAssertEqual(
            ProfileSelector.select(from: profiles, frontmostBundleID: "com.apple.Safari", overrideID: nil)?.name,
            "Desktop"
        )
        let xcodeID = profiles[1].id
        XCTAssertEqual(
            ProfileSelector.select(from: profiles, frontmostBundleID: "com.apple.Safari", overrideID: xcodeID)?.name,
            "Xcode"
        )
        var disabled = profiles
        disabled[1].enabled = false
        XCTAssertEqual(
            ProfileSelector.select(from: disabled, frontmostBundleID: "com.apple.dt.Xcode", overrideID: nil)?.name,
            "Desktop"
        )
        disabled[0].enabled = false
        XCTAssertNil(ProfileSelector.select(from: disabled, frontmostBundleID: nil, overrideID: xcodeID))
    }

    func testStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try store.loadDocument(), SampleProfiles.document())
        try store.saveDocument(SampleProfiles.document())
        XCTAssertEqual(try store.loadDocument(), SampleProfiles.document())
        var settings = AppSettings.initial
        settings.debounceMilliseconds = 400
        settings.stickReleaseZone = 0.8
        settings.stickDeadzone = 0.3
        try store.saveSettings(settings)
        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.debounceMilliseconds, 200)
        XCTAssertEqual(loaded.stickReleaseZone, 0.3)
    }

    func testRejectsWrongFormatVersionAndShellAction() throws {
        XCTAssertThrowsError(try ProfileCodec.decode(Data(#"{"format":"nope","version":1,"profiles":[]}"#.utf8)))
        XCTAssertThrowsError(try ProfileCodec.decode(Data(#"{"format":"gamepad-keymapper.profiles","version":99,"profiles":[]}"#.utf8)))

        let data = try ProfileCodec.encode(ProfileDocument(profiles: [Profile.starter(name: "S", isDefault: true)]))
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var profiles = root["profiles"] as! [[String: Any]]
        var layers = profiles[0]["layers"] as! [[String: Any]]
        var bindings = layers[0]["bindings"] as! [[String: Any]]
        var action = bindings[0]["action"] as! [String: Any]
        action["type"] = "shell"
        action["command"] = "rm -rf /"
        bindings[0]["action"] = action
        layers[0]["bindings"] = bindings
        profiles[0]["layers"] = layers
        root["profiles"] = profiles
        let mutated = try JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try ProfileCodec.decode(mutated))
    }

    func testUnknownKeysAreNotExecuted() throws {
        let data = try ProfileCodec.encode(ProfileDocument(profiles: [Profile.starter(name: "S", isDefault: true)]))
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var profiles = root["profiles"] as! [[String: Any]]
        var layers = profiles[0]["layers"] as! [[String: Any]]
        var bindings = layers[0]["bindings"] as! [[String: Any]]
        var action = bindings[0]["action"] as! [String: Any]
        action["shell"] = "rm -rf /"
        bindings[0]["action"] = action
        layers[0]["bindings"] = bindings
        profiles[0]["layers"] = layers
        root["profiles"] = profiles
        let mutated = try JSONSerialization.data(withJSONObject: root)
        let decoded = try ProfileCodec.decode(mutated)
        let encoded = try ProfileCodec.encode(decoded)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("rm -rf"))
        XCTAssertFalse(text.contains("shell"))
    }

    func testUnsafeShortcutAndPathAreCleared() throws {
        var profile = Profile.starter(name: "Unsafe", isDefault: true)
        profile.layers[0].bindings[0].action = .shortcut(name: "Hello\nrm -rf /")
        profile.layers[0].bindings[1].action = .launchApp(AppLaunch(path: "TextEdit.app"))
        profile.bundleIdentifiers = ["../evil", "com.apple.TextEdit"]
        let report = try ProfileSanitizer.sanitize(ProfileDocument(profiles: [profile]))
        let bindings = report.document.profiles[0].layers[0].bindings
        XCTAssertEqual(bindings[0].action, .shortcut(name: ""))
        if case .launchApp(let launch) = bindings[1].action {
            XCTAssertNil(launch.path)
        } else {
            XCTFail("Expected a launch action")
        }
        XCTAssertEqual(report.document.profiles[0].bundleIdentifiers, ["com.apple.TextEdit"])
        XCTAssertFalse(report.warnings.isEmpty)
        XCTAssertNil(CommandSafety.shortcutsArguments(name: "Hello\nrm -rf /"))
        XCTAssertNil(CommandSafety.shortcutsArguments(name: "-help"))
        XCTAssertEqual(CommandSafety.shortcutsArguments(name: "New Note"), ["run", "New Note"])
    }

    func testSafeAbsoluteAppPathIsKept() throws {
        var profile = Profile.starter(name: "Path", isDefault: true)
        profile.layers[0].bindings[0].action = .launchApp(AppLaunch(path: "/Applications/TextEdit.app"))
        let report = try ProfileSanitizer.sanitize(ProfileDocument(profiles: [profile]))
        if case .launchApp(let launch) = report.document.profiles[0].layers[0].bindings[0].action {
            XCTAssertEqual(launch.path, "/Applications/TextEdit.app")
        } else {
            XCTFail("Expected a launch action")
        }
        XCTAssertFalse(ProfileSanitizer.isSafeAppPath("/tmp/../Applications/Foo.app"))
        XCTAssertFalse(ProfileSanitizer.isBundleIdentifier("not a bundle"))
    }

    func testSnippetWarningsAndSingleDefault() throws {
        var profile = Profile.starter(name: "Text", isDefault: true)
        profile.layers[0].bindings[0].action = .typeText("hello\n")
        profile.layers[0].bindings[1].action = .typeText("echo $(whoami)\nmore")
        var other = Profile.starter(name: "Also", isDefault: true)
        let report = try ProfileSanitizer.sanitize(ProfileDocument(profiles: [profile, other]))
        if case .typeText(let text) = report.document.profiles[0].layers[0].bindings[0].action {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("Expected typed text")
        }
        XCTAssertTrue(report.warnings.contains { $0.contains("line break") })
        XCTAssertTrue(report.warnings.contains { $0.contains("shell") })
        XCTAssertEqual(report.document.profiles.filter(\.isDefault).count, 1)
    }

    func testHardCaps() throws {
        XCTAssertThrowsError(try ProfileSanitizer.checkByteCount(ProfileSanitizer.maxBytes + 1))
        let profiles = (0..<41).map { Profile.starter(name: "P\($0)", isDefault: $0 == 0) }
        XCTAssertThrowsError(try ProfileSanitizer.sanitize(ProfileDocument(profiles: profiles)))
    }

    func testRadialGeometryCardinals() {
        XCTAssertEqual(RadialGeometry.sliceIndex(dx: 0, dy: 1, count: 4, deadzone: 0.2), 0)
        XCTAssertEqual(RadialGeometry.sliceIndex(dx: 1, dy: 0, count: 4, deadzone: 0.2), 1)
        XCTAssertEqual(RadialGeometry.sliceIndex(dx: 0, dy: -1, count: 4, deadzone: 0.2), 2)
        XCTAssertEqual(RadialGeometry.sliceIndex(dx: -1, dy: 0, count: 4, deadzone: 0.2), 3)
        XCTAssertNil(RadialGeometry.sliceIndex(dx: 0.1, dy: 0, count: 4, deadzone: 0.2))
        XCTAssertEqual(RadialGeometry.index(for: .up, count: 8), 0)
        XCTAssertEqual(RadialGeometry.index(for: .right, count: 8), 2)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
