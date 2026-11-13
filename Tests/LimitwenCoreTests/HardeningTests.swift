import Foundation
import Testing
@testable import LimitwenCore

@Test func snapshotDecodingRejectsDuplicateWindowIdentity() throws {
    let window = QuotaWindow(id: "weekly", title: "Weekly", durationMinutes: 10080, usedPercent: 30, resetsAt: nil)
    let data = try JSONEncoder().encode(UsageSnapshot(provider: .codex, windows: [window, window], observedAt: Date(timeIntervalSince1970: 1_800_000_000), source: "fixture"))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(UsageSnapshot.self, from: data) }
}

@Test func invalidClockDoesNotClaimThatAResetIsDue() {
    #expect(ResetDescription.relative(Date(timeIntervalSince1970: .nan), now: Date()) == "Reset time unavailable")
    #expect(ResetDescription.relative(Date(), now: Date(timeIntervalSince1970: .nan)) == "Reset time unavailable")
}

@Test func localStorageRejectsSymbolicLinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target.json"), link = directory.appendingPathComponent("link.json")
    try Data("42".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: (any Error).self) { try LocalStorage.read(Int.self, from: link) }
}

@Test(arguments: ["{}", "[]", #"{"original":5}"#])
func malformedLegacyBackupCannotEraseTheStatusLine(backup: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let setup = ClaudeSetup(settingsURL: directory.appendingPathComponent("settings.json"), supportURL: directory)
    let original = try JSONSerialization.data(withJSONObject: ["statusLine": ["type":"command", "command":setup.command]])
    try original.write(to: setup.settingsURL)
    try Data(backup.utf8).write(to: setup.previousURL)
    #expect(throws: (any Error).self) { try setup.uninstall() }
    #expect(try Data(contentsOf: setup.settingsURL) == original)
}

@Test(arguments: [Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude])
func extremeResetIntervalsCannotOverflow(value: Double) {
    #expect(ResetDescription.relative(Date(timeIntervalSince1970: value), now: Date(timeIntervalSince1970: 0)) == "Reset time unavailable")
}

@Test func storageRejectsANonregularInputWithoutBlocking() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: (any Error).self) { try LocalStorage.read(Int.self, from: directory) }
}

@Test func privateAtomicWriteDoesNotChangeAnExistingParentsPermissions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    try LocalStorage.write(42, to: directory.appendingPathComponent("value.json"))
    #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o755)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["value.json"])
}

@Test func processLaunchFailureDoesNotCrashCleanup() {
    #expect(throws: (any Error).self) {
        _ = try ProcessPipe(executable: URL(fileURLWithPath: "/nonexistent/limitwen-fixture"), arguments: [], deadline: .now.advanced(by: .seconds(1)))
    }
}
