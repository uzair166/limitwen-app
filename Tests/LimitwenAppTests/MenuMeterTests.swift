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
    @Test(arguments: [false, true])
    func fullAllowanceKeepsTheRingVisible(nested: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func coverage(remaining: Double) throws -> Double {
            var windows = [QuotaWindow(id: "short", title: "5-hour", durationMinutes: 300,
                                       usedPercent: 100 - remaining, resetsAt: nil)]
            if nested {
                windows.append(QuotaWindow(id: "weekly", title: "Weekly", durationMinutes: 10080,
                                           usedPercent: 29, resetsAt: now.addingTimeInterval(3600)))
            }
            let image = MenuMeter.image(windows: windows, stale: false, now: now, threshold: 20)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let radius = nested ? 5.2 : 9.0
            var alpha = 0.0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    let dx = (Double(x) + 0.5) * 24 / Double(bitmap.pixelsWide) - 12
                    let dy = (Double(y) + 0.5) * 22 / Double(bitmap.pixelsHigh) - 11
                    if abs(hypot(dx, dy) - radius) < 1.5 {
                        alpha += Double(try #require(bitmap.colorAt(x: x, y: y)).alphaComponent)
                    }
                }
            }
            return alpha
        }
        // A complete allowance must remain at least as visible as a nearly full
        // one, including a known percentage without a reported reset time.
        let full = try coverage(remaining: 100)
        let almostFull = try coverage(remaining: 99)
        #expect(full >= almostFull * 0.95)
    }

}
