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
