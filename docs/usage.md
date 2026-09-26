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
| Option + Shift + S | Stash the focused window in the scratchpad |
| Option + S | Show/hide a scratchpad window |
| Option + Control + S | Show the next scratchpad window |
| Option + Control + Shift + S | Release the focused scratchpad window |

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


With focus follows mouse enabled, moving the pointer onto a display selects that
display for workspace commands even when it has no managed windows. The menu-bar
number shows the globally focused workspace; macOS may show that same status
item on both displays. It is not a separate workspace label for each display.
`mctiler status` reports `focusedDisplay`, display coordinates, and the distinct
`visibleWorkspaces` mapping for verification.

## Scratchpad

The scratchpad holds managed windows outside the normal tiled layout. It is
global across workspaces and displays, with at most one scratchpad window shown
at a time. Windows remain individually managed, so stashing one window does not
hide the rest of its application.

| Command | Behavior |
| --- | --- |
| `scratchpad move` | Stash and hide the focused window. Stashing an existing scratchpad window hides it without adding a duplicate. |
| `scratchpad show` | Hide the scratchpad window if one is shown on the current workspace. Otherwise summon the most recently selected/stashed entry here, falling back to the first available entry. |
| `scratchpad next` | Show the next available entry in insertion order, wrapping around. Minimized and native-fullscreen entries are skipped. With one eligible entry, keep it shown. |
| `scratchpad release` | Remove the focused, shown window from the scratchpad and restore its previous individual tiled/floating mode on the current workspace. |

All commands use the `mctiler` CLI prefix and can be assigned to custom bindings.
No available entry produces an error rather than launching an application.
To enable the defaults in an existing custom `[bindings]` table, add:

```toml
alt-shift-s = "scratchpad move"
alt-s = "scratchpad show"
alt-ctrl-s = "scratchpad next"
alt-ctrl-shift-s = "scratchpad release"
```

### Placement and focus

- A tiled window initially gets a centered floating rectangle using 60% of the
  display's usable width and height. Already-floating windows retain their frame.
- Native dragging/resizing of a shown scratchpad window is remembered. Summoning
  it on another display centers its retained size, clamped to that display.
- Showing focuses the window and uses ordinary floating-window stacking. It exits
  McTiler fullscreen on the destination workspace. Hiding restores the prior
  focused window when it is still eligible, otherwise another visible member.
- When a scratchpad window's workspace becomes hidden or its display disconnects,
  the scratchpad window becomes hidden too. Returning to that workspace does not
  automatically show it. Focusing another display alone does not hide it; use
  `scratchpad show` there to bring it over.
- Hidden entries cannot be focused by pointer focus or stale AX focus reports.
  They do not occupy tiles, even in a floating workspace or behind fullscreen.
- Releasing on the same workspace preserves a manual tree slot. Summoning on a
  different workspace transfers membership; release then uses that workspace's
  layout. `send N` also releases a shown scratchpad window before moving it to N.
  Use release before toggling its individual floating mode.

### Lifetime and limitations

Scratchpad membership and order are in-memory, like workspace layouts; they are
not restored after restarting McTiler. Pause, Quit, and crash recovery restore
scratchpad windows through the ordinary recovery journal. Pause/Resume in the
same process retains membership, so resuming parks hidden entries again.

Hidden entries use workspace parking, which can leave a narrow edge strip and can
be rejected by some apps/display arrangements. Floating stacking has the same
application-dependent limitations as other floating windows; it does not promise
always-on-top behavior. Minimized and app-native fullscreen windows must be
restored/exited before they can be summoned. Closing a window removes its entry.

`mctiler status` reports the scratchpad insertion order and shown window ID, plus
`scratchpad` and `scratchpadHidden` flags on each window state. Automated coverage
is recorded in [validation](validation.md); live application/monitor validation
is still pending.
