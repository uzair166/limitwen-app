import Foundation
import Testing
@testable import LimitwenCore

private let cacheTime = Date(timeIntervalSince1970: 1_800_000_000)
private func cache(_ utilization: String, account: String = "fixture-account", fetched: Double = 1_800_000_000_000) -> Data {
    Data("""
    {"oauthAccount":{"accountUuid":"fixture-account","subscriptionType":"team"},
     "cachedUsageUtilization":{"accountUuid":"\(account)","fetchedAtMs":\(fetched),"utilization":\(utilization)},
     "unrelatedPrivateData":"must not be retained"}
    """.utf8)
}

@Test func claudeTeamCacheReportsRealWindowsWithoutAStatusLine() throws {
    let data = cache(#"{"five_hour":{"utilization":42,"resets_at":"2027-01-15T09:00:00.123456+00:00"},"seven_day":{"utilization":9,"resets_at":"2027-01-22T01:00:00+00:00"}}"#)
    let reading = try UsageParser.claudeCache(data, now: cacheTime)
    #expect(reading.provider == .claude)
    #expect(reading.windows.map(\.id) == ["five-hour", "weekly"])
    #expect(reading.windows.map(\.remainingPercent) == [58, 91])
    #expect(reading.windows.allSatisfy { $0.resetsAt != nil })
    #expect(reading.observedAt == cacheTime)
    let saved = String(decoding: try JSONEncoder().encode(reading), as: UTF8.self)
    #expect(!saved.contains("fixture-account") && !saved.contains("unrelatedPrivateData"))
}

@Test func claudeCachePreservesAgeAndDoesNotInventAbsentWindows() throws {
    let reading = try UsageParser.claudeCache(cache(#"{"seven_day":{"utilization":0,"resets_at":null}}"#), now: cacheTime.addingTimeInterval(7200))
    #expect(reading.windows.count == 1)
    #expect(reading.windows[0].remainingPercent == 100)
    #expect(reading.windows[0].resetsAt == nil)
    #expect(reading.observedAt == cacheTime)
    #expect(reading.isStale(at: cacheTime.addingTimeInterval(7200)))
}

@Test func claudeStructuredLimitsTakePrecedenceAndKeepScopedWindowsDistinct() throws {
    let reading = try UsageParser.claudeCache(cache(#"{"five_hour":{"utilization":99,"resets_at":null},"limits":[{"kind":"weekly_all","group":"weekly","percent":9,"resets_at":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":12,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}]}"#), now: cacheTime)
    #expect(reading.windows.map(\.remainingPercent) == [91, 88])
    #expect(reading.windows[0].id == "weekly")
    #expect(reading.windows[1].title == "Fable · weekly")
    #expect(Set(reading.windows.map(\.id)).count == 2)
}

@Test func claudeCacheRejectsWrongAccountsMissingIdentityEmptyAndFutureObservations() {
    let valid = #"{"seven_day":{"utilization":9,"resets_at":null}}"#
    for data in [cache(valid, account: "another-account"), cache("{}"), cache(valid, fetched: 0),
                 cache(valid, fetched: 1_800_000_061_000), Data(#"{"cachedUsageUtilization":{}}"#.utf8),
                 cache(#"{"limits":[],"five_hour":{"utilization":99,"resets_at":null}}"#)] {
        #expect(throws: (any Error).self) { try UsageParser.claudeCache(data, now: cacheTime) }
    }
}
