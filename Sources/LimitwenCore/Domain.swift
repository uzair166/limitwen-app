import Foundation

public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex & ChatGPT"
        }
    }
    public var initials: String {
        switch self { case .claude: "Cl"; case .codex: "Cx" }
    }
    public var symbol: String {
        switch self { case .claude: "asterisk"; case .codex: "terminal" }
    }
    public var dashboardLabel: String { "Open usage dashboard ↗" }
    public var dashboard: String {
        switch self {
        case .claude: "https://claude.ai/settings/usage"
        case .codex: "https://chatgpt.com/codex/settings/usage"
        }
    }
    public var connectionSummary: String {
        switch self {
        case .codex: "One entry for Codex and ChatGPT. Reads Codex allowance through your signed-in Codex CLI. No API key needed."
        case .claude: "Reads limits using your existing Claude Code sign-in, including Team accounts."
        }
    }
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let durationMinutes: Int?
    public let usedPercent: Double?
    public let resetsAt: Date?

    public init(id: String, title: String, durationMinutes: Int?, usedPercent: Double?, resetsAt: Date?) {
        self.id = id; self.title = title; self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        self.resetsAt = resetsAt.flatMap {
            let seconds = $0.timeIntervalSince1970
            return seconds.isFinite && seconds > 0 && seconds < 32_503_680_000 ? $0 : nil
        }
    }
    private enum CodingKeys: String, CodingKey { case id, title, durationMinutes, usedPercent, resetsAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id), title: try values.decode(String.self, forKey: .title),
                  durationMinutes: try values.decodeIfPresent(Int.self, forKey: .durationMinutes),
                  usedPercent: try values.decodeIfPresent(Double.self, forKey: .usedPercent),
                  resetsAt: try values.decodeIfPresent(Date.self, forKey: .resetsAt))
    }
    public var remainingPercent: Double? { usedPercent.map { 100 - $0 } }
    public func hasElapsed(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public var cycleID: String? { resetsAt.map { "\(id):\(Int($0.timeIntervalSince1970))" } }
    public static let unknownShort = QuotaWindow(id: "five-hour", title: "5-hour window", durationMinutes: 300, usedPercent: nil, resetsAt: nil)
    public static let unknownWeek = QuotaWindow(id: "weekly", title: "Weekly window", durationMinutes: 10080, usedPercent: nil, resetsAt: nil)
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let windows: [QuotaWindow]
    public let observedAt: Date
    public let source: String
    public init(provider: ProviderID, windows: [QuotaWindow], observedAt: Date, source: String) {
        self.provider = provider; self.windows = windows; self.observedAt = observedAt; self.source = source
    }
    private enum CodingKeys: String, CodingKey { case provider, windows, observedAt, source }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let windows = try values.decode([QuotaWindow].self, forKey: .windows)
        let observed = try values.decode(Date.self, forKey: .observedAt)
        guard Set(windows.map(\.id)).count == windows.count, windows.count <= 64,
              windows.allSatisfy({ !$0.id.isEmpty }), observed.timeIntervalSince1970.isFinite else {
            throw ProviderFailure.invalidResponse
        }
        self.init(provider: try values.decode(ProviderID.self, forKey: .provider), windows: windows,
                  observedAt: observed, source: try values.decode(String.self, forKey: .source))
    }
    public func isStale(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return !age.isFinite || age > 900 || age < -60
    }
    /// A missing window is not evidence that the account has that allowance.
    public var displayWindows: [QuotaWindow] {
        return windows.sorted { ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max) }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var enabled: [ProviderID] = [.claude, .codex]
    public var pinned: [ProviderID] = [.claude, .codex]
    public var showInitials = true
    public var alertsEnabled = false
    public var threshold = 20
    public var resetReminders: [String: Date] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case enabled, pinned, showInitials, alertsEnabled, threshold, resetReminders
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Retired identifiers must not invalidate the user's entire preferences record.
        // Keep reminder keys until normalization so the app can cancel removed requests.
        if let ids = try values.decodeIfPresent([String].self, forKey: .enabled) {
            enabled = ids.compactMap(ProviderID.init(rawValue:))
        }
        if let ids = try values.decodeIfPresent([String].self, forKey: .pinned) {
            pinned = ids.compactMap(ProviderID.init(rawValue:))
        }
        showInitials = try values.decodeIfPresent(Bool.self, forKey: .showInitials) ?? showInitials
        alertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? alertsEnabled
        threshold = try values.decodeIfPresent(Int.self, forKey: .threshold) ?? threshold
        resetReminders = try values.decodeIfPresent([String: Date].self, forKey: .resetReminders) ?? resetReminders
    }
    public mutating func normalize() {
        var seen = Set<ProviderID>()
        enabled = enabled.filter { seen.insert($0).inserted }
        seen.removeAll()
        pinned = pinned.filter { enabled.contains($0) && seen.insert($0).inserted }
        threshold = min(95, max(1, threshold))
        resetReminders = resetReminders.filter { key, _ in enabled.contains { key.hasPrefix($0.rawValue + ":") } }
    }
    public var visiblePins: [ProviderID] { pinned.filter { enabled.contains($0) } }
}

public struct AlertLedger: Codable, Sendable {
    public private(set) var sent: [String: Date] = [:]
    public init() {}
    public func candidates(snapshot: UsageSnapshot, threshold: Int, now: Date) -> [QuotaWindow] {
        guard !snapshot.isStale(at: now) else { return [] }
        return snapshot.windows.filter { window in
            guard let remaining = window.remainingPercent, remaining <= Double(threshold),
                  !window.hasElapsed(at: now), let cycle = window.cycleID else { return false }
            return sent[snapshot.provider.rawValue + ":" + cycle] == nil
        }
    }
    public mutating func record(provider: ProviderID, window: QuotaWindow, now: Date) {
        guard let cycle = window.cycleID else { return }
        sent = sent.filter { now.timeIntervalSince($0.value) < 60 * 86400 }
        sent[provider.rawValue + ":" + cycle] = now
    }
}

public enum ResetDescription {
    public static func relative(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "Reset time unavailable" }
        let seconds = reset.timeIntervalSince(now)
        guard seconds.isFinite, abs(seconds) < 32_503_680_000 else { return "Reset time unavailable" }
        guard seconds > 0 else { return "Reset due · awaiting update" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        if minutes < 1440 {
            return minutes % 60 == 0 ? "Resets in \(minutes / 60)h" : "Resets in \(minutes / 60)h \(minutes % 60)m"
        }
        let hours = (minutes % 1440) / 60
        return hours == 0 ? "Resets in \(minutes / 1440)d" : "Resets in \(minutes / 1440)d \(hours)h"
    }
}
