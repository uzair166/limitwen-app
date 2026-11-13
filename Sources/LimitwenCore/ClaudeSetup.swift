import Foundation

/// Installs a reversible status-line bridge while preserving unrelated Claude settings.
public struct ClaudeSetup: Sendable {
    public let settingsURL: URL
    public let supportURL: URL
    public init(settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), supportURL: URL = LocalStorage.directory) {
        self.settingsURL = settingsURL; self.supportURL = supportURL
    }
    public var relayURL: URL { supportURL.appendingPathComponent("LimitwenRelay") }
    public var previousURL: URL { supportURL.appendingPathComponent("claude-statusline-backup.json") }
    public var command: String { Self.quote(relayURL.path) + " --previous " + Self.quote(previousURL.path) }
    public var isInstalled: Bool { (try? settings()["statusLine"] as? [String: Any])?["command"] as? String == command }
    public func install(relayBinary: URL) throws {
        var settings = try settings()
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let binary = try Data(contentsOf: relayBinary)
        try LocalStorage.writeData(binary, to: relayURL, mode: 0o700)
        guard !isInstalled else { return }
        let backup: [String: Any] = ["original": settings["statusLine"] ?? NSNull()]
        try writeJSON(backup, to: previousURL)
        settings["statusLine"] = ["type": "command", "command": command, "padding": (settings["statusLine"] as? [String: Any])?["padding"] ?? 0]
        try writeJSON(settings, to: settingsURL)
    }
    @discardableResult public func uninstall() throws -> Bool {
        var settings = try settings()
        guard (settings["statusLine"] as? [String: Any])?["command"] as? String == command else { return false } // A later user edit always wins.
        guard let backup = try JSONSerialization.jsonObject(with: LocalStorage.readData(from: previousURL)) as? [String: Any],
              let original = backup["original"], original is NSNull || original is [String: Any] else { throw ProviderFailure.invalidResponse }
        if !(original is NSNull) { settings["statusLine"] = original }
        else { settings.removeValue(forKey: "statusLine") }
        try writeJSON(settings, to: settingsURL)
        return true
    }
    private func settings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: LocalStorage.readData(from: settingsURL, allowSymbolicLink: true)) as? [String: Any] else { throw ProviderFailure.invalidResponse }
        return object
    }
    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try LocalStorage.writeData(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: url)
    }
    private static func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}
