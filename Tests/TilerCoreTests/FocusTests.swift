import Testing
@testable import TilerCore

final class FocusTests {
    @Test func testWaitsForConfirmedKeyboardFocusAndThenStops() {
        let adapter = FakeAdapter(); adapter.focusResults = [false, true]
        var pending: [() -> Void] = [], result: Bool?, raised = 0
        let focus = FocusCoordinator(adapter: adapter) { _, work in pending.append(work) }
        focus.request("window", isCurrent: { true }, afterAttempt: { raised += 1 }, completion: { result = $0 })
        #expect(result == nil)
        pending.removeFirst()()
        #expect(result == true)
        #expect(adapter.focusAttempts == ["window", "window"])
        #expect(raised == 2)
        #expect(pending.isEmpty)
    }
    @Test func testRetriesAreBoundedAndFailuresReported() {
        let adapter = FakeAdapter(); adapter.focusResults = [false, false, false, false]
        var pending: [() -> Void] = [], result: Bool?
        let focus = FocusCoordinator(adapter: adapter) { _, work in pending.append(work) }
        focus.request("window", isCurrent: { true }, afterAttempt: {}, completion: { result = $0 })
        while !pending.isEmpty { pending.removeFirst()() }
        #expect(adapter.focusAttempts.count == 3)
        #expect(result == false)
    }
    @Test func testNewRequestCancelsOldFocusAndPausePreventsRetry() {
        let adapter = FakeAdapter(); adapter.focusResults = [false, false]
        var pending: [() -> Void] = [], active = true
        let focus = FocusCoordinator(adapter: adapter) { _, work in pending.append(work) }
        focus.request("old", isCurrent: { true }, afterAttempt: {}, completion: { _ in })
        focus.request("new", isCurrent: { active }, afterAttempt: {}, completion: { _ in })
        active = false
        while !pending.isEmpty { pending.removeFirst()() }
        #expect(adapter.focusAttempts == ["old", "new"])
    }
}
