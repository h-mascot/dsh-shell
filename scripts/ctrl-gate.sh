#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/DSH Shell.app"
PLIST="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"

# Resolve tools through PATH with Homebrew fallbacks so the gate runs on any
# macOS box with node/python3 installed, not just this machine (P2 fix).
NODE_BIN="$(command -v node || true)"
[ -z "$NODE_BIN" ] && for _p in /opt/homebrew/bin /usr/local/bin; do
  [ -x "$_p/node" ] && NODE_BIN="$_p/node" && break
done
PY_BIN="$(command -v python3 || true)"
[ -z "$PY_BIN" ] && for _p in /opt/homebrew/bin /usr/local/bin; do
  [ -x "$_p/python3" ] && PY_BIN="$_p/python3" && break
done
if [ -z "$NODE_BIN" ] || [ -z "$PY_BIN" ]; then
  print -u2 "[gate] node and python3 are required (PATH or /opt/homebrew/bin, /usr/local/bin)"
  exit 2
fi

print "[gate] JavaScript syntax"
"$NODE_BIN" --check "$ROOT/Resources/EffortControl.js"

print "[gate] source plist"
/usr/bin/plutil -lint "$ROOT/Info.plist"

print "[gate] build"
"$ROOT/scripts/build-app.sh"

print "[gate] bundle resources"
for resource in \
  DeepSeek.icns \
  app-icon-1024.png \
  deepseek-favicon.svg \
  deepseek-icon.svg \
  founder-off.png \
  founder-high.png \
  founder-max.png \
  EffortControl.js; do
  test -f "$RESOURCES/$resource"
done

print "[gate] built plist"
/usr/bin/plutil -lint "$PLIST"
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$PLIST")" == "DeepSeek.icns" ]]
[[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$PLIST")" == "3.1.1" ]]
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" == "3.1.1" ]]
[[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$PLIST")" == "dsh-shell" ]]

print "[gate] code signature"
/usr/bin/codesign --verify --deep --strict "$APP"

print "[gate] bounded DOM interaction"
"$PY_BIN" "$ROOT/tests/test_effort_control.py" --script "$ROOT/Resources/EffortControl.js"

print "CTRL gate passed: $APP"
