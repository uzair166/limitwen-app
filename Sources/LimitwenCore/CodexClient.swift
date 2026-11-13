import Foundation
import Darwin

public struct CodexClient: Sendable {
    public var executable: URL?
    public var timeout: TimeInterval
    public init(executable: URL? = nil, timeout: TimeInterval = 20) { self.executable = executable; self.timeout = timeout }

    public func read() async throws -> UsageSnapshot {
        let executable = executable ?? Self.findExecutable()
        guard let executable else { throw ProviderFailure.notInstalled }
        let timeout = timeout
        let worker = Task.detached(priority: .utility) { try Self.readBlocking(executable: executable, timeout: timeout) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    public static func findExecutable() -> URL? {
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path]
        return paths.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func readBlocking(executable: URL, timeout: TimeInterval) throws -> UsageSnapshot {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout.isFinite ? max(0.05, min(60, timeout)) : 20))
        let pipe = try ProcessPipe(executable: executable,
            arguments: ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"], deadline: deadline)
        try pipe.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "limitwen", "title": "Limitwen", "version": "0.1.0"]]])
        var buffer = Data()
        var initialized = false
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard let chunk = try pipe.nextChunk() else { throw ProviderFailure.unavailable }
            buffer.append(chunk)
            guard buffer.count < 1_048_576 else { throw ProviderFailure.invalidResponse }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int else { continue }
                guard id == 1 || id == 2 else { continue }
                if let error = object["error"] as? [String: Any] {
                    let message = (error["message"] as? String ?? "").lowercased()
                    if ["unauthorized", "not authenticated", "not logged", "401", "sign in"].contains(where: message.contains) {
                        throw ProviderFailure.authentication
                    }
                    throw ProviderFailure.unavailable
                }
                if id == 1 && !initialized {
                    guard object["result"] != nil else { throw ProviderFailure.invalidResponse }
                    initialized = true
                    try pipe.send(["method": "initialized", "params": [:]])
                    try pipe.send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, initialized, let result = object["result"] {
                    return try UsageParser.codex(JSONSerialization.data(withJSONObject: result), observedAt: Date())
                }
            }
        }
        throw ProviderFailure.timedOut
    }
}
