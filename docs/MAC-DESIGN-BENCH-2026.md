# MAC-DESIGN-BENCH-2026 — DSH Shell v3 Design Gate

Receipt-grade rubric distilled from Apple HIG (macOS 26 / Liquid Glass era, "Materials", "Layout", macOS section), the 2026 Mac-citizen checklists, and platform conventions for tabbed document windows. There is no public "Mac Design Standard 2026" benchmark; this codifies one so the pass is auditable, not vibes.

Score = axes with PASS receipts. Ship gate: **5/5**. Every PASS cites a receipt artifact under `~/.hermes/output/dsh-shell-v3/`.

## Axis 1 — Platform conventions (Mac citizen)
- Standard app menu order: About / Settings… ⌘, / Hide / Quit ⌘Q
- File: New Tab ⌘T, Close Tab ⌘W, Open Location… ⌘L (maps the Safari address-bar convention to the hidden location field)
- Window menu: Minimize ⌘M, Zoom, Rename Tab ⌘R, Show Next/Previous Tab ⌃⇥/⌃⇧⇥, Select Tab ⌘1..⌘9
- Traffic lights intact; standard About panel; window restoration across relaunch
- ctrl-gate still passes (v2 web contract regression)
Receipts: `bench-axis1.json` (AX menu walk + gate log)

## Axis 2 — Liquid Glass correctness
- Glass appears ONLY in the control layer: the tab strip pills (+ new-tab pill). No glass in the content layer.
- `NSGlassEffectView.Style.regular` (text-bearing controls; clear is for media overlays per HIG)
- Content scrolls/peeks beneath the strip; strip passes clicks through except on pills; window draggable by strip background
- Graceful degradation: pre-26 or Reduce Transparency → `NSVisualEffectView` fallback, no layout break
Receipts: `bench-axis2.json` (AX structure: strip is a sibling layer over content, not a sibling pane) + `glass-strip.png` + fallback screenshot or code-path note

## Axis 3 — Minimalist chrome
- Main window shows: traffic lights, tab strip. Nothing else. No environment picker, no address bar, no toolbar.
- Window title is the active tab's name only (no "DSH Shell —" prefix); titlebar transparent/hidden
- Environment profiles + URL field live in Settings (⌘,) and Open Location (⌘L)
Receipts: `bench-axis3.json` (AX: zero text fields in main window chrome; window.toolbar == nil; title string exact)

## Axis 4 — Naming & legibility
- Tabs user-nameable: Rename Tab ⌘R (sheet), double-click pill, context menu → all reach the same rename sheet
- Names persist across relaunch (v3 tab state format, migrates v2 URL-only state)
- Fallback labels: profile name for matching origin, else host; page title never overrides a custom name
- System font 13pt; active tab .semibold labelColor, inactive .regular secondaryLabelColor; truncating tail; SF Symbols for +/×
Receipts: `bench-axis4.json` (AX rename flow + relaunch persistence proof) + `tabs-named.png`

## Axis 5 — Accessibility & robustness
- Every tab control reachable by keyboard (⌘1..⌘9, ⌃⇥, ⌘R, ⌘T, ⌘W, ⌘L, ⌘,)
- AX roles: pills expose AXButton with meaningful titles ("Tab <name>", "New Tab"); rename sheet exposes text field + default button; menus carry key equivalents
- No contrast hazards: system semantic colors only; no custom low-contrast grays
- Min window size: strip never clips pills below usability (min pill width honored, strip scrolls/compresses)
Receipts: `bench-axis5.json` (full AX dump assertions incl. key equivalents)
