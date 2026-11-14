import Foundation
import Testing
import LimitwenCore
@testable import Limitwen

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
private func snapshot(remaining: Double = 18, reset: Date = epoch.addingTimeInterval(3600), observed: Date = epoch) -> UsageSnapshot {
    UsageSnapshot(provider: .codex, windows: [QuotaWindow(id: "weekly", title: "Weekly window", durationMinutes: 10080,
        usedPercent: 100 - remaining, resetsAt: reset)], observedAt: observed, source: "Test fixture")
}

private actor Feed {
    var value: UsageSnapshot = snapshot()
    var failure: ProviderFailure?
    var reads = 0
    func read() throws -> UsageSnapshot { reads += 1; if let failure { throw failure }; return value }
    func set(_ value: UsageSnapshot) { self.value = value; failure = nil }
    func fail() { failure = .unavailable }
}

@MainActor
private final class Delivery: NotificationDelivery {
    var allowed = true
    var authorizations = 0
    var requests: [String: LimitNotification] = [:]
    var history: [LimitNotification] = []
    func authorize() async throws -> Bool { authorizations += 1; return allowed }
    func schedule(_ notification: LimitNotification) async throws { requests[notification.id] = notification; history.append(notification) }
    func cancel(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
}

@MainActor
private final class Harness {
    let suite = "LimitwenTests." + UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let delivery = Delivery()
    let feed = Feed()
    var date = epoch
    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        var preferences = Preferences(); preferences.enabled = [.codex]; preferences.pinned = [.codex]
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
    }
    func model(preview: Bool = false) -> AppModel {
        AppModel(preview: preview, defaults: defaults, storageDirectory: directory, notifications: delivery,
                 clock: { self.date }, readCodex: { [feed] in try await feed.read() })
    }
    func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
}

@Test @MainActor func appearanceAndPinningSurviveRelaunch() throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    model.change { $0.showInitials = false; $0.pinned = [] }
    let relaunched = h.model()
    #expect(!relaunched.preferences.showInitials)
    #expect(relaunched.preferences.visiblePins.isEmpty)
    relaunched.change { $0.pinned = $0.enabled }
    #expect(h.model().preferences.visiblePins == [.codex])
}

@Test(arguments: [false, true]) @MainActor
func providerRemovalMigratesSettingsAndCancelsOnlyRemovedReminders(beginInPreview: Bool) throws {
    let h = try Harness(); defer { h.clean() }
    let json = #"{"meterStyle":"Bars","enabled":["claude","cursor","codex"],"pinned":["cursor","codex"],"showInitials":false,"alertsEnabled":true,"threshold":35,"resetReminders":{"claude:weekly":900000000,"cursor:monthly":900000000}}"#
    h.defaults.set(Data(json.utf8), forKey: "preferences")
    h.delivery.requests = [
        "reset:claude:weekly": LimitNotification(id: "reset:claude:weekly", title: "fixture", body: "fixture"),
        "reset:cursor:monthly": LimitNotification(id: "reset:cursor:monthly", title: "fixture", body: "fixture")
    ]
    _ = h.model(preview: true)
    #expect(h.defaults.data(forKey: "preferences") == Data(json.utf8))
    #expect(h.delivery.requests.count == 2, "Preview must not perform a real settings migration")
    let model = h.model(preview: beginInPreview)
    if beginInPreview { model.setPreview(false) }
    #expect(model.preferences.enabled == [.claude, .codex])
    #expect(model.preferences.visiblePins == [.codex])
    #expect(!model.preferences.showInitials)
    #expect(model.preferences.alertsEnabled && model.preferences.threshold == 35)
    #expect(h.delivery.requests["reset:cursor:monthly"] == nil)
    #expect(h.delivery.requests["reset:claude:weekly"] != nil)
    let stored = try #require(h.defaults.data(forKey: "preferences"))
    #expect(!String(decoding: stored, as: UTF8.self).contains("cursor"))
    #expect(h.model().preferences == model.preferences)
}

@Test @MainActor func emptyClaudeCacheDoesNotClaimAFreshUsageReading() async throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    model.change { $0.enabled = [.claude] }
    model.claudeInstalled = true
    let empty = UsageSnapshot(provider: .claude, windows: [], observedAt: epoch, source: "Claude Code local feed")
    try LocalStorage.write(empty, to: h.directory.appendingPathComponent("claude-usage.json"))
    await model.refresh(force: true)
    #expect(model.states[.claude]?.snapshot == nil)
    #expect(model.states[.claude]?.error != nil, "An installed bridge with no quota data must explain the missing reading")
}

@Test @MainActor func claudeTeamReadsTheNativeLocalSourceWithoutARelayFile() async throws {
    let h = try Harness(); defer { h.clean() }
    let reading = UsageSnapshot(provider: .claude, windows: snapshot().windows, observedAt: epoch.addingTimeInterval(-7200), source: "Claude Code")
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery,
        clock: { epoch }, readClaudeAccount: { .team }, readClaude: { _ in reading })
    model.change { $0.enabled = [.claude] }
    model.claudeInstalled = true
    await model.refresh(force: true)
    #expect(model.states[.claude]?.snapshot == reading)
    #expect(model.states[.claude]?.snapshot?.isStale(at: epoch) == true)
    #expect(model.states[.claude]?.error == nil)
}

@Test @MainActor func claudeTeamExplainsMissingDataButAcceptsAnyActualReportedQuotas() async throws {
    let h = try Harness(); defer { h.clean() }
    let feed = Feed(); await feed.fail()
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery,
        clock: { h.date }, readClaudeAccount: { .team }, readClaude: { _ in
            do { return try await feed.read() } catch { throw ProviderFailure.noObservation }
        })
    model.change { $0.enabled = [.claude] }
    model.claudeInstalled = true
    await model.refresh(force: true)
    #expect(model.states[.claude]?.error?.contains("Team") == true)
    let reading = UsageSnapshot(provider: .claude, windows: snapshot().windows, observedAt: epoch, source: "fixture")
    await feed.set(reading)
    h.date = epoch.addingTimeInterval(3)
    await model.refresh(force: true)
    #expect(model.states[.claude]?.snapshot == reading)
    #expect(model.states[.claude]?.error == nil)
}

@Test @MainActor func previewNeverWritesSettingsReadsProvidersOrSendsNotifications() async throws {
    let h = try Harness(); defer { h.clean() }
    let saved = h.defaults.data(forKey: "preferences")
    let model = h.model(preview: true)
    model.change { $0.pinned = [] }
    let window = try #require(model.states[.claude]?.snapshot?.windows.first)
    await model.toggleReminder(.claude, window)
    await model.setAlerts(true)
    await model.refresh(force: true)
    #expect(h.defaults.data(forKey: "preferences") == saved)
    #expect(h.delivery.authorizations == 0)
    #expect(h.delivery.history.isEmpty)
    #expect(await h.feed.reads == 0)
    #expect(!FileManager.default.fileExists(atPath: h.directory.path))
}

@Test @MainActor func refreshRetainsOldObservationBacksOffAndRecovers() async throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    await model.refresh()
    #expect(model.states[.codex]?.snapshot?.windows.first?.remainingPercent == 18)
    await model.refresh(force: true)
    #expect(await h.feed.reads == 1) // Burst refreshes are coalesced.
    h.date = epoch.addingTimeInterval(3)
    await h.feed.fail()
    await model.refresh(force: true)
    #expect(model.states[.codex]?.snapshot?.observedAt == epoch)
    #expect(model.states[.codex]?.error != nil)
    h.date = epoch.addingTimeInterval(400)
    await model.refresh()
    #expect(await h.feed.reads == 2)
    h.date = epoch.addingTimeInterval(604)
    await h.feed.set(snapshot(remaining: 75, observed: h.date))
    await model.refresh()
    #expect(model.states[.codex]?.snapshot?.windows.first?.remainingPercent == 75)
    #expect(model.states[.codex]?.error == nil)
    #expect(!((model.states[.codex]?.refreshing) ?? true))
    #expect(h.model().states[.codex]?.snapshot == nil, "Account-unbound readings must not survive relaunch")
}

@Test @MainActor func deniedNotificationsDoNotEnableAlertsOrReminders() async throws {
    let h = try Harness(); defer { h.clean() }; h.delivery.allowed = false
    let model = h.model()
    await model.setAlerts(true)
    await model.toggleReminder(.codex, snapshot().windows[0])
    #expect(!model.preferences.alertsEnabled)
    #expect(model.preferences.resetReminders.isEmpty)
    #expect(model.notice?.contains("System Settings") == true)
    #expect(h.delivery.history.isEmpty)
}

@Test @MainActor func resetReminderFollowsCorrectedTimeAndDisablingCancelsIt() async throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    let first = snapshot().windows[0]
    await model.toggleReminder(.codex, first)
    #expect(model.reminderEnabled(.codex, first))
    let changed = snapshot(reset: epoch.addingTimeInterval(7200))
    await h.feed.set(changed)
    await model.refresh()
    #expect(h.delivery.requests["reset:codex:weekly"]?.date == changed.windows[0].resetsAt)
    #expect(model.reminderEnabled(.codex, changed.windows[0]))
    model.change { $0.enabled = [] }
    #expect(h.delivery.requests.isEmpty)
    #expect(model.preferences.resetReminders.isEmpty)
}

@Test @MainActor func remindersAreOneShotAndAlertsDeduplicateAcrossRelaunches() async throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    await model.refresh()
    await model.setAlerts(true)
    #expect(h.delivery.history.filter { $0.id.hasPrefix("low:") }.count == 1)
    let relaunched = h.model()
    await relaunched.refresh()
    #expect(h.delivery.history.filter { $0.id.hasPrefix("low:") }.count == 1)
    await model.toggleReminder(.codex, snapshot().windows[0])
    h.date = epoch.addingTimeInterval(3601)
    await h.feed.set(snapshot(reset: epoch.addingTimeInterval(7200), observed: h.date))
    await model.refresh(force: true)
    #expect(model.preferences.resetReminders.isEmpty)
    #expect(h.delivery.requests["reset:codex:weekly"] == nil)
}

@Test @MainActor func disabledProvidersAreNotPolledAndSettingsOpens() async throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    model.change { $0.enabled = [] }
    await model.refresh(force: true)
    #expect(await h.feed.reads == 0)
    var opened = false
    model.onSettings = { opened = true }
    model.showSettings()
    #expect(opened)
}

@Test @MainActor func scheduledResetTriggersAnEarlyReadWithoutInventingARefill() async throws {
    let h = try Harness(); defer { h.clean() }
    await h.feed.set(snapshot(reset: epoch.addingTimeInterval(60)))
    let model = h.model()
    await model.refresh()
    h.date = epoch.addingTimeInterval(61)
    await h.feed.fail()
    await model.refresh()
    #expect(await h.feed.reads == 2)
    #expect(model.states[.codex]?.snapshot?.windows[0].remainingPercent == 18)
    #expect(model.states[.codex]?.error != nil)
}

@Test @MainActor func disconnectedClaudeDoesNotReloadItsOldFeed() async throws {
    let h = try Harness(); defer { h.clean() }
    let old = UsageSnapshot(provider: .claude, windows: snapshot().windows, observedAt: epoch, source: "Test")
    try LocalStorage.write(old, to: h.directory.appendingPathComponent("claude-usage.json"))
    let model = h.model()
    model.change { $0.enabled = [.claude] }
    model.disconnectClaude()
    await model.refresh()
    #expect(model.states[.claude] == nil)
}

private actor DeferredFeed {
    let started = AsyncStream<Void>.makeStream()
    var continuation: CheckedContinuation<UsageSnapshot, Never>?
    func read() async -> UsageSnapshot {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(())
        }
    }
    func finish() { continuation?.resume(returning: snapshot(remaining: 5)); continuation = nil }
}

private actor ClaudeFeed {
    var nativeReads = 0
    var cacheReads = 0
    var failure: (any Error)?
    var value = UsageSnapshot(provider: .claude, windows: snapshot().windows, observedAt: epoch, source: "Claude Code")
    func read(refresh: Bool) throws -> UsageSnapshot {
        if refresh { nativeReads += 1 } else { cacheReads += 1 }
        if let failure, refresh || failure is ClaudeFailure { throw failure }
        return value
    }
    func fail(_ failure: (any Error)?) { self.failure = failure }
}

@Test @MainActor func claudeRefreshPreservesOldReadingsBacksOffAndClearsChangedAccounts() async throws {
    let h = try Harness(); defer { h.clean() }
    let feed = ClaudeFeed()
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery,
        clock: { h.date }, readClaude: { try await feed.read(refresh: $0) })
    model.change { $0.enabled = [.claude] }; model.claudeInstalled = true
    await model.refresh()
    #expect(await feed.nativeReads == 1)
    let original = model.states[.claude]?.snapshot
    h.date = epoch.addingTimeInterval(30)
    await model.refresh()
    #expect(await feed.cacheReads == 2)
    #expect(await feed.nativeReads == 1)
    await feed.fail(ProviderFailure.unavailable)
    h.date = epoch.addingTimeInterval(300)
    await model.refresh()
    #expect(model.states[.claude]?.snapshot == original)
    #expect(model.states[.claude]?.error != nil)
    h.date = epoch.addingTimeInterval(600)
    await model.refresh()
    #expect(await feed.nativeReads == 2)
    #expect(model.states[.claude]?.error != nil)
    await feed.fail(ClaudeFailure.accountChanged)
    h.date = epoch.addingTimeInterval(900)
    await model.refresh()
    #expect(model.states[.claude]?.snapshot == nil)
    #expect(model.states[.claude]?.error != nil)
    await feed.fail(nil)
    h.date = epoch.addingTimeInterval(903)
    await model.refresh(force: true)
    #expect(model.states[.claude]?.snapshot == original)
    #expect(model.states[.claude]?.error == nil)
    model.disconnectClaude()
    let reads = await feed.cacheReads
    await model.refresh(force: true)
    #expect(await feed.cacheReads == reads)
    #expect(model.states[.claude] == nil)
    #expect(!h.model().claudeInstalled)
}

@Test @MainActor func disconnectDuringClaudeRefreshCannotRestoreUsage() async throws {
    let h = try Harness(); defer { h.clean() }
    let feed = DeferredFeed()
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery,
        clock: { h.date }, readClaude: { refresh in
            if refresh { return await feed.read() }
            throw ProviderFailure.noObservation
        })
    model.change { $0.enabled = [.claude] }; model.claudeInstalled = true
    let refresh = Task { await model.refresh() }
    var started = feed.started.stream.makeAsyncIterator()
    await started.next()
    model.disconnectClaude()
    await feed.finish()
    await refresh.value
    #expect(model.states[.claude] == nil)
    #expect(!model.claudeInstalled)
}

@Test @MainActor func delayedLiveResponseCannotReplacePreviewValues() async throws {
    let h = try Harness(); defer { h.clean() }
    let feed = DeferredFeed()
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery, clock: { h.date }, readCodex: { await feed.read() })
    let refresh = Task { await model.refresh() }
    var started = feed.started.stream.makeAsyncIterator()
    await started.next()
    model.setPreview(true)
    await feed.finish()
    await refresh.value
    #expect(model.preview)
    #expect(model.states[.codex]?.snapshot?.windows[0].remainingPercent == 64)
    #expect(!FileManager.default.fileExists(atPath: h.directory.appendingPathComponent("codex-usage.json").path))
    #expect(h.delivery.history.isEmpty)
}

@Test @MainActor func disconnectingClaudeCancelsItsResetRemindersOnly() throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    model.change {
        $0.enabled = [.claude, .codex]
        $0.resetReminders = ["claude:weekly": epoch.addingTimeInterval(3600), "codex:weekly": epoch.addingTimeInterval(3600)]
    }
    h.delivery.requests = [
        "reset:claude:weekly": LimitNotification(id: "reset:claude:weekly", title: "fixture", body: "fixture"),
        "reset:codex:weekly": LimitNotification(id: "reset:codex:weekly", title: "fixture", body: "fixture")]
    model.disconnectClaude()
    #expect(model.preferences.resetReminders["claude:weekly"] == nil)
    #expect(h.delivery.requests["reset:claude:weekly"] == nil)
    #expect(h.delivery.requests["reset:codex:weekly"] != nil)
    #expect(h.model().preferences.resetReminders["claude:weekly"] == nil)
}

@Test @MainActor func claudeReadsExistingUsageWithoutAConnectStep() async throws {
    let h = try Harness(); defer { h.clean() }
    h.defaults.removeObject(forKey: "preferences")
    let expected = UsageSnapshot(provider: .claude, windows: [], observedAt: epoch, source: "Fixture")
    let model = AppModel(defaults: h.defaults, storageDirectory: h.directory, notifications: h.delivery,
        clock: { epoch }, readCodex: { snapshot() }, readClaude: { _ in expected })
    await model.refresh()
    #expect(model.states[.claude]?.snapshot == expected)
}

@Test @MainActor func anExplicitClaudeDisconnectMigratesToTheSubscriptionToggle() throws {
    let h = try Harness(); defer { h.clean() }
    h.defaults.removeObject(forKey: "preferences")
    h.defaults.set(false, forKey: "claudeConnected")
    let model = h.model()
    #expect(!model.preferences.enabled.contains(.claude))
    model.change { $0.enabled.append(.claude) }
    #expect(model.claudeInstalled)
    #expect(h.model().preferences.enabled.contains(.claude))
    #expect(h.model().claudeInstalled)
}

@Test @MainActor func enablingClaudeClearsTheObsoleteDisconnectedNotice() throws {
    let h = try Harness(); defer { h.clean() }
    let model = h.model()
    model.change { $0.enabled = [.claude] }
    model.disconnectClaude()
    #expect(model.notice != nil)
    model.change { $0.enabled.append(.claude) }
    #expect(model.notice == nil)
}
