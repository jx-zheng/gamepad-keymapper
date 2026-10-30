import Foundation

struct ProfileStore {
    var root: URL

    var profilesURL: URL { root.appendingPathComponent("profiles.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }

    static func applicationSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("GamepadKeymapper", isDirectory: true)
    }

    func loadDocument() throws -> ProfileDocument {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else {
            return SampleProfiles.document()
        }
        let data = try Data(contentsOf: profilesURL)
        return try ProfileCodec.importDocument(data).document
    }

    func saveDocument(_ document: ProfileDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clean = try ProfileSanitizer.sanitize(document).document
        let data = try ProfileCodec.encode(clean)
        try writeAtomic(data, to: profilesURL)
    }

    func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return .initial
        }
        let data = try Data(contentsOf: settingsURL)
        let settings = try ProfileCodec.decodeSettings(data)
        return ProfileSanitizer.sanitizeSettings(settings)
    }

    func saveSettings(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try ProfileCodec.encodeSettings(ProfileSanitizer.sanitizeSettings(settings))
        try writeAtomic(data, to: settingsURL)
    }

    private func writeAtomic(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
