import Foundation
import Testing
@testable import LimitwenCore

private func fixture(_ content: String) throws -> (URL, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent("fixture")
    try Data(("#!/bin/sh\n" + content).utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return (directory, executable)
}

@Test func transportDeadlineStopsAnUnresponsiveProcess() async throws {
    let (directory, executable) = try fixture("while IFS= read -r line; do :; done\n")
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: ProviderFailure.timedOut) { try await CodexClient(executable: executable, timeout: 0.15).read() }
}

@Test(arguments: [("Not authenticated", ProviderFailure.authentication), ("Service temporarily offline", .unavailable)])
func transportClassifiesErrorsWithoutExposingServerText(value: (String, ProviderFailure)) async throws {
    let error: [String: Any] = ["id": 1, "error": ["message": value.0]]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: error), as: UTF8.self)
    let (directory, executable) = try fixture("read -r line\nprintf '%s\\n' '\(json)'\n")
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: value.1) { try await CodexClient(executable: executable).read() }
}

@Test func cancellationStopsProviderWork() async throws {
    let (directory, executable) = try fixture("while IFS= read -r line; do :; done\n")
    defer { try? FileManager.default.removeItem(at: directory) }
    let task = Task { try await CodexClient(executable: executable).read() }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func decodedWindowsCannotBypassNormalization() throws {
    let data = Data(#"{"id":"test","title":"Test","usedPercent":200,"resetsAt":1e100}"#.utf8)
    let window = try JSONDecoder().decode(QuotaWindow.self, from: data)
    #expect(window.remainingPercent == 0)
    #expect(window.resetsAt == nil)
    #expect(window.cycleID == nil)
}

@Test func oversizedLocalCacheIsRejected() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("snapshot.json")
    try Data(repeating: 32, count: 1_048_577).write(to: url)
    #expect(throws: ProviderFailure.invalidResponse) { try LocalStorage.read(UsageSnapshot.self, from: url) }
}

@Test func duplicateSourceWindowsAreRejectedInsteadOfSharingUIIdentity() {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300},"secondary":{"usedPercent":10,"windowDurationMins":300}}}"#.utf8)
    #expect(throws: ProviderFailure.invalidResponse) { try UsageParser.codex(data, observedAt: Date()) }
}

@Test func codexRejectsAQuotaReplyBeforeInitializationCompletes() async throws {
    let (directory, executable) = try fixture("read -r line\nprintf '%s\\n' '{\"id\":2,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":15,\"windowDurationMins\":300}}}}'\n")
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: (any Error).self) { try await CodexClient(executable: executable, timeout: 0.2).read() }
}

@Test func codexEarlyExitIsNotMisreportedAsADeadline() async throws {
    let (directory, executable) = try fixture("read -r line\nexit 1\n")
    defer { try? FileManager.default.removeItem(at: directory) }
    // This checks EOF classification, not launch speed. A 200 ms deadline can
    // legitimately expire while the OS starts the fixture on a busy build host.
    await #expect(throws: ProviderFailure.unavailable) { try await CodexClient(executable: executable, timeout: 5).read() }
}
