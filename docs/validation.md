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
