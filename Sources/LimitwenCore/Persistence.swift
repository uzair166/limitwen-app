import Foundation
import Darwin

public enum LocalStorage {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Limitwen", isDirectory: true)
    }

    /// Private from creation, atomically replaced within an opened directory. Never
    /// follow a destination symlink or change permissions on an existing parent.
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try writeData(JSONEncoder().encode(value), to: url)
    }

    static func writeData(_ data: Data, to url: URL, mode: mode_t = 0o600) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directoryFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw ProviderFailure.unavailable }
        defer { close(directoryFD) }
        let temporary = ".limitwen-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else { throw ProviderFailure.unavailable }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ProviderFailure.unavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(directoryFD, temporary, directoryFD, url.lastPathComponent) == 0 else { throw ProviderFailure.unavailable }
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: readData(from: url))
    }

    /// Bound the read itself, not just a metadata check that can race a writer.
    public static func readData(from url: URL, maximumBytes: Int = 1_048_576, allowSymbolicLink: Bool = false) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (allowSymbolicLink ? 0 : O_NOFOLLOW))
        guard fd >= 0 else { throw ProviderFailure.invalidResponse }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= maximumBytes else { throw ProviderFailure.invalidResponse }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count <= maximumBytes {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximumBytes + 1 - data.count))
            if count == 0 { return data }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ProviderFailure.invalidResponse }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw ProviderFailure.invalidResponse
    }
}
