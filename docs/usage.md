# Using McTiler

## Layout and shortcuts

Option is the default primary modifier (`alt` in configuration). Normal Command
shortcuts remain available. Option-based bindings can overlap character entry
or navigation shortcuts on your keyboard layout; all bindings are configurable.
Pause releases all bindings. Resume from the menu bar or CLI. Shortcuts use
physical US key positions.

| Shortcut | Action |
| --- | --- |
| Option + arrows | Focus in a direction |
| Option + Shift + arrows | Move the selected tile/container, or move a floating window |
| Option + Control + arrows | Resize; right/down grow, left/up shrink |
| Option + 1–9 | Switch workspace |
| Option + Shift + 1–9 | Send focused window to workspace |
| Option + Space | Toggle fullscreen, raise, and focus |
| Option + Control + Space | Toggle workspace floating |
| Option + Control + F | Toggle McTiler fullscreen |
| Option + Control + H / V | Set horizontal / vertical split |
| Option + Control + P / C | Select parent / first child |
| Option + Control + R | Reload configuration |
| Option + Control + Escape | Pause and restore windows |

Drag a tiled window by its title bar and release the pointer inside another
tile in the same workspace to swap their positions. Dropping onto another
display inserts the window into its visible workspace and applies that workspace’s
layout. Existing windows remain there; returning a fourth window restores four
quadrants in an automatic workspace. Cross-display drops also work in gaps.
For swaps, tile sizes, gaps, and split weights are preserved; the
involved workspaces switch to manual layout. The moved window keeps focus.
Layout writes wait until you release the mouse, so the window can move freely.
For same-workspace swaps, the destination is the tile's original layout slot, even when the dragged
window covers it; there is no drop-target highlight in this version.

Drops into gaps within the same workspace, outside eligible destinations, or after the layout changes restore the original
arrangement. Escape cancels the swap. Dragging content or resizing does not swap
tiles. Floating windows retain normal movement; fullscreen windows do not take
part in tile swaps.

Known issue: a cross-monitor drag that changes the window’s size may be rejected
when grabbed very close to the title bar’s top edge. Grab slightly lower as a
workaround; tracked in [issue #11](https://github.com/tjukkefeiten/mctiler/issues/11).

Focus follows the mouse by default: moving into a visible managed window gives
it keyboard focus without clicking. Hit testing respects overlapping windows.
A stationary pointer, mouse-button drag, or pointer over unmanaged UI does not
trigger focus. Keyboard commands get a short grace period, and pointer movement
cannot reveal tiles behind a fullscreen window. Set `focus-follows-mouse = false`
at the top level of your config and reload to disable it.

New workspaces use automatic quadrant tiling. One window fills the usable area;
two share equal columns; the third splits the left column into top and bottom;
the fourth splits the right column. The order is top-left, top-right,
bottom-left, bottom-right. Window five splits the bottom-right quadrant side by
side. Later windows split the newest tile, alternating vertical and horizontal.
Configured inner and outer gaps apply throughout. The default gap between tiles
is 12 macOS logical points; the outer gap is 8. Explicit configuration values
override these defaults, including on Retina displays.

Placement follows discovery/insertion order, independent of focus. Floating,
minimized, and native-fullscreen windows do not consume tiled positions; returning
them restores their place in that order. Closing or sending a window compacts the
remaining tiles. Explicit split, container selection, tiled move, or tiled resize
switches that workspace to manual layout for the rest of the session, preserving
its tree and adjustments during subsequent discovery.

Splitting a selected tile wraps it in a container. The next window opens beside
that tile within the new split. Selecting a container makes new windows its
children. Movement swaps siblings along the nearest matching split axis;
cross-container reparenting and i3 command compatibility are not implemented.

Floating windows retain a place in the tree without consuming tiled space.
They are raised above tiled windows after layout and focus changes, with the
focused floating window raised last. Unchanged polls do not repeatedly raise
windows. Returning to tiling removes the window from the floating order.
Raising does not explicitly activate the floating window's application; behavior
still depends on the application's Accessibility support.
Workspace floating retains the tree as well. New windows join that tree even
while the workspace is floating. Switching back restores surviving tiles;
individually floated windows stay floating. Drag or resize floating windows with
normal macOS window controls.

Option+Space toggles fullscreen and requests keyboard focus for that
window. Option+Control+F remains an equivalent shortcut. Fullscreen fills the
display below the top menu bar, ignoring Dock-reserved space. It stays in the current workspace and restores the previous geometry on
exit. Other ordinary windows are parked temporarily. Same-application dialogs
remain accessible. Focusing another ordinary window exits fullscreen.
Menu bar auto-hide follows your macOS setting; McTiler does not change it.

Workspaces are globally numbered, with one visible per display. Switching to a
workspace already visible on another display focuses that display. Otherwise it
opens on the focused display. `move-workspace DISPLAY_ID` swaps the current
workspace with the target display's visible workspace. `focus-display DISPLAY_ID`
changes the focused monitor. Display UUIDs are included in `status` output.
Disconnected monitors' workspaces remain separate and can be opened on the
remaining display; preferred assignments are retained for reconnection.
Each display remembers its last visible workspace, including when several
workspaces prefer that display.

### Locking, sleep, and wake

System sleep suspends automatic layout, pointer focus, and drag handling while
retaining window identities and workspace state. Screen locking and session
deactivation also suspend management. Overlapping suspension reasons must all
end before recovery starts. Screen locking uses unofficial macOS distributed
notifications; three live lock/unlock cycles passed on the tested setup.
On wake or unlock, McTiler waits for the
known windows and displays to return and for display geometry to stay unchanged
for one second. During this settling period, layout commands report that recovery
is in progress; Status, Pause, Recover, and Quit remain available.

After ten seconds, management can continue on the available displays if a monitor
is still absent or an application closed. If no displays are available, it keeps
waiting. A monitor returning later reclaims its last visible workspace; windows
on its hidden workspaces keep their membership. A previously paused session stays
paused. This is in-memory state, not persistence across app restarts.

`mctiler status` includes `sleepWake.phase` (`sleeping`, `settling`, or `awake`),
`lastResult`, `screenLocked`, `sessionInactive`, `lockCount`, and the missing
display/window IDs from the last recovery check. Compare
`windowStates` (window ID and workspace) and `visibleWorkspaces` before and after
sleep to distinguish membership changes from misplaced windows. Actual sleep/wake,
hidden workspace, and delayed monitor return validation remain pending;
see [validation](validation.md).

### Pointer display selection
With focus follows mouse enabled, moving the pointer onto a display selects that
display for workspace commands even when it has no managed windows. The menu-bar
number shows the globally focused workspace; macOS may show that same status
item on both displays. It is not a separate workspace label for each display.
`mctiler status` reports `focusedDisplay`, display coordinates, and the distinct
`visibleWorkspaces` mapping for verification.
