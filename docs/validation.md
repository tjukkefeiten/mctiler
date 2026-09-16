# Validation

## Verified on this machine — 2026-09-08

- macOS 26.6.2, Apple Silicon, Swift 6.3.3 Command Line Tools.
- 24 Swift Testing tests passed across layout, reconciliation, configuration,
  recovery, and IPC suites.
- Release app and CLI built successfully; ad-hoc signatures verified with
  `codesign --verify --strict` and app metadata passed `plutil -lint`.
- Shipped example configuration passed validation: 39 bindings, zero active rules.
- All 39 default hotkeys successfully registered and were released by the
  `check-hotkeys` diagnostic while management was paused.
- Packaged app launched in paused mode; the CLI connected and returned the
  detected display, workspace 1, zero managed windows, and zero recovery entries.
- macOS reported Accessibility permission absent. No real windows were moved;
  the live acceptance checks below remain outstanding. Dock preferences were
  not changed, and permanent suppression is explicitly unavailable.

## Automated

Latest clarification to issue #1 on 2026-09-08: Option+Shift+Escape now invokes
`fullscreen`, not `floating`, in defaults and the migrated local configuration.
The focus adapter requests the target AX window and checks both foreground
application and focused window. A coordinator retries at most three times and
cancels stale requests. All 33 tests passed, the release app was rebuilt and
signed, and its old Accessibility entry was reset for the new signature. Actual
keyboard input into the fullscreen window still needs live verification after
granting access to this build.

Issue #5 update on 2026-09-08: all 39 built-in and example bindings now use Option
(`alt`), including Option+Shift+Escape for individual floating. The active local
configuration was backed up and migrated without changing assigned commands or
other settings, and collision validation passed. All 39 migrated shortcuts were
registered and released successfully while management was paused. The expanded
suite passed 30 tests, covering modifier masks, example/default agreement, custom
Command bindings, and normalized binding collisions. Real keyboard behavior and
pause/resume registration still need live validation with Accessibility access.

Follow-up on 2026-09-08: the floating-stack update passed 27 tests, including
raising floating windows after focus changes without a repeated polling loop,
excluding hidden/unmanaged windows, and keeping dialogs above fullscreen windows.
The default individual floating shortcut at that stage was Command+Shift+Escape. The release
app was rebuilt and signed; live validation of this update awaits a renewed
Accessibility grant because rebuilding changed the ad-hoc signature.

Run `bash scripts/test.sh`. The suite covers nested geometry, floating round trips with
window creation/destruction, fullscreen restoration and dialogs, directional
navigation, resize/move, workspace sends, monitor changes, parking boundaries,
configuration errors, duplicate events, partial enumeration, geometry rejection,
native-fullscreen/minimized exclusions, and journal persistence/corruption.

`bash scripts/build-app.sh` builds and ad-hoc signs the release app and CLI.
`dist/mctiler check-config config.example.toml` validates the shipped config.

## Live acceptance checklist — not yet certified

These checks require a logged-in GUI session, Accessibility permission, and
real applications. Automated core tests do not establish live compatibility.

1. Start with Terminal, Finder, Safari, and an Electron app; create two windows
   per application. Confirm existing and newly opened windows are tiled once.
2. Build nested horizontal/vertical splits; select a parent and move/resize it.
   Confirm polling does not discard the selection.
3. Float and re-tile the middle window. Toggle the whole workspace, move floating
   windows, create/close windows, then return to tiling. Verify surviving order.
4. Toggle McTiler fullscreen. Verify the menu bar remains available, no native
   Space is created, and exiting restores both tiled and floating geometry.
   Open a same-app dialog and confirm it remains accessible.
5. Put two windows from the same application on separate workspaces. Switch by
   hotkey and by normal application/window focus. Check for focus bouncing and
   inactive windows leaking onto a display.
6. Minimize and restore a window. Open an application-native fullscreen window,
   then exit it. Confirm McTiler suspends geometry changes while it is active.
7. Connect an external monitor with different scaling, move workspaces, unplug,
   reconnect, and sleep/wake. Check all windows remain recoverable. Test monitors
   both horizontally arranged and with different vertical offsets.
8. Use an app with minimum-size constraints and an unresponsive app. Confirm
   other commands remain responsive and rejected targets do not cause a loop.
9. Pause and quit. Confirm original geometry is restored and all McTiler hotkeys
   are released. Resume from the menu/CLI.
10. With test windows parked, force-terminate McTiler and relaunch. Verify recovery
    before normal management. Also exercise `recover --standalone` while stopped.
11. Revoke Accessibility permission. Verify management pauses and reports it;
    restore permission, Recover, then Resume.

Permanent Dock suppression is unavailable and must not be marked as passing.
For any future backend, use [the dedicated checks](dock-feasibility.md).

## Quadrant layout — 2026-09-08

- Previous Option/fullscreen/focus changes committed and pushed as `90df985`.
- Automatic placement fills TL, TR, BL, BR, then splits only the newest bottom-right tile with alternating axes. Fewer windows expand to fill available space.
- Floating/minimized/native-fullscreen windows are excluded from automatic tiled positions; insertion order survives floating round trips. Explicit tree edits disable automatic rebuilding for that workspace.
- 37 tests passed, including exact quadrant/fifth/sixth geometry, gaps, floating and removal, explicit split preservation, and batch versus incremental discovery.
- Release app rebuilt and signed. After a fresh Accessibility grant, resumed with six managed windows. The user accepted the live layout. The bottom-right region appeared crowded and an application rejected a resize; minimum window sizes are a possible cause, not independently confirmed. The user requested keeping the layout and closing issue #2.

## Focus follows mouse — 2026-09-08

- Enabled by default; `focus-follows-mouse = false` disables it on reload.
- Samples the pointer every 100 ms and hit-tests through Accessibility only after movement. Hidden/minimized/native-fullscreen windows and tiles behind McTiler fullscreen are excluded. Pointer focus uses existing bounded activation retries and floating stacking.
- Suppresses focus while mouse buttons are held, during keyboard-command grace, and when Accessibility reports an active menu. Retries check that the pointer still targets the window. Stationary pointer samples do not undo keyboard focus.
- 41 tests passed, including pointer transitions, suppression/reset, fullscreen eligibility, and config validation. Release build and signing succeeded.
- Opened paused after resetting stale Accessibility authorization. Live typing, overlapping floating windows, menu interaction, and multiple-display checks remain pending; issue #3 remains open.

### Pointer-focus review — 2026-09-09

The user reported only one successful focus change in five attempts. Review found that mouse focus shared the keyboard grace gate: movement during the next 350 ms was consumed, so stopping over a new window could leave it unfocused. Pointer suppression now uses a separate keyboard-only deadline; AX reconciliation retains its activation grace. Hit testing also walks AX parents when content omits AXWindow. All 42 tests passed and the release build succeeded. These fixes await renewed live testing; issue #3 remains open.

## Drag and drop tiles — 2026-09-09

- Issue #3 was accepted in live retesting and closed at the user's request; its implementation remains uncommitted alongside this work.
- Issue #6 now supports native window dragging onto an original tile slot to swap window identities. Visible cross-display swaps update workspace membership and focus while preserving container weights. Involved workspaces become manual layouts.
- Mouse-button state and active drag sessions suspend frame and stacking writes; mouse focus is suppressed. Content-only movement, resize, fullscreen, floating targets, gaps, cancelled moves, and changed layouts do not swap. Escape cancels the pending swap. No drop-target overlay yet.
- 46 tests passed, including destination validation, manual geometry preservation, cross-display membership/focus, floating round trips, and ineligible/disappearing targets. Release build succeeded.
- Opened paused after resetting stale Accessibility authorization. Native title-bar dragging and cancellation still need live validation; issue #6 remains open.

## Default inner gap — 2026-09-09

- Changed core and configuration defaults plus the example to 12 logical points between windows. Outer gap remains 8; explicit user values still override defaults.
- Backed up the active config, set its inner gap to 12, and reloaded the running app successfully (`Running`). No app replacement or Accessibility reset was needed for the live config change.
- 47 tests passed, including default horizontal/vertical quadrant gap geometry and usable-area bounds. Release packaging of the new built-in default is pending; the running build uses the explicit config value. Issue #4 remains open pending visual acceptance.

## Accepted features and documentation — 2026-09-09

- User accepted pointer focus, drag-and-drop with four windows, and the 12-point gaps. Issues #3, #6, and #4 were closed at their request; Option modifier issue #5 is also closed. Cross-display drag behavior has model coverage only.
- Graphite/orange artwork is bundled as the menu-bar image and a standard/Retina ICNS app icon. Menu bar shows the current workspace number. App was rebuilt, signed, reauthorized, and resumed successfully with three windows and status Running. The packaged binary includes the new 12-point built-in default.
- README now documents source-only installation (no releases exist), first launch, controls, configuration, recovery, uninstall, and current limitations. Detailed usage/development/recovery guides and a labelled layout illustration are linked. No private desktop screenshot is published.
- Example configuration validates with 39 bindings; local documentation links, shell syntax, and git whitespace checks pass. Latest implementation regression suite: 47 passing tests. Live walkthroughs support the features described; clean-machine installation and broader hardware validation have not been performed.

## Floating stacking after pointer focus — 2026-09-16

System Settings floated correctly but could be covered after pointer focus activated a tile. Added three bounded post-activation stacking repairs (150/400/800 ms), guarded by fresh foreground focus and cancellation for commands, dragging, or pause. These issue raises only, without requesting keyboard focus. The delayed-activation race is a working diagnosis pending live confirmation.

50 tests passed across nine suites, including delayed repair, stale request cancellation, and fresh unmanaged foreground protection. Release build/signing succeeded. One window initially rejected recovery, then restored on retry; all recovery entries cleared before quitting. Updated build launched paused after resetting Accessibility. Live validation remains pending.

## Accessibility icon investigation — 2026-09-16

Issue #9: confirmed Launch Services and the running application both resolve to the repository dist/McTiler.app (no copy exists in /Applications or ~/Applications). CFBundleIconFile points to McTiler.icns; signature verification and iconset extraction passed for all ten standard/Retina representations. NSWorkspace and NSRunningApplication resolve branded artwork; the inspected NSWorkspace rendering includes a pale rounded border around the source artwork.

Refreshed only McTiler registration and quit/reopened System Settings, preserving Accessibility permissions. A window-only screencapture attempt failed; visual confirmation in the Accessibility pane is pending. No confirmed packaging defect or claim of a completed fix. Documented targeted refresh steps in the README.

## Empty-display pointer focus — 2026-09-16

Issue #10 live snapshot confirmed unique assignments: external workspace 1 held four windows; built-in workspace 2 was empty. The shared menu-bar label reported globally focused workspace 1. Pointer polling required a window hit and therefore could not select an empty display.

Added movement-driven display targeting before window hit testing, using display bounds. It retains pause/drag/keyboard-grace suppression and cancels stale focus/stacking requests when the display changes. Status now exposes focusedDisplay and display origins. All 53 tests passed, including the four-external-windows/empty-built-in sequence, stale AX focus, workspace targeting, stationary-pointer suppression, negative coordinates, and display removal. Live validation remains pending.

## Live follow-up — 2026-09-16

- User confirmed the empty-display targeting fix and requested closure of #10.
- User visually confirmed the Accessibility icon after targeted registration refresh and reopening Settings; #9 is closed.
- Floating stacking #8 remains unresolved: System Settings is marked floating and AXRaise returns success, but observed window order still places an overlapping iTerm window above it. The bounded delayed raises do not resolve this report. User explicitly rejected retaining floating-window keyboard focus as a workaround.
- Cross-monitor mouse dragging is tracked separately in #11; keyboard movement works, but the reported mouse failure has not yet been diagnosed.
- Fullscreen defaults and the active local configuration now use Option+Space. Latest regression run: 53 passing tests.

## Cross-monitor drag to empty workspace — 2026-09-16

Issue #11: drag completion previously required another tile to swap with, so an empty destination display always rejected the drop. Added a shared drop-completion path for occupied-tile swaps and transfers to another display’s empty tiled workspace. Captured display geometry and visible workspace assignments are checked before mutation, alongside the tile layout. Focus follows the transferred window.

58 tests passed, including empty-display transfer, occupied-display swap through the same completion handler, duplicate release, invalid/content/resize drops, negative coordinates, changed destination workspace, new windows, and display removal. Live validation remains pending. Native drags that also resize the window remain rejected; this may need further compatibility work for apps that resize when crossing to a smaller display.

### Cross-monitor drag follow-up

The user reported that empty-monitor transfer still failed. Status confirmed the app was running with an empty built-in workspace 9. Found a controller integration defect: every app-activation notification called schedule(displays:), which unconditionally cancelled a pending drag even with identical display geometry. Cancellation now occurs only when the actual display list changes. Added lastDrag diagnostics for candidate capture, cancellation, final geometry, layout/workspace/display invariants, and drop outcome. The 58-test suite passes and the release build succeeded; live confirmation is pending.

### Cross-monitor return-drag follow-up

User clarified that the native window follows the pointer across displays and snaps back on release. Latest lastDrag was an ordinary no-movement click, so it did not capture the failed return drag. Added a bounded recentDrags history for actual geometry-changing attempts. Drop evaluation now waits 120 ms after mouse-up while layout remains suspended; sessions carry unique IDs to prevent stale completions. Cross-display native size changes are accepted only with an interior grab and window translation matching the pointer (or display clamping). Ordinary edge resize/content drags remain rejected.

60 tests passed, including transfer to another display followed by a resized return swap and rejection of mismatched translations/edge resizing. Live cause and reliability still need confirmation.

### Cross-display insertion and variable grab offsets (2026-09-16)

Live diagnostics recorded rejected drops with unchanged display/workspace/layout
snapshots but `nativeMove: false` after window size changes. The user also
confirmed cross-display swaps were unwanted: returning a fourth window should
restore four tiles. Cross-display drops now insert into the destination workspace
(including occupied tiles and gaps); same-workspace drops still swap. A resized
cross-display move may retain an interior title-bar grab with a changed horizontal
offset instead of exact translation. Start points are now retained in diagnostics.
All 62 tests pass, including four-window round trips, occupied-destination insertion,
changed grab offsets, and same-workspace swaps. Live verification remains pending.
