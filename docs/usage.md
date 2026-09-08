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
| Option + Shift + Escape | Toggle fullscreen, raise, and focus |
| Option + Control + Space | Toggle workspace floating |
| Option + Control + F | Toggle McTiler fullscreen |
| Option + Control + H / V | Set horizontal / vertical split |
| Option + Control + P / C | Select parent / first child |
| Option + Control + R | Reload configuration |
| Option + Control + Escape | Pause and restore windows |

Drag a tiled window by its title bar and release the pointer inside another
tile to swap their positions. This also works between visible workspaces on
different displays. Tile sizes, gaps, and split weights are preserved; the
involved workspaces switch to manual layout. The moved window keeps focus.
Layout writes wait until you release the mouse, so the window can move freely.
The destination is the tile's original layout slot, even when the dragged
window covers it; there is no drop-target highlight in this version.

Drops into gaps, outside tiles, or after the layout changes restore the original
arrangement. Escape cancels the swap. Dragging content or resizing does not swap
tiles. Floating windows retain normal movement; fullscreen windows do not take
part in tile swaps.

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

Option+Shift+Escape toggles fullscreen and requests keyboard focus for that
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

