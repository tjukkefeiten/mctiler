# Recovery

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

