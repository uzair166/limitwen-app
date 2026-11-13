import Foundation
import Testing
@testable import LimitwenCore

private struct ClaudeFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var binary: URL { directory.appendingPathComponent("claude") }
    var config: URL { directory.appendingPathComponent("config.json") }
    var calls: URL { directory.appendingPathComponent("calls") }
    init(version: String = "2.1.273", body: String = "") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(calls.path)'
        if [ "$1" = --version ]; then printf '%s\\n' '\(version) (Claude Code)'; exit 0; fi
        \(body)
        printf '%s' '{"type":"result","subtype":"success","is_error":false,"local_command":"usage","num_turns":0,"total_cost_usd":0,"duration_api_ms":0}'
        """
        try Data(script.utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    }
    func saveCache() throws {
        let data = #"{"oauthAccount":{"accountUuid":"fixture"},"cachedUsageUtilization":{"accountUuid":"fixture","fetchedAtMs":1700000000000,"utilization":{"seven_day":{"utilization":9,"resets_at":null}}}}"#
        try Data(data.utf8).write(to: config)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Test func claudeNativeRefreshOnlyInvokesTheBuiltinUsageCommandAndPreservesCacheAge() async throws {
    let f = try ClaudeFixture(); defer { f.clean() }
    try f.saveCache()
    let reading = try await ClaudeClient(executable: f.binary, configuration: f.config).read()
    #expect(reading.windows[0].remainingPercent == 91)
    #expect(reading.observedAt == Date(timeIntervalSince1970: 1_700_000_000))
    let commands = try String(contentsOf: f.calls, encoding: .utf8).split(separator: "\n")
    #expect(commands.count == 2)
    #expect(commands[0] == "--version")
    #expect(commands[1].contains("--safe-mode"))
    #expect(commands[1].contains("--no-session-persistence"))
    #expect(commands[1].hasSuffix("-p /usage"))
}

@Test func claudeLocalReadsDoNotRunCommands() async throws {
    let f = try ClaudeFixture(); defer { f.clean() }
    try f.saveCache()
    _ = try await ClaudeClient(executable: f.binary, configuration: f.config).read(refresh: false)
    #expect(!FileManager.default.fileExists(atPath: f.calls.path))
}

@Test func olderClaudeIsNeverSentAnUnrecognizedUsagePrompt() async throws {
    let f = try ClaudeFixture(version: "2.1.80"); defer { f.clean() }
    try f.saveCache()
    await #expect(throws: (any Error).self) { try await ClaudeClient(executable: f.binary, configuration: f.config).read() }
    #expect(try String(contentsOf: f.calls, encoding: .utf8) == "--version\n")
}

@Test func claudeNativeRefreshHasADeadlineAndRejectsNonLocalResults() async throws {
    let f = try ClaudeFixture(body: "exec /bin/sleep 30"); defer { f.clean() }
    try f.saveCache()
    let start = ContinuousClock.now
    await #expect(throws: ProviderFailure.timedOut) {
        try await ClaudeClient(executable: f.binary, configuration: f.config, timeout: 0.2).read()
    }
    #expect(start.duration(to: .now) < .seconds(2))
    let bad = try ClaudeFixture(body: "printf '%s' '{\"type\":\"result\",\"local_command\":\"usage\",\"num_turns\":1}'; exit 0")
    defer { bad.clean() }
    try bad.saveCache()
    await #expect(throws: ProviderFailure.invalidResponse) {
        try await ClaudeClient(executable: bad.binary, configuration: bad.config).read()
    }
}

@Test func claudeNativeReadCancellationStopsItsProcess() async throws {
    let f = try ClaudeFixture(body: "exec /bin/sleep 30"); defer { f.clean() }
    let task = Task { try await ClaudeClient(executable: f.binary, configuration: f.config).read() }
    // A bounded readiness check ensures cancellation exercises the running process.
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
        if let calls = try? String(contentsOf: f.calls, encoding: .utf8), calls.contains("/usage") { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect((try? String(contentsOf: f.calls, encoding: .utf8))?.contains("/usage") == true)
    let start = ContinuousClock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(start.duration(to: .now) < .seconds(2))
}

@Test func claudeNativeReadBoundsOutputAndDoesNotWaitForeverAfterEOF() async throws {
    let flood = try ClaudeFixture(body: "exec /usr/bin/yes quota"); defer { flood.clean() }
    await #expect(throws: ProviderFailure.invalidResponse) {
        try await ClaudeClient(executable: flood.binary, configuration: flood.config).read()
    }
    let closed = try ClaudeFixture(body: "exec 1>&-; exec /bin/sleep 30"); defer { closed.clean() }
    await #expect(throws: ProviderFailure.timedOut) {
        try await ClaudeClient(executable: closed.binary, configuration: closed.config, timeout: 0.2).read()
    }
}
