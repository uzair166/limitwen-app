import Foundation
import LimitwenCore
import Darwin

// A status-line command may close stdin early; that must not kill the relay.
signal(SIGPIPE, SIG_IGN)

var input = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
let inputDeadline = ContinuousClock.now.advanced(by: .seconds(2))
_ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)
while true {
    guard ContinuousClock.now < inputDeadline else { exit(0) }
    var readable = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    let ready = poll(&readable, 1, 50)
    if ready < 0 && errno == EINTR { continue }
    guard ready >= 0 else { exit(0) }
    if ready == 0 { continue }
    let count = read(STDIN_FILENO, &buffer, buffer.count)
    if count == 0 { break }
    if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
    guard count > 0, input.count + count <= 1_048_576 else { exit(0) }
    input.append(contentsOf: buffer.prefix(count))
}
let arguments = CommandLine.arguments
let destination: URL
if let i = arguments.firstIndex(of: "--output"), arguments.indices.contains(i + 1) { destination = URL(fileURLWithPath: arguments[i + 1]) }
else { destination = LocalStorage.directory.appendingPathComponent("claude-usage.json") }

if let snapshot = try? UsageParser.claude(input, observedAt: Date()) {
    try? LocalStorage.write(snapshot, to: destination)
}

// Forward the original input only to the user's pre-existing local status-line command.
if let i = arguments.firstIndex(of: "--previous"), arguments.indices.contains(i + 1),
   let data = try? LocalStorage.readData(from: URL(fileURLWithPath: arguments[i + 1])),
   let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let original = backup["original"] as? [String: Any], let command = original["command"] as? String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardInput = pipe
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let descriptor = pipe.fileHandleForWriting.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        input.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count && process.isRunning && ContinuousClock.now < deadline {
                var writable = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                guard poll(&writable, 1, 50) >= 0 else { break }
                let count = write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if errno != EAGAIN && errno != EINTR { break }
            }
        }
        try pipe.fileHandleForWriting.close()
        while process.isRunning && ContinuousClock.now < deadline { usleep(10_000) }
        if process.isRunning { process.terminate() }
        let grace = ContinuousClock.now.advanced(by: .milliseconds(200))
        while process.isRunning && ContinuousClock.now < grace { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    } catch { /* Claude's status line must remain non-fatal. */ }
} else {
    print("Limitwen · usage connected")
}
