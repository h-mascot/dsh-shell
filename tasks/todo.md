# DSH Shell v2 effort dial

- [x] Inspect the v1 shell and define the native injection/runtime contract.
- [x] Add the v2 icon/version and bundled effort-control resources.
- [x] Wire `WKUserScript` injection into every tab and fix configured web-view construction.
- [x] Add the reproducible app build and fail-closed CTRL gate.
- [x] Add the Playwright DOM fixture for effort selection, synchronization, hero treatment, and page errors.
- [x] Run non-browser syntax, build, resource, plist, signature, and diff checks.
- [x] Run the bounded Playwright fixture from a normal macOS shell; the parent shell completed the full fail-closed gate.
- [x] Complete Jeff Dean architecture review and Luke W/Ryan Singer UI review.

## Review results

✅ Jeff Dean review: the Swift bundle-resource helper is isolated from the AppKit delegate; every tab now receives the configured `WKUserScript` before `WKWebView` construction; the JS uses a bounded native-menu adapter with serialized selection, observer reconciliation, teardown, and no network interception. The render-token repair prevents stale crossfade frames from winning.

✅ Selector safety review: hero targeting retains the explicit `data-*` markers and bounded route/main fallback without accepting a global sidebar `aria-label` match; the fixture places a sidebar decoy before the main target and asserts the main container owns the hero marker.

✅ Luke W + Ryan Singer review: the rail is compact and responsive, has no permanent labels, exposes native range semantics and keyboard controls, uses focus/hover/change tooltips, scopes DOM/CSS to the DSH composer contract, preserves pointer events, and removes hero/theme treatment on active conversations or teardown. Max uses the supplied dark treatment and gold composer/send accents.

## Verification receipts

- `node --check Resources/EffortControl.js` — PASS.
- `/bin/zsh -n scripts/build-app.sh` — PASS.
- `plutil -lint Info.plist` — PASS.
- `./scripts/build-app.sh` — PASS; staged and installed `.build/DSH Shell.app`, preserving the prior bundle under `.build/.previous-DSH Shell.app.<timestamp>.<pid>`, with existing Swift deprecation warnings for v1 toolbar sizing APIs.
- Built resource/plist checks and `codesign --verify --deep --strict '.build/DSH Shell.app'` — PASS.
- `test -f codedb.snapshot` — PASS; file preserved.
- `git diff --check` — PASS.
- `/opt/homebrew/bin/python3 tests/test_effort_control.py --script Resources/EffortControl.js` — EXIT 1 before the fixture starts under the Codex seatbelt because Playwright Chromium cannot launch there.
- `./scripts/ctrl-gate.sh` under the Codex seatbelt — EXIT 1 at bounded Playwright launch after JavaScript, plist, build, resource, and signature stages passed.
- Parent normal-shell `./scripts/ctrl-gate.sh` — PASS end to end: `DOM fixture passed`; `CTRL gate passed: /Users/enterprise/Code/dsh-shell/.build/DSH Shell.app`.
