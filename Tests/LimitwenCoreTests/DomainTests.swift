import Foundation
import Testing
@testable import LimitwenCore

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
private func quota(used: Double? = 82, reset: Date? = epoch.addingTimeInterval(3600)) -> QuotaWindow {
    QuotaWindow(id: "five-hour", title: "5-hour window", durationMinutes: 300, usedPercent: used, resetsAt: reset)
}

@Test(arguments: [(0.0, 100.0), (100, 0), (82, 18), (-10, 100), (120, 0)])
func remainingIsBounded(values: (Double, Double)) { #expect(quota(used: values.0).remainingPercent == values.1) }

@Test func absenceIsNotExhaustion() {
    #expect(quota(used: nil).remainingPercent == nil)
    #expect(quota(used: .nan).remainingPercent == nil)
    #expect(quota(used: .infinity).remainingPercent == nil)
    #expect(quota(used: 100).remainingPercent == 0)
}

@Test func codexMapsDurationInsteadOfPosition() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":98,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1800003600},"secondary":null}}}"#.utf8)
    let snapshot = try UsageParser.codex(data, observedAt: epoch)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].id == "weekly")
    #expect(snapshot.windows[0].remainingPercent == 98)
    #expect(snapshot.displayWindows.map(\.id) == ["weekly"])
    #expect(snapshot.displayWindows[0].remainingPercent == 98)
}

@Test func codexLegacyAndUnusualWindows() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":15,"resetsAt":1800003600},"secondary":{"usedPercent":null,"windowDurationMins":10080,"resetsAt":null}}}"#.utf8)
    let snapshot = try UsageParser.codex(data, observedAt: epoch)
    #expect(snapshot.windows[0].title == "15-minute window")
    #expect(snapshot.windows[0].remainingPercent == 75)
    #expect(snapshot.windows[1].remainingPercent == nil)
    #expect(snapshot.windows[1].resetsAt == nil)
}

@Test(arguments: ["garbage", "{}", #"{"rateLimits":{"primary":{"usedPercent":"80"}}}"#])
func invalidCodexDoesNotInventData(input: String) {
    #expect(throws: (any Error).self) { try UsageParser.codex(Data(input.utf8), observedAt: epoch) }
}

@Test func claudeOnlyStoresQuotaData() throws {
    let input = Data(#"{"session_id":"private","workspace":{"current_dir":"private"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41.2,"resets_at":1800604800}}}"#.utf8)
    let snapshot = try UsageParser.claude(input, observedAt: epoch)
    #expect(snapshot.windows.map(\.remainingPercent) == [76.5, 58.8])
    let persisted = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!persisted.contains("private"))
    #expect(!persisted.contains("session_id"))
    #expect(snapshot.observedAt == epoch)
}

@Test func claudeOnlyDisplaysReportedWindows() throws {
    let snapshot = try UsageParser.claude(Data(#"{"rate_limits":{"seven_day":{"used_percentage":100}}}"#.utf8), observedAt: epoch)
    #expect(snapshot.displayWindows.map(\.id) == ["weekly"])
    #expect(snapshot.displayWindows[0].remainingPercent == 0)
}

@Test(arguments: ["{}", #"{"rate_limits":null}"#, #"{"rate_limits":{}}"#])
func claudeWithoutQuotasIsNotANewUsageObservation(input: String) {
    #expect(throws: ProviderFailure.noObservation) { try UsageParser.claude(Data(input.utf8), observedAt: epoch) }
}

@Test func freshnessAndClockSkew() {
    let snapshot = UsageSnapshot(provider: .codex, windows: [quota()], observedAt: epoch, source: "fixture")
    #expect(!snapshot.isStale(at: epoch.addingTimeInterval(900)))
    #expect(snapshot.isStale(at: epoch.addingTimeInterval(901)))
    #expect(snapshot.isStale(at: epoch.addingTimeInterval(-61)))
}

@Test func alertsAreDeduplicatedPerWindowAndCycle() {
    var ledger = AlertLedger()
    let window = quota()
    let snapshot = UsageSnapshot(provider: .claude, windows: [window], observedAt: epoch, source: "fixture")
    #expect(ledger.candidates(snapshot: snapshot, threshold: 20, now: epoch).count == 1)
    ledger.record(provider: .claude, window: window, now: epoch)
    #expect(ledger.candidates(snapshot: snapshot, threshold: 30, now: epoch).isEmpty)
    let newCycle = UsageSnapshot(provider: .claude, windows: [quota(reset: epoch.addingTimeInterval(7200))], observedAt: epoch, source: "fixture")
    #expect(ledger.candidates(snapshot: newCycle, threshold: 20, now: epoch).count == 1)
    let otherProvider = UsageSnapshot(provider: .codex, windows: [window], observedAt: epoch, source: "fixture")
    #expect(ledger.candidates(snapshot: otherProvider, threshold: 20, now: epoch).count == 1)
}

@Test func alertsRequireFreshMeasurementsAndFutureKnownReset() {
    let ledger = AlertLedger()
    for window in [quota(used: nil), quota(reset: nil), quota(reset: epoch), quota(used: 20)] {
        let snapshot = UsageSnapshot(provider: .codex, windows: [window], observedAt: epoch, source: "fixture")
        #expect(ledger.candidates(snapshot: snapshot, threshold: 20, now: epoch).isEmpty)
    }
    let stale = UsageSnapshot(provider: .codex, windows: [quota()], observedAt: epoch.addingTimeInterval(-901), source: "fixture")
    #expect(ledger.candidates(snapshot: stale, threshold: 20, now: epoch).isEmpty)
}

@Test func resetPassingDoesNotRefillValue() {
    let window = quota(reset: epoch)
    #expect(window.hasElapsed(at: epoch))
    #expect(window.remainingPercent == 18)
    #expect(ResetDescription.relative(epoch, now: epoch) == "Reset due · awaiting update")
    #expect(ResetDescription.relative(nil, now: epoch) == "Reset time unavailable")
    #expect(ResetDescription.relative(epoch.addingTimeInterval(1), now: epoch) == "Resets in 1m")
    #expect(ResetDescription.relative(epoch.addingTimeInterval(8040), now: epoch) == "Resets in 2h 14m")
    #expect(ResetDescription.relative(epoch.addingTimeInterval(3600), now: epoch) == "Resets in 1h")
    #expect(ResetDescription.relative(epoch.addingTimeInterval(172800), now: epoch) == "Resets in 2d")
}

@Test func preferencesNormalizeAndRoundTrip() throws {
    var p = Preferences()
    p.enabled = [.codex, .codex]; p.pinned = [.claude, .codex, .codex]
    p.resetReminders = ["claude:weekly": epoch, "codex:weekly": epoch]; p.threshold = 999
    p.normalize()
    #expect(p.enabled == [.codex]); #expect(p.visiblePins == [.codex])
    #expect(p.resetReminders == ["codex:weekly": epoch]); #expect(p.threshold == 95)
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)) == p)
    p.pinned = []; p.normalize(); #expect(p.visiblePins.isEmpty)
}

@Test func privateSnapshotRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("snapshot.json")
    let original = UsageSnapshot(provider: .claude, windows: [quota()], observedAt: epoch, source: "fixture")
    try LocalStorage.write(original, to: url)
    #expect(try LocalStorage.read(UsageSnapshot.self, from: url) == original)
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
}

@Test func claudeSetupPreservesAndRestoresExistingConfiguration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settingsURL = directory.appendingPathComponent("settings.json")
    let original: [String: Any] = ["theme": "dark", "statusLine": ["type": "command", "command": "printf original", "padding": 2]]
    try JSONSerialization.data(withJSONObject: original).write(to: settingsURL)
    let binary = directory.appendingPathComponent("relay-source")
    try Data("fixture".utf8).write(to: binary)
    let setup = ClaudeSetup(settingsURL: settingsURL, supportURL: directory.appendingPathComponent("support with ' quote"))
    try setup.install(relayBinary: binary); #expect(setup.isInstalled)
    try setup.install(relayBinary: binary)
    try setup.uninstall(); #expect(!setup.isInstalled)
    let restored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
    #expect(restored["theme"] as? String == "dark")
    #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "printf original")
}

@Test func claudeUninstallPreservesLaterUserEdit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settingsURL = directory.appendingPathComponent("settings.json")
    let data = Data(#"{"statusLine":{"command":"my-new-command"}}"#.utf8)
    try data.write(to: settingsURL)
    try ClaudeSetup(settingsURL: settingsURL, supportURL: directory).uninstall()
    #expect(try Data(contentsOf: settingsURL) == data)
}

@Test func codexTransportUsesHandshakeAndReadOnlyRequest() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("codex-fixture")
    let content = """
    #!/bin/sh
    read -r first
    case "$first" in *initialize*) ;; *) exit 1 ;; esac
    printf '%s\\n' '{"id":1,"result":{}}'
    read -r second
    read -r third
    case "$third" in *account*rateLimits*read*) ;; *) exit 2 ;; esac
    printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":35,"windowDurationMins":300,"resetsAt":1800003600}}}}'
    """
    try Data(content.utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let snapshot = try await CodexClient(executable: script).read()
    #expect(snapshot.windows[0].remainingPercent == 65)
}
