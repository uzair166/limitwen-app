import Foundation
import Darwin

public enum ClaudeAccount: Sendable, Equatable {
    case proOrMax, team, api, signedOut, unknown

    public var missingUsageMessage: String {
        switch self {
        case .team:
            "Claude Team hasn’t returned usage yet. Open /usage in Claude Code, then refresh."
        case .api:
            "Claude Code is using API billing. Subscription limits aren’t available through this connection."
        case .signedOut:
            "Sign in to Claude Code with your subscription, then refresh."
        case .proOrMax:
            "No saved usage yet. Open /usage in Claude Code, then refresh."
        case .unknown:
            "No saved usage yet. Sign in to Claude Code and open /usage, then refresh."
        }
    }

    public static func parse(_ data: Data) throws -> Self {
        struct Status: Decodable { let loggedIn: Bool; let authMethod: String?; let subscriptionType: String? }
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.loggedIn else { return .signedOut }
        guard status.authMethod == "claude.ai" else { return .api }
        switch status.subscriptionType?.lowercased() {
        case "pro", "max": return .proOrMax
        case "team", "enterprise": return .team
        default: return .unknown
        }
    }

    /// Uses Claude's own read-only command. No credentials or account identifiers
    /// are retained; an unavailable diagnostic never prevents a valid quota feed.
    public static func read(executable: URL? = nil, timeout: TimeInterval = 3) async -> Self {
        let worker = Task.detached(priority: .utility) { () -> Self in
            let paths = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
                         "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            guard let executable = executable ?? paths.map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return .unknown }
            do {
                let deadline = ContinuousClock.now.advanced(by: .seconds(timeout.isFinite ? max(0.05, min(timeout, 10)) : 3))
                let pipe = try ProcessPipe(executable: executable, arguments: ["auth", "status", "--json"],
                                           deadline: deadline, maximumBytes: 65_536)
                return try parse(pipe.completedOutput())
            } catch { return .unknown }
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }
}
