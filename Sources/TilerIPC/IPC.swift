import Foundation
import Darwin
import TilerCore

public enum RuntimePaths {
    public static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/McTiler", isDirectory: true) }
    // UNIX paths have a 104-byte limit. A private per-user directory keeps this short.
    public static var socketDirectory: String { "/tmp/mctiler-\(getuid())" }
    public static var socket: String { socketDirectory + "/control.sock" }
    public static func prepareSocketDirectory(_ directory: String = socketDirectory) throws {
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw POSIXFailure("mkdir") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw TilerError.message("Unsafe runtime directory: \(directory)") }
    }
}

public struct POSIXFailure: Error, LocalizedError {
    let message: String
    public init(_ operation: String) { message = "\(operation): \(String(cString: strerror(errno)))" }
    public var errorDescription: String? { message }
}

public final class InstanceLock {
    private var fd: Int32 = -1
    public init(directory: String = RuntimePaths.socketDirectory) throws {
        try RuntimePaths.prepareSocketDirectory(directory)
        fd = open(directory + "/instance.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXFailure("open lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); fd = -1
            throw TilerError.message("McTiler is already running (or recovery is in progress)")
        }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}

public struct Request: Codable { public var arguments: [String]; public init(_ arguments: [String]) { self.arguments = arguments } }
public struct Response: Codable {
    public var ok: Bool
    public var message: String
    public init(ok: Bool = true, message: String) { self.ok = ok; self.message = message }
}

private func address(_ path: String) throws -> sockaddr_un {
    var value = sockaddr_un()
    value.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else { throw TilerError.message("Socket path too long") }
    value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &value.sun_path) { $0.copyBytes(from: bytes + Array(repeating: UInt8(0), count: $0.count-bytes.count)) }
    return value
}

private func configure(_ fd: Int32) {
    var timeout = timeval(tv_sec: 5, tv_usec: 0), yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
}
private func receiveLine(_ fd: Int32) throws -> Data {
    var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while result.count <= 65_536 {
        let count = read(fd, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw TilerError.message("Connection closed or timed out") }
        if let end = buffer[..<count].firstIndex(of: 10) {
            guard result.count + end <= 65_536 else { throw TilerError.message("IPC message exceeds 64 KiB") }
            result.append(contentsOf: buffer[..<end]); return result
        }
        result.append(contentsOf: buffer[..<count])
    }
    throw TilerError.message("IPC message exceeds 64 KiB")
}
private func sendLine<T: Encodable>(_ value: T, fd: Int32) throws {
    var data = try JSONEncoder().encode(value); data.append(10)
    try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count-offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw POSIXFailure("write socket") }; offset += count
        }
    }
}

public enum Client {
    public static func send(_ arguments: [String], directory: String = RuntimePaths.socketDirectory) throws -> Response {
        try RuntimePaths.prepareSocketDirectory(directory)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXFailure("socket") }; defer { close(fd) }
        configure(fd)
        var addr = try address(directory + "/control.sock")
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw TilerError.message("Cannot connect to McTiler. Launch McTiler.app first. Use 'recover --standalone' only when it is stopped.") }
        try sendLine(Request(arguments), fd: fd)
        return try JSONDecoder().decode(Response.self, from: receiveLine(fd))
    }
}

public final class Server {
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "mctiler.ipc")
    private let directory: String
    private var path: String { directory + "/control.sock" }
    public init(directory: String = RuntimePaths.socketDirectory) { self.directory = directory }
    public func start(handler: @escaping ([String]) -> Response) throws {
        try RuntimePaths.prepareSocketDirectory(directory)
        unlink(path) // caller must hold InstanceLock
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXFailure("socket") }
        configure(fd)
        var addr = try address(path)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { throw POSIXFailure("listen") }
        let listener = fd
        queue.async {
            while true {
                let connection = accept(listener, nil, nil)
                if connection < 0 { if errno == EINTR { continue }; break }
                configure(connection)
                var user: uid_t = 0, group: gid_t = 0
                guard getpeereid(connection, &user, &group) == 0, user == getuid() else { close(connection); continue }
                do {
                    let request = try JSONDecoder().decode(Request.self, from: receiveLine(connection))
                    try sendLine(handler(request.arguments), fd: connection)
                } catch { try? sendLine(Response(ok: false, message: error.localizedDescription), fd: connection) }
                close(connection)
            }
        }
    }
    deinit { if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); unlink(path) } }
}
