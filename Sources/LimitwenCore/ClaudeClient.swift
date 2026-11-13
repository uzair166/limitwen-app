import Foundation
import Darwin

public enum ClaudeFailure: Error, LocalizedError, Sendable {
    case notInstalled, updateRequired, accountChanged
    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Install Claude Code and sign in, then refresh."
        case .updateRequired: "Update Claude Code to 2.1.273 or later to refresh automatically. Saved usage is still available."
        case .accountChanged: "Claude’s account changed or signed out. Open Claude Code, sign in, and refresh."
        }
    }
}

/// Claude owns authentication and network access. Limitwen runs only its built-in
/// local /usage command, then reads quota fields from Claude's account-bound cache.
public struct ClaudeClient: Sendable {
    private let executable: URL?
    private let configuration: URL
    private let timeout: TimeInterval

    public init(executable: URL? = nil, configuration: URL? = nil, timeout: TimeInterval = 15) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        self.executable = executable ?? paths.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let configRoot = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home
        self.configuration = configuration ?? configRoot.appendingPathComponent(".claude.json")
        self.timeout = timeout.isFinite ? max(0.05, min(timeout, 30)) : 15
    }

    public func read(refresh: Bool = true) async throws -> UsageSnapshot {
        let worker = Task.detached(priority: .utility) {
            if refresh {
                guard let executable else { throw ClaudeFailure.notInstalled }
                let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
                let version = try command(executable, arguments: ["--version"], deadline: deadline)
                guard Self.supportsLocalUsage(version) else { throw ClaudeFailure.updateRequired }
                let result = try command(executable, arguments: ["--safe-mode", "--no-session-persistence", "--tools", "",
                    "--max-budget-usd", "0.000001", "--output-format", "json", "-p", "/usage"], deadline: deadline)
                struct Receipt: Decodable {
                    let type: String; let subtype: String; let is_error: Bool; let local_command: String
                    let num_turns: Int; let total_cost_usd: Double; let duration_api_ms: Double
                }
                guard let receipt = try? JSONDecoder().decode(Receipt.self, from: result), receipt.type == "result",
                      receipt.subtype == "success", !receipt.is_error, receipt.local_command == "usage",
                      receipt.num_turns == 0, receipt.total_cost_usd == 0, receipt.duration_api_ms == 0 else {
                    throw ProviderFailure.invalidResponse
                }
            }
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: configuration.path) else { throw ProviderFailure.noObservation }
            let data = try LocalStorage.readData(from: configuration, maximumBytes: 8_388_608, allowSymbolicLink: true)
            return try UsageParser.claudeCache(data, now: Date())
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private static func supportsLocalUsage(_ data: Data) -> Bool {
        guard let token = String(data: data, encoding: .utf8)?.split(separator: " ").first else { return false }
        let parts = token.split(separator: ".").compactMap { Int($0) }
        // The first release verified here to execute /usage without a model turn.
        // Unknown major versions require revalidation of that contract.
        return parts.count == 3 && parts[0] == 2 && (parts[1] > 1 || (parts[1] == 1 && parts[2] >= 273))
    }

    private func command(_ executable: URL, arguments: [String], deadline: ContinuousClock.Instant) throws -> Data {
        let pipe = try ProcessPipe(executable: executable, arguments: arguments,
                                   directory: configuration.deletingLastPathComponent(), deadline: deadline)
        return try pipe.completedOutput()
    }
}

extension UsageParser {
    private struct ClaudeCache: Decodable {
        let oauthAccount: Account?
        let cachedUsageUtilization: Observation?
        struct Account: Decodable { let accountUuid: String? }
        struct Observation: Decodable { let accountUuid: String?; let fetchedAtMs: Double; let utilization: Utilization }
        struct Utilization: Decodable {
            let five_hour: Window?; let seven_day: Window?
            let seven_day_opus: Window?; let seven_day_sonnet: Window?
            let limits: [Limit]?
        }
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Limit: Decodable {
            let kind: String; let percent: Double?; let resets_at: String?; let scope: Scope?
            struct Scope: Decodable {
                let model: Label?; let surface: Label?
                struct Label: Decodable { let id: String?; let display_name: String? }
            }
        }
    }

    public static func claudeCache(_ data: Data, now: Date) throws -> UsageSnapshot {
        let cache: ClaudeCache
        do { cache = try JSONDecoder().decode(ClaudeCache.self, from: data) }
        catch { throw ProviderFailure.invalidResponse }
        guard let account = cache.oauthAccount?.accountUuid, !account.isEmpty else { throw ClaudeFailure.accountChanged }
        guard let observation = cache.cachedUsageUtilization else { throw ProviderFailure.noObservation }
        guard observation.accountUuid == account else { throw ClaudeFailure.accountChanged }
        let seconds = observation.fetchedAtMs / 1000
        guard seconds.isFinite, seconds > 0, seconds <= now.timeIntervalSince1970 + 60 else { throw ProviderFailure.invalidResponse }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        func date(_ value: String?) -> Date? { value.flatMap { fractional.date(from: $0) ?? whole.date(from: $0) } }
        let utilization = observation.utilization
        let windows: [QuotaWindow]
        if let limits = utilization.limits {
            windows = limits.compactMap { limit in
                let id: String, title: String, duration: Int
                switch limit.kind {
                case "session": id = "five-hour"; title = "5-hour window"; duration = 300
                case "weekly_all": id = "weekly"; title = "Weekly window"; duration = 10080
                case "weekly_scoped":
                    let labels = [limit.scope?.model?.display_name, limit.scope?.surface?.display_name].compactMap { $0 }.filter { !$0.isEmpty }
                    guard !labels.isEmpty else { return nil }
                    let identity = [limit.scope?.model?.id ?? limit.scope?.model?.display_name,
                                    limit.scope?.surface?.id ?? limit.scope?.surface?.display_name].compactMap { $0 }
                    id = "weekly:" + identity.map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
                    title = labels.joined(separator: " · ") + " · weekly"; duration = 10080
                default: return nil
                }
                return QuotaWindow(id: id, title: title, durationMinutes: duration, usedPercent: limit.percent, resetsAt: date(limit.resets_at))
            }
        } else {
            let entries: [(String, String, Int, ClaudeCache.Window?)] = [
                ("five-hour", "5-hour window", 300, utilization.five_hour), ("weekly", "Weekly window", 10080, utilization.seven_day),
                ("weekly:opus", "Opus · weekly", 10080, utilization.seven_day_opus), ("weekly:sonnet", "Sonnet · weekly", 10080, utilization.seven_day_sonnet)]
            windows = entries.compactMap { id, title, duration, window in
                window.map { QuotaWindow(id: id, title: title, durationMinutes: duration, usedPercent: $0.utilization, resetsAt: date($0.resets_at)) }
            }
        }
        guard !windows.isEmpty else { throw ProviderFailure.noObservation }
        guard Set(windows.map(\.id)).count == windows.count else { throw ProviderFailure.invalidResponse }
        return UsageSnapshot(provider: .claude, windows: windows, observedAt: Date(timeIntervalSince1970: seconds), source: "Claude Code")
    }
}
