import Testing
import Foundation
import MacAdapter
import TilerCore

final class RecoveryTests {
    @Test func testJournalSurvivesRestartAndRetainsOriginalFrame() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("recovery.json")
        let first = try RecoveryJournal(url: url)
        let original = Rect(10,20,400,300), parked = Rect(1999,999,400,300), visible = Rect(0,24,1000,700)
        let launch = Date()
        try first.record(id:"a",pid:123,launched:launch,title:"Terminal",current:original,target:parked)
        let restarted = try RecoveryJournal(url:url)
        #expect(restarted.entries["a"]?.target == parked)
        try restarted.record(id:"a",pid:123,launched:launch,title:"Terminal",current:parked,target:visible)
        let reread = try RecoveryJournal(url:url)
        #expect(reread.entries["a"]?.original == original)
        #expect(reread.entries["a"]?.previous == parked)
        try reread.remove(["a"])
        #expect(try RecoveryJournal(url:url).entries.isEmpty)
    }
    @Test func testCorruptJournalIsNotSilentlyOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url = folder.appendingPathComponent("recovery.json")
        try Data("broken".utf8).write(to:url)
        #expect(throws: (any Error).self) { _ = try RecoveryJournal(url:url) }
        #expect(try String(contentsOf:url,encoding:.utf8) == "broken")
    }
}
