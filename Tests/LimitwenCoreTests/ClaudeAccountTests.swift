import Foundation
import Testing
@testable import LimitwenCore

@Test(arguments: [
    (#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"team","email":"discard-me"}"#, ClaudeAccount.team),
    (#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}"#, .proOrMax),
    (#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"enterprise"}"#, .team),
    (#"{"loggedIn":true,"authMethod":"api_key"}"#, .api),
    (#"{"loggedIn":false}"#, .signedOut),
    (#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"new-plan"}"#, .unknown)
])
func claudeAccountDiagnosticsDiscardIdentity(input: (String, ClaudeAccount)) throws {
    #expect(try ClaudeAccount.parse(Data(input.0.utf8)) == input.1)
}

@Test func claudeAccountReadHasADeadlineAndDoesNotSendPrompts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let binary = directory.appendingPathComponent("claude")
    let script = """
    #!/bin/sh
    [ "$1" = auth ] && [ "$2" = status ] && [ "$3" = --json ] || exit 1
    printf '%s' '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"team"}'
    """
    try Data(script.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    #expect(await ClaudeAccount.read(executable: binary) == .team)
    try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: binary)
    let start = ContinuousClock.now
    #expect(await ClaudeAccount.read(executable: binary, timeout: 0.1) == .unknown)
    #expect(start.duration(to: .now) < .seconds(2))
}

@Test func failedAuthDiagnosticCannotClaimAnAuthenticatedAccount() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let binary = directory.appendingPathComponent("claude")
    try Data("#!/bin/sh\nprintf '%s' '{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"subscriptionType\":\"team\"}'\nexit 1\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    #expect(await ClaudeAccount.read(executable: binary, timeout: 0.2) == .unknown)
}
