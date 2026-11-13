import Foundation
import Testing
import LimitwenCore
@testable import Limitwen

private let instant = Date(timeIntervalSince1970: 1_800_000_000)
private let quota = QuotaWindow(id: "weekly", title: "Weekly window", durationMinutes: 10080, usedPercent: 90, resetsAt: instant.addingTimeInterval(3600))
private func reading(_ provider: ProviderID = .codex) -> UsageSnapshot {
    UsageSnapshot(provider: provider, windows: [quota], observedAt: instant, source: "fixture")
}

@MainActor private final class SuspendedDelivery: NotificationDelivery {
    let started = AsyncStream<Void>.makeStream()
    var continuation: CheckedContinuation<Void, Never>?
    var atAuthorization = true
    var failScheduling = false
    var requests: Set<String> = []
    var scheduledDates: [String: Date] = [:]
    func suspend() async { await withCheckedContinuation { continuation = $0; started.continuation.yield(()) } }
    func resume() { continuation?.resume(); continuation = nil }
    func authorize() async throws -> Bool { if atAuthorization { await suspend() }; return true }
    func schedule(_ notification: LimitNotification) async throws {
        if !atAuthorization { await suspend() }
        if failScheduling { throw ProviderFailure.unavailable }
        requests.insert(notification.id)
        scheduledDates[notification.id] = notification.date
    }
    func cancel(_ identifiers: [String]) { requests.subtract(identifiers) }
}

@MainActor private struct Context {
    let suite = "Lifecycle." + UUID().uuidString
    let defaults: UserDefaults
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() { defaults = UserDefaults(suiteName: suite)! }
    func model(delivery: any NotificationDelivery = SuspendedDelivery(), codex: @escaping @Sendable () async throws -> UsageSnapshot = { reading() }, claude: @escaping @Sendable (Bool) async throws -> UsageSnapshot = { _ in reading(.claude) }) -> AppModel {
        AppModel(defaults: defaults, storageDirectory: directory, notifications: delivery, clock: { instant }, readCodex: codex, readClaude: claude)
    }
    func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
}

@Test(arguments: [true, false], ["disconnect", "disable-reenable", "preview"])
@MainActor func lateReminderCannotUndoConnectionChanges(atAuthorization: Bool, action: String) async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); delivery.atAuthorization = atAuthorization
    let model = context.model(delivery: delivery); model.claudeInstalled = true
    let task = Task { await model.toggleReminder(.claude, quota) }
    var events = delivery.started.stream.makeAsyncIterator(); await events.next()
    switch action {
    case "disconnect": model.disconnectClaude()
    case "disable-reenable": model.change { $0.enabled = [.codex] }; model.change { $0.enabled = [.claude, .codex] }
    default: model.setPreview(true)
    }
    delivery.resume(); await task.value
    #expect(delivery.requests.isEmpty)
    #expect(model.preferences.resetReminders["claude:weekly"] == nil)
}

@Test @MainActor func turningAlertsOffWinsOverPendingAuthorization() async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); let model = context.model(delivery: delivery)
    let enabling = Task { await model.setAlerts(true) }
    var events = delivery.started.stream.makeAsyncIterator(); await events.next()
    await model.setAlerts(false)
    delivery.resume(); await enabling.value
    #expect(!model.preferences.alertsEnabled)
}

private actor SuspendedSource {
    let started = AsyncStream<Void>.makeStream()
    var continuation: CheckedContinuation<UsageSnapshot, Never>?
    func read() async -> UsageSnapshot {
        await withCheckedContinuation { continuation = $0; started.continuation.yield(()) }
    }
    func resume() { continuation?.resume(returning: reading()); continuation = nil }
}

@Test(arguments: [false, true]) @MainActor
func cancelledCodexResultCannotReappearAfterStopOrReenable(stop: Bool) async {
    let context = Context(); defer { context.clean() }
    let source = SuspendedSource(); let model = context.model(codex: { await source.read() })
    let task = Task { await model.refresh() }
    var events = source.started.stream.makeAsyncIterator(); await events.next()
    if stop { model.stop() }
    else { model.change { $0.enabled = [] }; model.change { $0.enabled = [.codex] } }
    await source.resume(); await task.value
    #expect(model.states[.codex]?.snapshot == nil)
    #expect(model.states[.codex]?.refreshing != true)
}

@Test @MainActor func unboundCodexCacheIsNeverPresentedAtLaunch() throws {
    let context = Context(); defer { context.clean() }
    try LocalStorage.write(reading(), to: context.directory.appendingPathComponent("codex-usage.json"))
    #expect(context.model().states[.codex]?.snapshot == nil)
}

@Test @MainActor func codexAuthenticationFailureClearsPreviousAccountUsage() async {
    let context = Context(); defer { context.clean() }
    let model = context.model(codex: { throw ProviderFailure.authentication })
    model.states[.codex] = ProviderState(snapshot: reading())
    await model.refresh(force: true)
    #expect(model.states[.codex]?.snapshot == nil)
}

@Test(arguments: ["alerts-off", "disable-reenable", "preview"])
@MainActor func obsoleteLowAlertIsCancelledAfterDeliverySuspends(action: String) async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); delivery.atAuthorization = false
    let model = context.model(delivery: delivery)
    model.change { $0.enabled = [.codex]; $0.alertsEnabled = true }
    let task = Task { await model.refresh() }
    var events = delivery.started.stream.makeAsyncIterator(); await events.next()
    switch action {
    case "alerts-off": await model.setAlerts(false)
    case "disable-reenable": model.change { $0.enabled = [] }; model.change { $0.enabled = [.codex] }
    default: model.setPreview(true)
    }
    delivery.resume(); await task.value
    #expect(delivery.requests.isEmpty)
    #expect(context.defaults.data(forKey: "alertLedger") == nil)
}

@Test(arguments: ["disable-reenable", "preview", "preview-roundtrip", "cancel-all"])
@MainActor func obsoleteResetCorrectionCannotReviveAReminder(action: String) async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); delivery.atAuthorization = false
    let returningRead = SuspendedSource()
    actor Reads {
        var count = 0
        func next() -> Int { count += 1; return count }
    }
    let reads = Reads()
    let model = context.model(delivery: delivery, codex: {
        if await reads.next() > 1 { return await returningRead.read() }
        return reading()
    })
    model.change { $0.enabled = [.codex]; $0.resetReminders = ["codex:weekly": instant.addingTimeInterval(100)] }
    let task = Task { await model.refresh() }
    var events = delivery.started.stream.makeAsyncIterator(); await events.next()
    switch action {
    case "disable-reenable": model.change { $0.enabled = [] }; model.change { $0.enabled = [.codex] }
    case "cancel-all": model.cancelResetReminders()
    case "preview-roundtrip": model.setPreview(true); model.setPreview(false)
    default: model.setPreview(true)
    }
    if action == "preview-roundtrip" {
        var started = returningRead.started.stream.makeAsyncIterator(); await started.next()
    }
    delivery.atAuthorization = true // subsequent compensation must not suspend again
    delivery.resume(); await task.value
    if action.hasPrefix("preview") {
        #expect(delivery.requests == ["reset:codex:weekly"])
        #expect(delivery.scheduledDates["reset:codex:weekly"] == instant.addingTimeInterval(100))
    }
    else { #expect(delivery.requests.isEmpty) }
    if action == "preview-roundtrip" {
        #expect(model.preferences.resetReminders["codex:weekly"] == instant.addingTimeInterval(100))
    } else { #expect(model.preferences.resetReminders["codex:weekly"] == nil) }
    if action == "preview-roundtrip" {
        let completed = AsyncStream<Void>.makeStream()
        model.onMenuChange = { [weak model] in
            if model?.states[.codex]?.refreshing == false { completed.continuation.yield(()) }
        }
        await returningRead.resume()
        var finished = completed.stream.makeAsyncIterator(); await finished.next()
        model.stop()
    }
}

@Test @MainActor func cancellingAllRemindersAlsoCancelsPendingAuthorization() async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); let model = context.model(delivery: delivery)
    let task = Task { await model.toggleReminder(.codex, quota) }
    var events = delivery.started.stream.makeAsyncIterator(); await events.next()
    model.cancelResetReminders(); delivery.resume(); await task.value
    #expect(delivery.requests.isEmpty)
    #expect(model.preferences.resetReminders.isEmpty)
}

@Test @MainActor func slowClaudeDoesNotPreventANewCodexRefresh() async {
    let context = Context(); defer { context.clean() }
    let claude = SuspendedSource()
    actor Counter {
        var reads = 0
        func read() -> UsageSnapshot { reads += 1; return reading() }
    }
    let codex = Counter()
    var date = instant
    let model = AppModel(defaults: context.defaults, storageDirectory: context.directory,
        notifications: SuspendedDelivery(), clock: { date }, readCodex: { await codex.read() },
        readClaude: { _ in await claude.read() })
    model.claudeInstalled = true
    let codexCompleted = AsyncStream<Void>.makeStream()
    model.onMenuChange = { [weak model] in if model?.states[.codex]?.snapshot != nil { codexCompleted.continuation.yield(()) } }
    let initial = Task { await model.refresh() }
    var started = claude.started.stream.makeAsyncIterator(); await started.next()
    // A second refresh must finish independently while the first Claude read is suspended.
    var completed = codexCompleted.stream.makeAsyncIterator(); await completed.next()
    date = instant.addingTimeInterval(301)
    await model.refresh(force: true)
    #expect(await codex.reads == 2)
    model.disconnectClaude(); await claude.resume(); await initial.value
}

@Test @MainActor func cancellingRefreshReleasesProviderForTheNextRead() async {
    let context = Context(); defer { context.clean() }
    let source = SuspendedSource()
    actor Attempts {
        var count = 0
        var cancelled = false
        func begin() -> Int { count += 1; return count }
        func recordCancellation(_ value: Bool) { cancelled = value }
    }
    let attempts = Attempts()
    var date = instant
    let model = AppModel(defaults: context.defaults, storageDirectory: context.directory,
        notifications: SuspendedDelivery(), clock: { date }, readCodex: {
            if await attempts.begin() == 1 {
                let snapshot = await source.read()
                await attempts.recordCancellation(Task.isCancelled)
                return snapshot
            }
            return reading()
        })
    model.change { $0.enabled = [.codex] }
    let task = Task { await model.refresh() }
    var events = source.started.stream.makeAsyncIterator(); await events.next()
    task.cancel(); await source.resume(); await task.value
    #expect(await attempts.cancelled)
    #expect(model.states[.codex]?.refreshing != true)
    #expect(model.states[.codex]?.snapshot == nil)
    date = instant.addingTimeInterval(3)
    await model.refresh(force: true)
    #expect(await attempts.count == 2)
    #expect(model.states[.codex]?.snapshot != nil)
}


@Test @MainActor func previewRoundTripPreservesLastKnownLiveUsage() async {
    let context = Context(); defer { context.clean() }
    let source = SuspendedSource()
    let model = context.model(codex: { _ = await source.read(); throw ProviderFailure.unavailable })
    model.change { $0.enabled = [.codex] }
    let original = reading()
    model.states[.codex] = ProviderState(snapshot: original)
    model.setPreview(true); model.setPreview(false)
    #expect(model.states[.codex]?.snapshot == original)
    let completed = AsyncStream<Void>.makeStream()
    model.onMenuChange = { [weak model] in
        if model?.states[.codex]?.error != nil { completed.continuation.yield(()) }
    }
    var started = source.started.stream.makeAsyncIterator(); await started.next()
    await source.resume()
    var finished = completed.stream.makeAsyncIterator(); await finished.next()
    #expect(model.states[.codex]?.snapshot == original)
    #expect(model.states[.codex]?.refreshing == false)
}

@Test(arguments: ["disconnect", "preview"]) @MainActor
func obsoleteReminderFailureDoesNotOverwriteCurrentNotice(action: String) async {
    let context = Context(); defer { context.clean() }
    let delivery = SuspendedDelivery(); delivery.atAuthorization = false; delivery.failScheduling = true
    let model = context.model(delivery: delivery); model.claudeInstalled = true
    let task = Task { await model.toggleReminder(.claude, quota) }
    var started = delivery.started.stream.makeAsyncIterator(); await started.next()
    if action == "preview" { model.setPreview(true) } else { model.disconnectClaude() }
    let currentNotice = model.notice
    delivery.resume(); await task.value
    #expect(model.notice == currentNotice)
}
