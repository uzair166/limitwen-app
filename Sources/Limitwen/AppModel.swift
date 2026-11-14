import SwiftUI
import LimitwenCore

struct ProviderState: Equatable {
    var snapshot: UsageSnapshot?
    var refreshing = false
    var error: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences: Preferences
    @Published var states: [ProviderID: ProviderState] = [:]
    @Published var selected: ProviderID?
    @Published var preview: Bool
    private(set) var now: Date
    @Published var popoverAvailableHeight: CGFloat = 760
    private var visiblePresentations: Set<String> = []
    @Published var notice: String?
    @Published var claudeInstalled: Bool
    @Published private(set) var claudeAccount: ClaudeAccount = .unknown
    @Published private(set) var pendingReminders: Set<String> = []
    var onMenuChange: (() -> Void)?
    var onSettings: (() -> Void)?
    private let defaults: UserDefaults
    private let storageDirectory: URL
    private let notifications: any NotificationDelivery
    private let clock: () -> Date
    private let readCodex: @Sendable () async throws -> UsageSnapshot
    private let readClaudeAccount: @Sendable () async -> ClaudeAccount
    private let readClaude: @Sendable (Bool) async throws -> UsageSnapshot
    private var claudeTask: Task<UsageSnapshot, Error>?
    private var claudeGeneration = 0
    private var nextClaudeRead = Date.distantPast
    private var lastClaudeAttempt = Date.distantPast
    private var claudeFailures = 0
    private var ledger: AlertLedger
    private var loop: Task<Void, Never>?
    private var providerTask: Task<UsageSnapshot, Error>?
    private var deliveringAlerts = false
    private var nextCodexRead = Date.distantPast
    private var lastCodexAttempt = Date.distantPast
    private var failures = 0
    private var codexGeneration = 0
    private var alertsRevision = 0
    private var reminderRevisions: [String: Int] = [:]
    private var generation = 0
    private var liveStatesBeforePreview: [ProviderID: ProviderState]?
    private let previewOrigin: Date

    init(preview: Bool = false, defaults: UserDefaults = .standard, storageDirectory: URL = LocalStorage.directory,
         notifications: any NotificationDelivery = SystemNotifications(), clock: @escaping () -> Date = { Date() },
         readCodex: @escaping @Sendable () async throws -> UsageSnapshot = { try await CodexClient().read() },
         readClaudeAccount: (@Sendable () async -> ClaudeAccount)? = nil,
         readClaude: (@Sendable (Bool) async throws -> UsageSnapshot)? = nil) {
        self.preview = preview
        self.defaults = defaults; self.storageDirectory = storageDirectory
        self.notifications = notifications; self.clock = clock; self.readCodex = readCodex
        if let readClaudeAccount { self.readClaudeAccount = readClaudeAccount }
        else if storageDirectory == LocalStorage.directory { self.readClaudeAccount = { await ClaudeAccount.read() } }
        else { self.readClaudeAccount = { .unknown } }
        if let readClaude { self.readClaude = readClaude }
        else if storageDirectory == LocalStorage.directory { self.readClaude = { try await ClaudeClient().read(refresh: $0) } }
        else { self.readClaude = { _ in throw ProviderFailure.noObservation } }
        let initialTime = clock()
        now = initialTime; previewOrigin = initialTime
        claudeInstalled = defaults.object(forKey: "claudeConnected") as? Bool
            ?? true
        preferences = Preferences()
        ledger = defaults.data(forKey: "alertLedger").flatMap { try? JSONDecoder().decode(AlertLedger.self, from: $0) } ?? AlertLedger()
        restorePreferences()
        if preview { loadPreview() }

    }

    private func restorePreferences() {
        let saved = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        preferences = saved ?? Preferences()
        // Preserve an explicit opt-out from releases with a separate Connect control.
        if !claudeInstalled { preferences.enabled.removeAll { $0 == .claude } }
        let previousReminders = preferences.resetReminders
        preferences.normalize()
        guard !preview, saved != nil else { return }
        for key in previousReminders.keys where preferences.resetReminders[key] == nil {
            notifications.cancel(["reset:" + key])
        }
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences") }
    }

    func setPresentationVisible(_ name: String, visible: Bool) {
        if visible { visiblePresentations.insert(name); updateClock() }
        else { visiblePresentations.remove(name) }
    }
    private func updateClock() {
        let value = clock()
        guard value != now else { return }
        if !visiblePresentations.isEmpty { objectWillChange.send() }
        now = value
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    func stop() {
        generation += 1; claudeGeneration += 1; codexGeneration += 1; alertsRevision += 1
        loop?.cancel(); loop = nil; providerTask?.cancel(); providerTask = nil; claudeTask?.cancel(); claudeTask = nil
        for provider in ProviderID.allCases { states[provider]?.refreshing = false }
    }
    func showSettings() { onSettings?() }
    func change(_ update: (inout Preferences) -> Void) {
        let previous = preferences
        let previousReminders = previous.resetReminders
        update(&preferences); preferences.normalize()
        for key in Set(previousReminders.keys).union(preferences.resetReminders.keys)
            where previousReminders[key] != preferences.resetReminders[key] {
            reminderRevisions[key, default: 0] += 1
        }
        if previous.alertsEnabled != preferences.alertsEnabled || previous.threshold != preferences.threshold { alertsRevision += 1 }
        if previous.enabled.contains(.claude) != preferences.enabled.contains(.claude) {
            if !preview {
                claudeInstalled = preferences.enabled.contains(.claude)
                if claudeInstalled { notice = nil }
                defaults.set(claudeInstalled, forKey: "claudeConnected")
            }
            claudeGeneration += 1; claudeTask?.cancel(); claudeTask = nil; nextClaudeRead = .distantPast; lastClaudeAttempt = .distantPast
            states[.claude] = nil
        }
        if previous.enabled.contains(.codex) != preferences.enabled.contains(.codex) {
            codexGeneration += 1; providerTask?.cancel(); providerTask = nil; nextCodexRead = .distantPast; lastCodexAttempt = .distantPast
            states[.codex] = nil
        }
        if !preview {
            for key in previousReminders.keys where preferences.resetReminders[key] == nil {
                notifications.cancel(["reset:" + key])
            }
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences") }
        }
        onMenuChange?()
    }
    func setPreview(_ enabled: Bool) {
        guard preview != enabled else { return }
        providerTask?.cancel(); providerTask = nil
        claudeGeneration += 1; claudeTask?.cancel(); claudeTask = nil
        generation += 1; preview = enabled; notice = nil
        if enabled {
            liveStatesBeforePreview = states.mapValues { state in
                var retained = state; retained.refreshing = false; return retained
            }
            loadPreview()
        }
        else {
            restorePreferences()
            states = liveStatesBeforePreview ?? [:]
            liveStatesBeforePreview = nil
            nextClaudeRead = .distantPast; lastClaudeAttempt = .distantPast
            nextCodexRead = .distantPast
            lastCodexAttempt = .distantPast
            Task { await refresh(force: true) }
        }
        onMenuChange?()
    }
    private func loadPreview() {
        preferences = Preferences(); preferences.alertsEnabled = true
        let source = "Preview · example values"
        func window(_ id: String, _ title: String, _ minutes: Int, _ used: Double, _ seconds: Double) -> QuotaWindow {
            QuotaWindow(id: id, title: title, durationMinutes: minutes, usedPercent: used, resetsAt: previewOrigin.addingTimeInterval(seconds))
        }
        states = [
            .claude: ProviderState(snapshot: UsageSnapshot(provider: .claude, windows: [window("five-hour", "5-hour window", 300, 82, 8040), window("weekly", "Weekly window", 10080, 38, 152400)], observedAt: now, source: source)),
            .codex: ProviderState(snapshot: UsageSnapshot(provider: .codex, windows: [window("five-hour", "5-hour window", 300, 36, 2520), window("weekly", "Weekly window", 10080, 59, 325200)], observedAt: now, source: source))
        ]
    }

    func refresh(force: Bool = false) async {
        guard !preview, !Task.isCancelled else { return }
        let currentGeneration = generation
        updateClock()
        async let claude: Void = refreshClaude(force: force)
        async let codex: Void = refreshCodex(force: force)
        _ = await (claude, codex)
        guard currentGeneration == generation, !preview, !Task.isCancelled else { return }
        updateClock()
        onMenuChange?()
        await reconcileReminders()
        await deliverLowAlerts()
    }

    private func refreshCodex(force: Bool) async {
        guard providerTask == nil else { return }
        let currentGeneration = generation, revision = codexGeneration
        func isCurrent() -> Bool { currentGeneration == generation && revision == codexGeneration && !preview && preferences.enabled.contains(.codex) && !Task.isCancelled }
        defer { onMenuChange?() }
        let resetDue = states[.codex]?.snapshot?.windows.contains { window in
            window.resetsAt.map { $0 <= now && lastCodexAttempt < $0 } ?? false
        } == true
        let clockMovedBackwards = now < lastCodexAttempt
        if preferences.enabled.contains(.codex), (force || resetDue || clockMovedBackwards || now >= nextCodexRead),
           (clockMovedBackwards || now.timeIntervalSince(lastCodexAttempt) >= 2) {
            lastCodexAttempt = now
            states[.codex, default: ProviderState()].refreshing = true
            do {
                let readCodex = readCodex
                let task = Task { try await readCodex() }
                providerTask = task
                defer {
                    if currentGeneration == generation && revision == codexGeneration {
                        providerTask = nil
                        if states[.codex]?.refreshing == true { states[.codex]?.refreshing = false }
                    }
                }
                let snapshot = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard isCurrent() else { return }
                states[.codex] = ProviderState(snapshot: snapshot)
                failures = 0
            } catch {
                guard isCurrent() else { return }
                states[.codex, default: ProviderState()].refreshing = false
                if case ProviderFailure.authentication = error { states[.codex] = nil }
                states[.codex, default: ProviderState()].error = error.localizedDescription
                failures += 1
            }
            providerTask = nil
            nextCodexRead = clock().addingTimeInterval(min(900, 300 * pow(2, Double(min(failures, 2)))))
        }
    }

    private func refreshClaude(force: Bool) async {
        guard preferences.enabled.contains(.claude), claudeInstalled, claudeTask == nil else { return }
        defer { onMenuChange?() }
        let revision = claudeGeneration
        defer {
            if revision == claudeGeneration {
                claudeTask = nil
                if states[.claude]?.refreshing == true { states[.claude]?.refreshing = false }
            }
        }
        func isCurrent() -> Bool { revision == claudeGeneration && !preview && claudeInstalled && preferences.enabled.contains(.claude) && !Task.isCancelled }
        let readClaude = readClaude
        let cacheTask = Task { try await readClaude(false) }
        claudeTask = cacheTask
        do {
            let snapshot = try await withTaskCancellationHandler(operation: { try await cacheTask.value }, onCancel: { cacheTask.cancel() })
            guard isCurrent() else { return }
            let previous = states[.claude]
            let previousError = previous?.snapshot?.observedAt == snapshot.observedAt ? previous?.error : nil
            let updated = ProviderState(snapshot: snapshot, error: previousError)
            if previous != updated { states[.claude] = updated }
        } catch {
            guard isCurrent() else { return }
            if error is CancellationError { return }
            if case ClaudeFailure.accountChanged = error { states[.claude] = nil }
            states[.claude, default: ProviderState()].error = error.localizedDescription
        }
        claudeTask = nil
        let resetDue = states[.claude]?.snapshot?.windows.contains {
            $0.resetsAt.map { $0 <= now && lastClaudeAttempt < $0 } ?? false
        } == true
        let clockMovedBackwards = now < lastClaudeAttempt
        guard (force || resetDue || clockMovedBackwards || now >= nextClaudeRead),
              clockMovedBackwards || now.timeIntervalSince(lastClaudeAttempt) >= 2 else { return }
        lastClaudeAttempt = now
        states[.claude, default: ProviderState()].refreshing = true
        let task = Task { try await readClaude(true) }
        claudeTask = task
        do {
            let snapshot = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard isCurrent() else { return }
            states[.claude] = ProviderState(snapshot: snapshot)
            claudeFailures = 0
        } catch {
            guard isCurrent() else { return }
            states[.claude, default: ProviderState()].refreshing = false
            if error is CancellationError { return }
            if case ClaudeFailure.accountChanged = error { states[.claude] = nil }
            if case ProviderFailure.noObservation = error {
                let account = await readClaudeAccount()
                guard isCurrent() else { return }
                claudeAccount = account
                states[.claude, default: ProviderState()].error = account.missingUsageMessage
            } else { states[.claude, default: ProviderState()].error = error.localizedDescription }
            claudeFailures += 1
        }
        claudeTask = nil
        nextClaudeRead = clock().addingTimeInterval(min(900, 300 * pow(2, Double(min(claudeFailures, 2)))))
    }

    func reminderKey(_ provider: ProviderID, _ window: QuotaWindow) -> String { provider.rawValue + ":" + window.id }
    func reminderEnabled(_ provider: ProviderID, _ window: QuotaWindow) -> Bool {
        guard let reset = window.resetsAt else { return false }
        return preferences.resetReminders[reminderKey(provider, window)] == reset && reset > now
    }
    func toggleReminder(_ provider: ProviderID, _ window: QuotaWindow) async {
        let key = reminderKey(provider, window)
        guard !pendingReminders.contains(key) else { return }
        if reminderEnabled(provider, window) { change { $0.resetReminders.removeValue(forKey: key) }; return }
        guard let reset = window.resetsAt, reset > clock() else { return }
        if preview { change { $0.resetReminders[key] = reset }; return }
        pendingReminders.insert(key)
        defer { pendingReminders.remove(key) }
        let currentGeneration = generation, revision = reminderRevisions[key, default: 0]
        let connection = provider == .claude ? claudeGeneration : codexGeneration
        func isCurrent() -> Bool {
            currentGeneration == generation && revision == reminderRevisions[key, default: 0]
                && connection == (provider == .claude ? claudeGeneration : codexGeneration)
                && !preview && preferences.enabled.contains(provider) && (provider != .claude || claudeInstalled)
        }
        guard await authorizeNotifications(), isCurrent(), reset > clock() else { return }
        do {
            try await scheduleReset(provider, window)
            guard isCurrent() else {
                notifications.cancel(["reset:" + key]); return
            }
            change { $0.resetReminders[key] = reset }
        } catch { if isCurrent() { notice = "The reminder couldn’t be saved. Try again." } }
    }
    func cancelResetReminders() {
        for key in pendingReminders { reminderRevisions[key, default: 0] += 1 }
        change { $0.resetReminders.removeAll() }
    }
    func setAlerts(_ enabled: Bool) async {
        alertsRevision += 1
        let revision = alertsRevision
        let currentGeneration = generation
        if enabled && !preview {
            guard await authorizeNotifications() else { return }
        }
        guard currentGeneration == generation, revision == alertsRevision else { return }
        change { $0.alertsEnabled = enabled }
        if enabled && !preview { await deliverLowAlerts() }
    }
    private func authorizeNotifications() async -> Bool {
        let revision = generation
        do {
            let allowed = try await notifications.authorize()
            guard revision == generation, !preview else { return false }
            if !allowed { notice = "Notifications are off for Limitwen. Enable them in System Settings → Notifications." }
            return allowed
        } catch { if revision == generation && !preview { notice = "Notification permission couldn’t be checked." }; return false }
    }
    private func deliverLowAlerts() async {
        guard preferences.alertsEnabled, !preview, !deliveringAlerts else { return }
        deliveringAlerts = true
        defer { deliveringAlerts = false }
        let currentGeneration = generation, alertRevision = alertsRevision
        for provider in preferences.enabled {
            let connection = provider == .claude ? claudeGeneration : codexGeneration
            func isCurrent() -> Bool { currentGeneration == generation && alertRevision == alertsRevision && connection == (provider == .claude ? claudeGeneration : codexGeneration) && !preview && preferences.alertsEnabled && preferences.enabled.contains(provider) && (provider != .claude || claudeInstalled) }
            guard let state = states[provider], state.error == nil, let snapshot = state.snapshot else { continue }
            for window in ledger.candidates(snapshot: snapshot, threshold: preferences.threshold, now: now) {
                guard isCurrent() else { return }
                let message = LimitNotification(id: "low:\(provider.rawValue):\(window.cycleID ?? window.id)", title: "\(provider.name) is running low",
                    body: "\(Int((window.remainingPercent ?? 0).rounded()))% remains in your \(window.title.lowercased()). \(ResetDescription.relative(window.resetsAt, now: now)).")
                do {
                    try await notifications.schedule(message)
                    guard isCurrent() else { notifications.cancel([message.id]); return }
                    ledger.record(provider: provider, window: window, now: now)
                    if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "alertLedger") }
                } catch { if isCurrent() { notice = "A low-limit notification couldn’t be delivered." } }
            }
        }
    }
    private func scheduleReset(_ provider: ProviderID, _ window: QuotaWindow) async throws {
        try await notifications.schedule(LimitNotification(id: "reset:" + reminderKey(provider, window), title: "\(provider.name) reset time",
            body: "Your \(window.title.lowercased()) is scheduled to reset now. Open Limitwen to check the latest allowance.", date: window.resetsAt))
    }
    private func reconcileReminders() async {
        guard !preview else { return }
        let currentGeneration = generation
        for (key, previousReset) in preferences.resetReminders {
            guard currentGeneration == generation, !preview else { return }
            guard previousReset > now else { change { $0.resetReminders.removeValue(forKey: key) }; continue }
            for provider in preferences.enabled {
                guard let state = states[provider], state.error == nil, let snapshot = state.snapshot, !snapshot.isStale(at: now),
                      let window = snapshot.windows.first(where: { reminderKey(provider, $0) == key }),
                      let reset = window.resetsAt, reset != previousReset, reset > now else { continue }
                await correctReminder(provider, window: window, previous: previousReset)
            }
        }
    }
    private func correctReminder(_ provider: ProviderID, window: QuotaWindow, previous: Date) async {
        let key = reminderKey(provider, window)
        guard !pendingReminders.contains(key) else { return }
        pendingReminders.insert(key)
        defer { pendingReminders.remove(key) }
        let currentGeneration = generation, revision = reminderRevisions[key, default: 0]
        let connection = provider == .claude ? claudeGeneration : codexGeneration
        func isCurrent() -> Bool {
            currentGeneration == generation && revision == reminderRevisions[key, default: 0]
                && connection == (provider == .claude ? claudeGeneration : codexGeneration)
                && !preview && preferences.enabled.contains(provider) && (provider != .claude || claudeInstalled)
                && preferences.resetReminders[key] == previous
        }
        guard isCurrent() else { return }
        do {
            try await scheduleReset(provider, window)
            guard isCurrent() else {
                // A correction replaces the existing OS request. A preview round trip
                // must not erase the real reminder that existed before that edit.
                func originalStillSaved() -> Bool {
                    guard let data = defaults.data(forKey: "preferences"),
                          let saved = try? JSONDecoder().decode(Preferences.self, from: data) else { return false }
                    return saved.enabled.contains(provider) && saved.resetReminders[key] == previous
                        && previous > clock() && (provider != .claude || claudeInstalled)
                }
                if originalStillSaved() {
                    let original = QuotaWindow(id: window.id, title: window.title, durationMinutes: window.durationMinutes,
                        usedPercent: window.usedPercent, resetsAt: previous)
                    try await scheduleReset(provider, original)
                    if !originalStillSaved() { notifications.cancel(["reset:" + key]) }
                } else { notifications.cancel(["reset:" + key]) }
                return
            }
            change { $0.resetReminders[key] = window.resetsAt }
        } catch { if isCurrent() { notice = "A reset time changed, but its reminder couldn’t be updated." } }
    }
    func disconnectClaude() {
        guard !preview else { return }
        claudeGeneration += 1; claudeTask?.cancel(); claudeTask = nil
        claudeInstalled = false; states[.claude] = nil
        change {
            $0.enabled.removeAll { $0 == .claude }
            $0.resetReminders = $0.resetReminders.filter { !$0.key.hasPrefix("claude:") }
        }
        defaults.set(false, forKey: "claudeConnected")
        notice = "Claude disconnected."
        if storageDirectory == LocalStorage.directory {
            let revision = claudeGeneration
            Task { [weak self] in
                let restored = await Task.detached(priority: .utility) { () -> Result<Bool, Error> in
                    Result { try ClaudeSetup().uninstall() }
                }.value
                guard let self, self.claudeGeneration == revision, !self.claudeInstalled else { return }
                switch restored {
                case .success(true): self.notice = "Claude disconnected. The previous status line has been restored."
                case .success(false): break
                case .failure: self.notice = "Claude disconnected. Its previous status line couldn’t be restored; check Claude’s settings."
                }
            }
        }
        onMenuChange?()
    }
}
