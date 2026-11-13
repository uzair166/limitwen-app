import AppKit
import Testing
import LimitwenCore
@testable import Limitwen

@Suite @MainActor
struct MenuMeterTests {
    @Test
    func weeklyOnlyDrawsOneMeter() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func bitmap(_ duration: Int) throws -> NSBitmapImageRep {
            let quota = QuotaWindow(id: "quota", title: "Quota", durationMinutes: duration, usedPercent: 30, resetsAt: now.addingTimeInterval(3600))
            let image = MenuMeter.image(windows: [quota], stale: false, now: now, threshold: 20)
            let data = try #require(image.tiffRepresentation)
            return try #require(NSBitmapImageRep(data: data))
        }
        // A single weekly allowance must have exactly the same one-meter geometry
        // as a single short allowance, without a synthetic second window.
        let weekly = try bitmap(10080), short = try bitmap(300)
        #expect(weekly.pixelsWide == short.pixelsWide && weekly.pixelsHigh == short.pixelsHigh)
        var mismatches = 0
        for x in 0..<weekly.pixelsWide {
            for y in 0..<weekly.pixelsHigh {
                if weekly.colorAt(x: x, y: y) != short.colorAt(x: x, y: y) { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "A weekly-only account must not gain an inner ring ")
    }
}
