import Foundation
import Darwin

/// A bounded subprocess transport, used only from provider worker tasks. Owns
/// pipe ends and termination so a failed CLI cannot strand a refresh or SIGPIPE
/// the menu-bar app. Provider protocols stay in their respective adapters.
final class ProcessPipe {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private let deadline: ContinuousClock.Instant
    private var received = 0
    private let maximumBytes: Int

    init(executable: URL, arguments: [String], directory: URL? = nil,
         deadline: ContinuousClock.Instant, maximumBytes: Int = 2_097_152) throws {
        self.deadline = deadline; self.maximumBytes = maximumBytes
        try Task.checkCancellation()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw ProviderFailure.unavailable }
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0,
              fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else { throw ProviderFailure.unavailable }
    }

    deinit {
        try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close()
        if process.isRunning { process.terminate() }
        let grace = ContinuousClock.now.advanced(by: .milliseconds(200))
        while process.isRunning && ContinuousClock.now < grace { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        if process.processIdentifier > 0 { process.waitUntilExit() }
    }

    private func checkDeadline() throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ProviderFailure.timedOut }
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                try checkDeadline()
                let fd = input.fileHandleForWriting.fileDescriptor
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&descriptor, 1, 50)
                if ready < 0 && errno == EINTR { continue }
                guard ready >= 0 else { throw ProviderFailure.unavailable }
                if ready == 0 { continue }
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard count > 0 else { throw ProviderFailure.unavailable }
                offset += count
            }
        }
    }

    func closeInput() { try? input.fileHandleForWriting.close() }

    func nextChunk() throws -> Data? {
        let fd = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            try checkDeadline()
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw ProviderFailure.unavailable }
            if ready == 0 { continue }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard count >= 0 else { throw ProviderFailure.unavailable }
            if count == 0 { return nil }
            received += count
            guard received <= maximumBytes else { throw ProviderFailure.invalidResponse }
            return Data(bytes.prefix(count))
        }
    }

    func completedOutput() throws -> Data {
        closeInput()
        var data = Data()
        while let chunk = try nextChunk() { data.append(chunk) }
        while process.isRunning { try checkDeadline(); usleep(10_000) }
        guard process.terminationStatus == 0 else { throw ProviderFailure.unavailable }
        return data
    }
}
