import Testing
import Foundation
@testable import TilerCore

final class LayoutTests {
    let screen = Display(id: "main", frame: Rect(0, 0, 1200, 800), usable: Rect(0, 24, 1200, 716), fullscreen: Rect(0, 24, 1200, 776))
    func desktop() -> Desktop {
        let desktop = Desktop(); desktop.innerGap = 0; desktop.outerGap = 0
        desktop.updateDisplays([screen]); return desktop
    }
    func add(_ desktop: Desktop, _ id: String) { desktop.addWindow(id, frame: Rect(100, 100, 400, 300)) }
    @Test func testAutomaticQuadrantsAndFifthWindow() {
        let d = desktop(); add(d, "1")
        #expect(d.layout(d.current!, on: screen)["1"] == screen.usable)
        add(d, "2")
        #expect(d.layout(d.current!, on: screen)["2"] == Rect(600, 24, 600, 716))
        d.focus("1"); add(d, "3"); d.focus("1"); add(d, "4")
        let four = d.layout(d.current!, on: screen)
        #expect(four == ["1": Rect(0,24,600,358), "2": Rect(600,24,600,358),
                         "3": Rect(0,382,600,358), "4": Rect(600,382,600,358)])
        add(d, "5")
        let five = d.layout(d.current!, on: screen)
        for id in ["1", "2", "3"] { #expect(five[id] == four[id]) }
        #expect(five["4"] == Rect(600,382,300,358))
        #expect(five["5"] == Rect(900,382,300,358))
        add(d, "6")
        #expect(d.layout(d.current!, on: screen)["6"] == Rect(900,561,300,179))
    }
    @Test func testAutomaticGapsFloatingAndRemoval() throws {
        let d = desktop(); d.innerGap = 12; d.outerGap = 12
        for id in ["1", "2", "3", "4"] { add(d, id) }
        let before = d.layout(d.current!, on: screen)
        #expect(before["1"] == Rect(12,36,582,340))
        #expect(before["4"] == Rect(606,388,582,340))
        d.addWindow("dialog", frame: Rect(100,100,200,200), floating: true)
        for id in ["1", "2", "3", "4"] { #expect(d.layout(d.current!, on: screen)[id] == before[id]) }
        d.focus("2"); try d.toggleFloating(); try d.toggleFloating()
        for id in ["1", "2", "3", "4"] { #expect(d.layout(d.current!, on: screen)[id] == before[id]) }
        d.removeWindow("2"); add(d, "5")
        #expect(d.layout(d.current!, on: screen)["5"] == before["4"])
    }
    @Test func testExplicitSplitSurvivesAutomaticMembershipChanges() throws {
        let d = desktop()
        for id in ["1", "2", "3", "4"] { add(d, id) }
        d.focus("1"); try d.split(.horizontal); add(d, "5")
        let before = d.layout(d.current!, on: screen)
        #expect(before["5"] == Rect(300,24,300,358))
        d.focus("4"); try d.toggleFloating(); try d.toggleFloating()
        #expect(d.layout(d.current!, on: screen) == before)
        #expect(!d.current!.automaticLayout)
    }
    @Test func testNestedSplitsPartitionScreen() throws {
        let d = desktop(); add(d, "a"); try d.split(.vertical); add(d, "b")
        try d.select(true); try d.select(true); add(d, "c")
        let frames = d.layout(d.current!, on: screen)
        #expect(frames["a"] == Rect(0, 24, 600, 358))
        #expect(frames["b"] == Rect(0, 382, 600, 358))
        #expect(frames["c"] == Rect(600, 24, 600, 716))
        #expect(!(frames["a"]!.intersects(frames["b"]!)))
    }
    @Test func testIndividualFloatingRestoresOriginalTreePosition() throws {
        let d = desktop(); add(d, "a"); add(d, "b"); add(d, "c"); d.focus("b")
        let before = d.layout(d.current!, on: screen), tree = d.current!.tree.windows
        try d.toggleFloating()
        #expect(d.windows["b"]!.floating)
        #expect(d.layout(d.current!, on: screen)["a"]!.width == 600)
        try d.toggleFloating()
        #expect(d.layout(d.current!, on: screen) == before)
        #expect(d.current!.tree.windows == tree)
    }
    @Test func testWorkspaceFloatingPreservesNewAndIndividuallyFloatingWindows() throws {
        let d = desktop(); add(d, "a"); add(d, "b"); try d.toggleFloating(); d.focus("a")
        try d.toggleWorkspaceFloating(); add(d, "c"); d.removeWindow("a")
        try d.toggleWorkspaceFloating()
        #expect(d.windows["b"]!.floating)
        #expect(!(d.windows["c"]!.floating))
        #expect(d.layout(d.current!, on: screen)["c"] == screen.usable)
        #expect(Set(d.current!.tree.windows) == ["b", "c"])
    }
    @Test func testFullscreenUsesMenuBarButNotDockInsetAndRestores() throws {
        let d = desktop(); add(d, "a"); add(d, "b")
        let before = d.layout(d.current!, on: screen)
        try Command.fullscreen.apply(to: d)
        #expect(d.layout(d.current!, on: screen) == ["b": screen.fullscreen])
        try Command.fullscreen.apply(to: d)
        #expect(d.layout(d.current!, on: screen) == before)
        try d.toggleFloating(); let floating = d.windows["b"]!.floatingFrame
        try Command.fullscreen.apply(to: d); try Command.fullscreen.apply(to: d)
        #expect(d.windows["b"]!.floating); #expect(d.windows["b"]!.floatingFrame == floating)
    }
    @Test func testFocusExitsFullscreenButOwnedDialogDoesNot() throws {
        let d = desktop(); add(d, "a"); add(d, "b")
        d.windows["b"]?.bundle = "app"
        try Command.fullscreen.apply(to: d)
        d.addWindow("dialog", frame: Rect(200, 200, 300, 200), floating: true, focus: false)
        d.windows["dialog"]?.bundle = "app"; d.windows["dialog"]?.dialog = true
        d.focus("dialog")
        #expect(d.current!.fullscreen == "b")
        #expect(Set(d.layout(d.current!, on: screen).keys) == ["b", "dialog"])
        d.focus("a"); #expect(d.current!.fullscreen == nil)
    }
    @Test func testDirectionalFocusResizeAndContainerMovement() throws {
        let d = desktop(); add(d, "a"); add(d, "b")
        #expect(d.neighbor(.left) == "a")
        try d.resize(.right, amount: 50)
        let frames = d.layout(d.current!, on: screen)
        #expect(frames["b"]!.width > frames["a"]!.width)
        try d.move(.left); #expect(d.current!.tree.windows == ["b", "a"])
    }
    @Test func testWorkspaceSendAndVisibleWorkspaceSwitch() throws {
        let d = desktop(); add(d, "a"); add(d, "b"); try d.sendWindow(to: "2")
        #expect(d.current!.name == "1"); #expect(d.windows["b"]!.workspace == "2")
        let second = Display(id: "external", frame: Rect(1200, 0, 1000, 800), usable: Rect(1200, 24, 1000, 716), fullscreen: Rect(1200, 24, 1000, 776))
        d.updateDisplays([screen, second]); try d.switchWorkspace("2")
        #expect(d.focusedDisplay == "external")
        try d.moveWorkspace(to: "main")
        #expect(d.visible["main"] == "2"); #expect(d.visible["external"] == "1")
        d.updateDisplays([screen]); #expect(d.windows.count == 2)
        #expect(d.workspaces["1"]!.tree.windows == ["a"])
        d.updateDisplays([screen, second]); #expect(d.visible["external"] == "1")
    }
    @Test func testParkingRejectsCornersCoveredByOtherDisplays() {
        let left = Display(id: "left", frame: Rect(-1000, 700, 1000, 800), usable: Rect(-1000, 700, 1000, 800), fullscreen: Rect(-1000, 700, 1000, 800))
        let right = Display(id: "right", frame: Rect(1200, 700, 1000, 800), usable: Rect(1200, 700, 1000, 800), fullscreen: Rect(1200, 700, 1000, 800))
        #expect(Parking.frame(for: Rect(0, 0, 400, 300), on: screen, displays: [screen, left, right]) == nil)
        let candidate = Parking.frame(for: Rect(0, 0, 400, 300), on: screen, displays: [screen, right])!
        #expect(candidate.x < 0)
        #expect(Parking.isHidden(Rect(1199, 770, 400, 300), on: screen, displays: [screen]))
        #expect(!Parking.isHidden(Rect(1199, 770, 400, 300), on: screen, displays: [screen, right]))
        #expect(!Parking.isHidden(Rect(1100, 770, 400, 300), on: screen, displays: [screen]))
    }
    @Test func testDisconnectedWorkspaceReturnsToPreferredMonitorAfterTemporaryUse() throws {
        let d = desktop()
        let external = Display(id: "external", frame: Rect(1200,0,1000,800), usable: Rect(1200,24,1000,716), fullscreen: Rect(1200,24,1000,776))
        d.updateDisplays([screen, external]); try d.switchWorkspace("2"); add(d, "external-window")
        d.updateDisplays([screen]); try d.switchWorkspace("2")
        #expect(d.workspaces["2"]?.preferredDisplay == "external")
        d.updateDisplays([screen, external])
        #expect(d.visible["external"] == "2")
        #expect(Set(d.visible.values).count == 2)
        #expect(d.windows["external-window"]?.workspace == "2")
    }
    @Test func testCloseCollapsesRedundantContainers() throws {
        let d = desktop(); add(d, "a"); try d.split(.vertical); add(d, "b")
        d.removeWindow("a")
        #expect(d.current!.tree.children.count == 1)
        #expect(d.current!.tree.children[0].window == "b")
        d.removeWindow("b"); #expect(d.current!.tree.children.isEmpty)
    }
}
