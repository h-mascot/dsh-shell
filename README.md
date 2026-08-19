# DSH Shell v2

Native AppKit/WKWebView shell for DSH with a real Off / High / Max reasoning-effort rail.

## Build and gate

From this directory:

```sh
./scripts/build-app.sh
./scripts/ctrl-gate.sh
```

The build creates `.build/DSH Shell.app`, compiles `main.swift` and `EffortControlScript.swift` with system `swiftc`, copies `Info.plist` and `Resources/`, and applies an ad-hoc signature. The gate is fail-closed: it checks JavaScript and plist syntax, rebuilds the app, checks the version/icon/resource contract, verifies the signature, and runs `tests/test_effort_control.py` with the installed Python Playwright package.

## Runtime contract

- Each tab gets a `WKWebViewConfiguration` containing `Resources/EffortControl.js` as a document-end, main-frame-only `WKUserScript`.
- Swift reads `founder-off.png`, `founder-high.png`, and `founder-max.png` from the app bundle, converts them to PNG data URIs, and replaces the script placeholders before injection.
- The script is inert until `[data-slot="conversation.input.right"]` and `button[aria-label^="Select model"]` exist. It inserts the accessible range rail immediately before that native model trigger.
- Applying a value opens the native model menu, opens its `Effort` row, and clicks the exact `button[role="menuitemradio"]` named `Off`, `High`, or `Max`. No fetch, WebSocket, or fake backend state is used.
- The rail reconciles from the native trigger's `reasoning effort Off|High|Max` accessibility label, with a mutation observer and periodic check. Failed application reverts and exposes `Unavailable` through the tooltip and `aria-valuetext`.
- Founder treatment is limited to a marked New Session hero (`data-dsh-view="new-session"`, equivalent DSH new-session markers, or a root/new-session route without conversation markers). Active conversation views remove it. Off/High force a temporary light theme and Max a temporary dark theme only while the hero is present; the original theme attributes/classes are restored on exit or teardown.
- The native profile store, tab state, and profile URLs remain unchanged. The shell does not read or modify `~/.dsh/settings.yaml`.
