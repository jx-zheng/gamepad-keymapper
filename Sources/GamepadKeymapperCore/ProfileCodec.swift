import Foundation

enum ProfileCodecError: Error, Equatable, CustomStringConvertible {
    case invalidFormat(String?)
    case unsupportedVersion(Int)
    case message(String)

    var description: String {
        switch self {
        case .invalidFormat(let found):
            return "This file is not a Gamepad Keymapper profile (format: \(found ?? "missing"))."
        case .unsupportedVersion(let version):
            return "This profile was written by a newer version (v\(version))."
        case .message(let message):
            return message
        }
    }
}

enum ProfileCodec {
    static func decode(_ data: Data) throws -> ProfileDocument {
        let decoder = JSONDecoder()
        let document: ProfileDocument
        do {
            document = try decoder.decode(ProfileDocument.self, from: data)
        } catch let error as ProfileCodecError {
            throw error
        } catch {
            throw ProfileCodecError.message(error.localizedDescription)
        }
        guard document.format == ProfileDocument.formatIdentifier else {
            throw ProfileCodecError.invalidFormat(document.format)
        }
        guard document.version <= ProfileDocument.currentVersion else {
            throw ProfileCodecError.unsupportedVersion(document.version)
        }
        return document
    }

    /// Decode an imported file, enforce the size cap, and strip anything that must not be executed.
    static func importDocument(_ data: Data) throws -> ProfileSanitizer.Report {
        try ProfileSanitizer.checkByteCount(data.count)
        let decoded = try decode(data)
        return try ProfileSanitizer.sanitize(decoded)
    }

    static func encode(_ document: ProfileDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    static func decodeSettings(_ data: Data) throws -> AppSettings {
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            throw ProfileCodecError.message(error.localizedDescription)
        }
    }

    static func encodeSettings(_ settings: AppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(settings)
    }
}
