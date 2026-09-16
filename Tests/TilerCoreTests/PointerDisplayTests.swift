import Testing
@testable import TilerCore

struct PointerDisplayTests {
    func desktop() -> Desktop {
        let d = Desktop()
        d.updateDisplays([
            Display(id: "external", frame: Rect(0,0,3360,1890), usable: Rect(0,30,3360,1860), fullscreen: Rect(0,30,3360,1860)),
            Display(id: "builtin", frame: Rect(-1800,721,1800,1169), usable: Rect(-1800,751,1800,1139), fullscreen: Rect(-1800,751,1800,1139))
        ])
        return d
    }
    @Test func enteringEmptyDisplayTargetsItsWorkspaceWithoutDuplicatingAssignments() throws {
        let d = desktop(), adapter = FakeAdapter(), pointer = PointerFocus()
        let r = Reconciler(desktop: d, adapter: adapter, configuration: .defaults)
        let observed = (1...4).map { ObservedWindow(id: String($0), frame: Rect(0,30,500,400)) }
        let snapshot = WindowSnapshot(windows: observed, focused: "1")
        r.ingest(snapshot)
        func move(_ x: Double, _ y: Double) {
            _ = pointer.update(x: x, y: y, enabled: true, moved: {
                d.focusDisplayFromPointer(x: x, y: y)
            }, target: { nil })
        }
        move(100,100); move(-100,800)
        #expect(d.focusedDisplay == "builtin")
        #expect(d.current?.name == "2")
        #expect(d.focusedWindow == nil)
        // macOS can keep the external app focused: repeated observations must
        // not undo the explicit display target when there is no new AX focus.
        r.ingest(snapshot)
        #expect(d.focusedDisplay == "builtin")
        try d.switchWorkspace("3")
        #expect(d.visible == ["external": "1", "builtin": "3"])
        #expect(d.windows.values.allSatisfy { $0.workspace == "1" })
        move(100,100)
        #expect(d.current?.name == "1")
        #expect(Set(d.visible.values).count == 2)
    }
    @Test func stationaryDisabledOrDraggingPointerDoesNotChangeDisplay() {
        let d = desktop(), pointer = PointerFocus()
        func sample(_ x: Double, enabled: Bool) {
            _ = pointer.update(x: x, y: 800, enabled: enabled, moved: {
                d.focusDisplayFromPointer(x: x, y: 800)
            }, target: { nil })
        }
        sample(100, enabled: true)
        sample(-100, enabled: false) // paused, dragging, or keyboard grace
        #expect(d.focusedDisplay == "external")
        sample(-100, enabled: true) // stationary after suppression
        #expect(d.focusedDisplay == "external")
        sample(-101, enabled: true)
        #expect(d.focusedDisplay == "builtin")
        d.focusedDisplay = "external" // explicit keyboard selection
        sample(-101, enabled: true)
        #expect(d.focusedDisplay == "external")
    }
    @Test func emptyDisplaysBoundariesAndDisconnect() {
        let d = desktop()
        #expect(!d.focusDisplayFromPointer(x: -100, y: 100)) // outside any display
        #expect(d.focusDisplayFromPointer(x: -1, y: 800))
        #expect(d.current?.name == "2")
        #expect(d.focusDisplayFromPointer(x: 0, y: 800))
        #expect(d.current?.name == "1")
        d.updateDisplays([d.displays[0]])
        #expect(!d.focusDisplayFromPointer(x: -1, y: 800))
        #expect(d.focusedDisplay == "external")
    }
}
