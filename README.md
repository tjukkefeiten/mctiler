# McTiler

An independent macOS tiling window manager: explicit split trees, numbered virtual
workspaces, and shortcuts to float one window or a whole workspace. Written in
Swift with AppKit and Accessibility APIs. Requires macOS 26 and Swift 6.3 for the
initial supported build. SIP stays enabled.

This is an initial implementation, not a claim of i3-level reliability. Real-app
compatibility and multi-monitor parking must be checked on your setup before
relying on it for daily work. See [validation](docs/validation.md).

## Build and launch

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/McTiler.app
```

The build produces `dist/McTiler.app` and `dist/mctiler`, both ad-hoc signed for
local use. Keep the app at a stable location; replacing an ad-hoc signed build
can require renewing its Accessibility permission. No installer, login item, or
system preference changes happen during the build.

Use `open dist/McTiler.app --args --paused` to inspect the menu bar and CLI before
enabling management. Existing recovery entries are still processed on launch.

From the **McT** menu, choose **Grant Accessibility Access…**. Enable McTiler in
**System Settings → Privacy & Security → Accessibility**, then choose **Resume**.
The app starts paused if permission is absent. Pause another tiling manager first
so the two apps do not compete for geometry or shortcuts.

Use one native macOS desktop per display for this version. McTiler supplies its
own workspaces. Native fullscreen is not used by McTiler.

```sh
./dist/mctiler status
./dist/mctiler workspace 2
./dist/mctiler floating
./dist/mctiler fullscreen
./dist/mctiler pause
./dist/mctiler resume
```

To start at login, add the built app through macOS Login Items yourself. This is
optional; McTiler never enables it automatically.

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

New workspaces use automatic quadrant tiling. One window fills the usable area;
two share equal columns; the third splits the left column into top and bottom;
the fourth splits the right column. The order is top-left, top-right,
bottom-left, bottom-right. Window five splits the bottom-right quadrant side by
side. Later windows split the newest tile, alternating vertical and horizontal.
Configured inner and outer gaps apply throughout.

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

## Configuration

Copy [config.example.toml](config.example.toml) to
`~/.config/mctiler/config.toml`. The file is optional; built-in shortcuts and
8-point gaps apply without it.

```sh
./dist/mctiler check-config config.example.toml
./dist/mctiler reload
```

While McTiler and other managers are paused, `./dist/mctiler check-hotkeys`
temporarily registers and releases the configured shortcuts to check for
conflicts with other software or macOS.

The parser supports the documented TOML subset: root scalar settings, string
tables for bindings and display assignments, and `[[rules]]` entries. Strings
must be double-quoted. Unsupported syntax and unknown keys are errors. A
`[bindings]` table replaces all default bindings. Invalid reloads preserve the
working configuration. Failed hotkey registration attempts restore the previous
bindings. Application rules use exact bundle IDs, first match wins, and apply
to newly discovered windows; restart to reapply them to all windows.

Existing `[bindings]` tables override the defaults, so changing the application
alone does not migrate a custom configuration. Back up your config, replace the
`cmd` modifier with `alt` in each binding key, keep the assigned commands and
other preferences, and run `check-config` before reloading. Resolve duplicate
bindings rather than overwriting them. For example:

```toml
alt-shift-escape = "fullscreen"
alt-ctrl-space = "workspace-floating"
alt-ctrl-escape = "pause"
```

If you still have the older `cmd-shift-space = "floating"` binding, use
`alt-shift-escape = "fullscreen"` for the current fullscreen toggle.
If it already says `floating`, change that command to `fullscreen` and reload.
Individual floating remains available through `mctiler floating` or a custom binding.
Command remains a supported modifier for custom bindings.

## Dock suppression

**Complete Dock suppression is currently unavailable.** The
`experimental-suppress-dock` option records the request and explains the status;
it does not change Dock preferences. McTiler fullscreen reserves no Dock space,
but the Dock may still appear over it.

Apple's [`hideDock`](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct/hidedock)
option hides and disables the Dock, but
[`presentationOptions`](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.property)
apply while the requesting application is active. McTiler runs in the background
while other applications receive focus. Setting that property does not provide
persistent global suppression. A long auto-show delay is not equivalent to
“never appears,” so this build does not silently substitute it.

See [Dock feasibility](docs/dock-feasibility.md) for the implementation boundary
and the acceptance checks for any future experimental backend.

## Recovery

Before moving a window, McTiler atomically writes and synchronizes its original,
previous, and target geometry to
`~/Library/Application Support/McTiler/recovery.json`. That file contains window
titles and has user-only permissions. Pause and normal quit restore original
rectangles, clamped to an available display. Application exits discard their
live recovery records.

If McTiler crashes or is forcibly terminated, relaunch it to recover. Alternatively:

```sh
./dist/mctiler recover --standalone
```

Standalone recovery refuses to run alongside the app and needs Accessibility
permission for the CLI or the terminal launching it. Within the running app,
`mctiler recover` restores windows and leaves management paused.

Recovery matches process launch identity, title, and recent geometry rather than
guessing between indistinguishable windows. Unresolved entries remain on disk;
the app stays paused and reports their count. Keep affected applications open
and retry recovery. It does not automatically delete a corrupt journal.

Window parking may leave a one-pixel edge strip. Unsupported display arrangements
or rejected parking cause management to pause and attempt restoration. See the
[AeroSpace workspace guide](https://nikitabobko.github.io/AeroSpace/guide#emulation-of-virtual-workspaces)
for the general macOS limitations of this technique.

## Development

- `TilerCore`: geometry, tree, workspaces, command/config parsing, reconciliation.
- `MacAdapter`: Accessibility, display coordinates, durable recovery journal.
- `TilerIPC`: user-restricted Unix socket and single-instance lock.
- `McTiler`: menu bar app, global hotkeys, serialized window controller.
- `McTilerCLI`: commands, configuration checks, standalone recovery.

The test script uses Swift Testing and supplies its framework search path when
building with Command Line Tools. Full Xcode is not required.

The main thread owns UI and hotkeys. A serial worker handles window state and
Accessibility calls; notifications are coalesced and a one-second poll repairs
missed events. Calls have short timeouts, failed application enumeration has a
cooldown, and rejected targets are not retried indefinitely. Layout and fake
adapter tests never manipulate real windows.

The CLI protocol is one newline-terminated JSON request and response per
connection, with a 64 KiB request limit and socket timeouts. The socket is in a
user-owned mode-0700 directory at `/tmp/mctiler-UID/control.sock`, mode 0600;
the server also checks the connecting user's identity. No network listener is
opened.

Deferred: tabbed/stacked layouts, Lua, settings UI, custom bars, native Spaces
integration, drag-to-reorder tiling, notarization, and public distribution.
