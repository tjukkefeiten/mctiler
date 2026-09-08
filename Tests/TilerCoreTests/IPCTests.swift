import Testing
import Foundation
import Darwin
import TilerIPC

final class IPCTests {
    @Test func testRoundTripAndSingleInstanceLock() throws {
        let directory = "/tmp/mctiler-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let lock = try InstanceLock(directory: directory)
        let server = Server(directory: directory)
        try server.start { arguments in Response(message: arguments.joined(separator: ":")) }
        let response = try Client.send(["workspace", "2"], directory: directory)
        #expect(response.ok)
        #expect(response.message == "workspace:2")
        #expect(throws: (any Error).self) { _ = try InstanceLock(directory: directory) }
        var info = stat()
        #expect(lstat(directory + "/control.sock", &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
        withExtendedLifetime((lock, server)) {}
    }
    @Test func testRejectsSharedRuntimeDirectory() throws {
        let directory = "/tmp/mctiler-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
        chmod(directory, 0o755)
        #expect(throws: (any Error).self) { try RuntimePaths.prepareSocketDirectory(directory) }
    }
}
