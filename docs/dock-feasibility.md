# Persistent Dock suppression investigation

Requested behavior: no Dock appearance while McTiler manages windows, including
prolonged pointer contact with any display edge. The top menu bar and application
switching must continue to work. Restore previous behavior on pause and quit.

## Evidence

The installed macOS SDK's `AppKit.framework/Headers/NSApplication.h` documents
`presentationOptions` as applying when the requesting application is active.
Apple's current documentation says the same. `hideDock` is distinct from
`autoHideDock`, but neither gives a background window manager a persistent
policy over other applications' presentation options.

- [Presentation options scope](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.property)
- [Hide Dock](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct/hidedock)
- [Effective options change when active applications change](https://developer.apple.com/documentation/appkit/nsapplication/currentsystempresentationoptions)

## Decision for v0.1

No verified backend meets the requirement with SIP enabled and normal foreground
application use. `DockSuppression.available` is false. The experimental config
option exposes that fact in status instead of altering the system. This is a
documented unavailable feature, not a successful implementation of suppression.

An enormous auto-show delay would only approximate the request and is excluded.
Stealing foreground activation to retain McTiler's presentation options would
break typing into managed apps and is excluded. This build does not terminate,
suspend, replace, or inject into the Dock process.

No Dock preferences were changed during development, so no restoration is needed
for this backend. A future mutating backend must journal the original settings
before enabling itself and restore them through the existing pause/quit/recovery
lifecycle, including after a crash.

## Required live validation for a future backend

- Switch repeatedly between Terminal, Finder, Safari, and an Electron app; type
  and use Command+Tab normally.
- Hold the pointer at each display edge and use macOS Dock-reveal shortcuts.
- Exercise tiled, floating, and McTiler fullscreen layouts.
- Disconnect/reconnect displays, sleep/wake, and restart the Dock process.
- Confirm the top menu bar still works and receives the focused app's menus.
- Pause, quit, and force-terminate/recover McTiler; verify original Dock behavior.

Until a backend passes these checks, do not advertise permanent Dock hiding.
