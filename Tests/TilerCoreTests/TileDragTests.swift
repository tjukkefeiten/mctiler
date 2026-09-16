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
    func twoDisplays() -> Desktop {
        let d = desktop()
        d.updateDisplays(d.displays + [Display(id: "left", frame: Rect(-1000,0,1000,800), usable: Rect(-1000,24,1000,776), fullscreen: Rect(-1000,24,1000,776))])
        return d
    }
    func capture(_ d: Desktop) -> TileDrag {
        let slots = d.tileSlots()
        return TileDrag(source: "a", originalFrame: slots["a"]!, slots: slots, visibleWorkspaces: d.visible, displays: d.displays)
    }
    func movedFrame(_ drag: TileDrag) -> Rect {
        Rect(-900, 50, drag.originalFrame.width, drag.originalFrame.height)
    }
    @Test func droppingOnEmptyMonitorTransfersWindowAndFocus() {
        let d = twoDisplays(), drag = capture(d)
        #expect(d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        #expect(d.windows["a"]?.workspace == "2")
        #expect(d.focusedDisplay == "left")
        #expect(d.focusedWindow == "a")
        #expect(d.workspaces["1"]!.tree.windows.count == 3)
        #expect(d.workspaces["2"]!.tree.windows == ["a"])
        #expect(d.tileSlots()["a"] == d.displays[1].usable.inset(d.outerGap))
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag))) // duplicate mouse-up
    }
    @Test func occupiedMonitorDropInsertsWithoutDisplacingExistingWindows() {
        let d = twoDisplays()
        d.addWindow("other", frame: Rect(-900,50,400,300), workspace: "2")
        let drag = capture(d)
        #expect(d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        #expect(d.windows["a"]?.workspace == "2")
        #expect(d.windows["other"]?.workspace == "2")
        #expect(d.workspaces["2"]!.tree.windows.count == 2)
        #expect(d.workspaces["2"]!.automaticLayout)
    }
    @Test func emptyMonitorRejectsContentDragResizeAndOutsideDrop() {
        let d = twoDisplays(), drag = capture(d)
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: drag.originalFrame))
        var resized = movedFrame(drag); resized.width += 100
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: resized))
        #expect(!d.completeTileDrag(drag, x: -1100, y: 70, finalFrame: movedFrame(drag)))
        #expect(!d.completeTileDrag(drag, x: -700, y: 10, finalFrame: movedFrame(drag))) // menu bar
        #expect(d.windows["a"]?.workspace == "1")
    }
    @Test func dragRejectsChangedEmptyWorkspaceOrDisconnectedMonitor() throws {
        let d = twoDisplays(), drag = capture(d)
        d.focusedDisplay = "left"; try d.switchWorkspace("3")
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        try d.switchWorkspace("2")
        d.updateDisplays([d.displays[0]])
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        #expect(d.windows["a"]?.workspace == "1")
    }
    @Test func dragRejectsFloatingWorkspaceAndNewDestinationTile() {
        let d = twoDisplays(), drag = capture(d)
        d.workspaces["2"]?.floating = true
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        d.workspaces["2"]?.floating = false
        d.addWindow("new", frame: Rect(-900,50,400,300), workspace: "2")
        #expect(!d.completeTileDrag(drag, x: -700, y: 70, finalFrame: movedFrame(drag)))
        #expect(d.windows["a"]?.workspace == "1")
    }
    @Test func resizedNativeMoveTransfersOutAndRestoresFourTilesOnReturn() {
        let d = twoDisplays(), slots = d.tileSlots(), original = slots["a"]!
        let start = (x: original.x+100, y: original.y+20)
        let outward = TileDrag(source: "a", originalFrame: original, slots: slots,
                               visibleWorkspaces: d.visible, displays: d.displays, startPoint: start)
        let smaller = Rect(-900,50,original.width-40,original.height-20)
        #expect(d.completeTileDrag(outward, x: -800, y: 70, finalFrame: smaller))
        #expect(d.windows["a"]?.workspace == "2")
        let nextSlots = d.tileSlots(), full = nextSlots["a"]!
        let returning = TileDrag(source: "a", originalFrame: full, slots: nextSlots,
                                 visibleWorkspaces: d.visible, displays: d.displays,
                                 startPoint: (full.x+100, full.y+20))
        let target = nextSlots["b"]!
        let final = Rect(target.x,target.y,original.width,original.height)
        #expect(d.completeTileDrag(returning, x: target.x+100, y: target.y+20, finalFrame: final))
        #expect(d.windows["a"]?.workspace == "1")
        #expect(d.windows["b"]?.workspace == "1")
        #expect(d.workspaces["2"]!.tree.windows.isEmpty)
        #expect(d.workspaces["1"]!.automaticLayout)
        #expect(d.tileSlots().count == 4)
        #expect(d.tileSlots().values.allSatisfy { slots.values.contains($0) })
        #expect(d.focusedWindow == "a")
        #expect(d.focusedDisplay == "main")
    }
    @Test func resizedCrossDisplayMoveRequiresMatchingPointerTranslation() {
        let d = twoDisplays(), slots = d.tileSlots(), original = slots["a"]!
        let drag = TileDrag(source: "a", originalFrame: original, slots: slots,
                            visibleWorkspaces: d.visible, displays: d.displays,
                            startPoint: (original.x+100,original.y+20))
        let resized = Rect(-900,50,original.width-40,original.height-20)
        #expect(!d.completeTileDrag(drag, x: -200, y: 70, finalFrame: resized))
        #expect(d.windows["a"]?.workspace == "1")
        let edge = TileDrag(source: "a", originalFrame: original, slots: slots,
                            visibleWorkspaces: d.visible, displays: d.displays,
                            startPoint: (original.x+2,original.y+2))
        #expect(!d.completeTileDrag(edge, x: -898, y: 52, finalFrame: resized))
    }
    @Test func resizedTitleBarMoveAcceptsChangedHorizontalGrabOffset() {
        let d = twoDisplays(), slots = d.tileSlots(), original = slots["a"]!
        let drag = TileDrag(source: "a", originalFrame: original, slots: slots,
                            visibleWorkspaces: d.visible, displays: d.displays,
                            startPoint: (original.x+100,original.y+20))
        #expect(d.completeTileDrag(drag, x: -650, y: 75, finalFrame: Rect(-950,50,900,700)))
        #expect(d.windows["a"]?.workspace == "2")
    }
    @Test func sameWorkspaceDropStillSwaps() {
        let d = desktop(), drag = capture(d), before = d.tileSlots(), target = before["b"]!
        #expect(d.completeTileDrag(drag, x: target.x+100, y: target.y+20,
                                  finalFrame: Rect(target.x,target.y,drag.originalFrame.width,drag.originalFrame.height)))
        #expect(d.tileSlots()["a"] == before["b"])
        #expect(d.tileSlots()["b"] == before["a"])
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
