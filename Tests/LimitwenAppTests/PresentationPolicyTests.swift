import AppKit
import Testing
import LimitwenCore
@testable import Limitwen

@Test @MainActor func knownResetStillHasACountdownWhenPercentageIsUnknown() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let model = AppModel(preview: true, clock: { date })
    let quota = QuotaWindow(id: "weekly", title: "Weekly", durationMinutes: 10080, usedPercent: nil, resetsAt: date.addingTimeInterval(3600))
    let row = QuotaRow(model: model, provider: .codex, window: quota, stale: false)
    #expect(row.resetText == "Resets in 1h")
    #expect(row.exactReset(date) == date.formatted(.dateTime.hour().minute()))
}

@Test @MainActor func unchangedMeterReusesItsImageUntilAVisualInputChanges() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let quota = QuotaWindow(id: "weekly", title: "Weekly", durationMinutes: 10080, usedPercent: 30, resetsAt: date.addingTimeInterval(3600))
    let first = MenuMeter.image(windows: [quota], stale: false, now: date, threshold: 20)
    let next = MenuMeter.image(windows: [quota], stale: false, now: date.addingTimeInterval(30), threshold: 20)
    #expect(first === next)
    let elapsed = MenuMeter.image(windows: [quota], stale: false, now: date.addingTimeInterval(3600), threshold: 20)
    #expect(first !== elapsed)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LIMITWEN_PERFORMANCE_TESTS"] == "1"))
@MainActor func repeatedMeterRenderingBenchmark() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let quota = QuotaWindow(id: "weekly", title: "Weekly", durationMinutes: 10080, usedPercent: 30, resetsAt: date.addingTimeInterval(3600))
    let start = ContinuousClock.now
    for _ in 0..<1000 { _ = MenuMeter.image(windows: [quota], stale: false, now: date, threshold: 20) }
    print("BENCHMARK 1000 unchanged menu renders: \(start.duration(to: .now))")
}
