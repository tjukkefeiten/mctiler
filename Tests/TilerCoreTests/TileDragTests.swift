import Testing
@testable import TilerCore

struct TileDragTests {
    func desktop() -> Desktop {
        let d = Desktop(); d.innerGap = 12; d.outerGap = 12
        d.updateDisplays([Display(id: "main", frame: Rect(0,0,1200,800), usable: Rect(0,24,1200,776), fullscreen: Rect(0,24,1200,776))])
        for id in ["a", "b", "c", "d"] { d.addWindow(id, frame: Rect(0,24,400,300)) }
        return d
    }
    @Test func dropRequiresNativeMoveAndUniqueTile() {
        let original = Rect(0,24,400,300)
        let drag = TileDrag(source: "a", originalFrame: original, slots: ["a": original, "b": Rect(420,24,400,300)])
        #expect(drag.destination(x: 500, y: 40, finalFrame: Rect(450,24,400,300)) == "b")
        #expect(drag.destination(x: 500, y: 40, finalFrame: original) == nil) // content drag/cancellation
        #expect(drag.destination(x: 500, y: 40, finalFrame: Rect(450,24,450,300)) == nil) // resize
        #expect(drag.destination(x: 410, y: 40, finalFrame: Rect(350,24,400,300)) == nil) // gap
        #expect(drag.destination(x: 100, y: 40, finalFrame: Rect(50,24,400,300)) == nil) // original slot
        #expect(drag.destination(x: -100, y: 40, finalFrame: Rect(-200,24,400,300)) == nil)
    }
    @Test func swapPreservesGeometryAndSurvivesNewWindows() throws {
        let d = desktop()
        d.focus("a"); try d.resize(.right, amount: 25)
        let before = d.tileSlots()
        #expect(d.swapTiles("a", "d"))
        let after = d.tileSlots()
        #expect(after["a"] == before["d"])
        #expect(after["d"] == before["a"])
        for id in ["b", "c"] { #expect(after[id] == before[id]) }
        #expect(d.focusedWindow == "a")
        #expect(!d.current!.automaticLayout)
        try d.toggleFloating(); try d.toggleFloating()
        #expect(d.tileSlots() == after)
        d.addWindow("e", frame: Rect(0,0,300,200))
        #expect(d.current!.tree.windows.first == "d")
    }
    @Test func swappingAcrossDisplaysUpdatesMembershipAndFocus() throws {
        let d = desktop()
        d.updateDisplays(d.displays + [Display(id: "left", frame: Rect(-1000,0,1000,800), usable: Rect(-1000,24,1000,776), fullscreen: Rect(-1000,24,1000,776))])
        d.addWindow("other", frame: Rect(-900,24,400,300), workspace: "2")
        let before = d.tileSlots()
        #expect(d.swapTiles("a", "other"))
        #expect(d.windows["a"]?.workspace == "2")
        #expect(d.windows["other"]?.workspace == "1")
        #expect(d.focusedDisplay == "left")
        #expect(d.focusedWindow == "a")
        #expect(d.tileSlots()["a"] == before["other"])
        #expect(d.tileSlots()["other"] == before["a"])
        #expect(d.workspaces["1"]!.insertionOrder.contains("other"))
        #expect(!d.workspaces["1"]!.insertionOrder.contains("a"))
    }
    @Test func ineligibleOrDisappearingWindowsCannotSwap() throws {
        let d = desktop()
        d.addWindow("hidden", frame: Rect(0,0,400,300), workspace: "3")
        #expect(!d.swapTiles("a", "hidden"))
        d.focus("b"); try d.toggleFloating()
        #expect(!d.swapTiles("a", "b"))
        d.windows["c"]?.minimized = true
        #expect(!d.swapTiles("a", "c"))
        d.current!.fullscreen = "a"
        #expect(!d.swapTiles("a", "d"))
        d.current!.fullscreen = nil
        d.removeWindow("d")
        #expect(!d.swapTiles("a", "d"))
        #expect(!d.swapTiles("a", "a"))
    }
}
