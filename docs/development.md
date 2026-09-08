# Development

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```



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


Deferred features include tabbed/stacked layouts, Lua configuration, a settings UI, native Spaces integration, notarization, and public binary distribution.

See [validation](validation.md) for automated and live test evidence.
