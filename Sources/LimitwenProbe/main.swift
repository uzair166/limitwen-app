import Foundation
import LimitwenCore

do {
    let claude = CommandLine.arguments.contains("--claude")
    let snapshot = try await (claude ? ClaudeClient().read(refresh: !CommandLine.arguments.contains("--cache-only")) : CodexClient().read())
    print("\(snapshot.provider.name) connection verified via \(snapshot.source)")
    print("Observed: \(snapshot.observedAt.ISO8601Format()) · stale: \(snapshot.isStale(at: Date()))")
    for window in snapshot.displayWindows {
        print("\(window.title): \(window.remainingPercent.map { String(format: "%.0f%% remaining", $0) } ?? "not reported")")
        if let reset = window.resetsAt { print("  Resets: \(reset.ISO8601Format())") }
    }
} catch {
    print("Connection failed: \(error.localizedDescription)")
    exit(1)
}
