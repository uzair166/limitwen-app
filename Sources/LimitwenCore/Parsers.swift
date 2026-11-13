import Foundation

public enum ProviderFailure: Error, LocalizedError, Sendable, Equatable {
    case notInstalled, timedOut, invalidResponse, authentication, unavailable, noObservation
    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Install Codex CLI, then sign in with codex login."
        case .timedOut: "The connection took too long. Try refreshing."
        case .invalidResponse: "The provider returned an unreadable response. Try updating its app."
        case .authentication: "Sign in to Codex CLI, then refresh your limits."
        case .unavailable: "Usage is temporarily unavailable. Try again shortly."
        case .noObservation: "Waiting for usage from Claude Code."
        }
    }
}

public enum UsageParser {
    private struct CodexResult: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
        struct Bucket: Decodable { let primary: Window?; let secondary: Window? }
        struct Window: Decodable { let usedPercent: Double?; let windowDurationMins: Int?; let resetsAt: Double? }
    }
    public static func codex(_ data: Data, observedAt: Date) throws -> UsageSnapshot {
        let result: CodexResult
        do { result = try JSONDecoder().decode(CodexResult.self, from: data) }
        catch { throw ProviderFailure.invalidResponse }
        guard let bucket = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits else { throw ProviderFailure.unavailable }
        let windows = [bucket.primary, bucket.secondary].enumerated().compactMap { index, value -> QuotaWindow? in
            guard let value else { return nil }
            let duration = value.windowDurationMins
            let id: String
            let title: String
            switch duration {
            case 300: id = "five-hour"; title = "5-hour window"
            case 10080: id = "weekly"; title = "Weekly window"
            case .some(let minutes) where minutes > 0: id = "window-\(minutes)"; title = "\(minutes)-minute window"
            default: id = "window-\(index)"; title = index == 0 ? "Primary window" : "Secondary window"
            }
            return QuotaWindow(id: id, title: title, durationMinutes: duration, usedPercent: value.usedPercent,
                               resetsAt: value.resetsAt.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil })
        }
        guard Set(windows.map(\.id)).count == windows.count else { throw ProviderFailure.invalidResponse }
        return UsageSnapshot(provider: .codex, windows: windows, observedAt: observedAt, source: "Codex CLI")
    }

    private struct ClaudeInput: Decodable {
        let rate_limits: Limits?
        struct Limits: Decodable { let five_hour: Window?; let seven_day: Window?; let spend_limit: Window? }
        struct Window: Decodable { let used_percentage: Double?; let resets_at: Double? }
    }
    /// Consumes the documented status-line envelope, discarding all non-quota fields.
    public static func claude(_ data: Data, observedAt: Date) throws -> UsageSnapshot {
        let input: ClaudeInput
        do { input = try JSONDecoder().decode(ClaudeInput.self, from: data) }
        catch { throw ProviderFailure.invalidResponse }
        let limits = input.rate_limits
        let values: [(String, String, Int?, ClaudeInput.Window?)] = [
            ("five-hour", "5-hour window", 300, limits?.five_hour),
            ("weekly", "Weekly window", 10080, limits?.seven_day),
            ("spend", "Spend allowance", nil, limits?.spend_limit)
        ]
        let windows = values.compactMap { id, title, duration, value -> QuotaWindow? in
            guard let value else { return nil }
            return QuotaWindow(id: id, title: title, durationMinutes: duration, usedPercent: value.used_percentage,
                               resetsAt: value.resets_at.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil })
        }
        // A new session and a reset can both omit rate_limits. Neither is a new
        // measurement. Preserve the previous observation and its original timestamp.
        guard !windows.isEmpty else { throw ProviderFailure.noObservation }
        return UsageSnapshot(provider: .claude, windows: windows, observedAt: observedAt, source: "Claude Code local feed")
    }
}
