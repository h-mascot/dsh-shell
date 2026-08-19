#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/.build"
APP="$BUILD_ROOT/DSH Shell.app"
STAMP="$(date +%Y%m%d-%H%M%S)"
STAGING_APP="$BUILD_ROOT/.DSH Shell.app.staging.$$.$STAMP"
PREVIOUS_APP="$BUILD_ROOT/.previous-DSH Shell.app.$STAMP.$$"
CONTENTS="$STAGING_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

preserve_staging_on_failure() {
  local exit_code=$?
  if (( exit_code != 0 )) && [[ -d "$STAGING_APP" ]]; then
    print -u2 "Build failed; preserving staging app at: $STAGING_APP"
  fi
}
trap preserve_staging_on_failure EXIT

if [[ ! -f "$ROOT/main.swift" || ! -f "$ROOT/EffortControlScript.swift" ]]; then
  print -u2 "missing Swift sources"
  exit 1
fi

mkdir -p "$BUILD_ROOT"
mkdir -p "$MACOS" "$RESOURCES"
mkdir -p "$BUILD_ROOT/ModuleCache"

/usr/bin/swiftc \
  "$ROOT/main.swift" \
  "$ROOT/EffortControlScript.swift" \
  -module-cache-path "$ROOT/.build/ModuleCache" \
  -framework Cocoa \
  -framework WebKit \
  -o "$MACOS/dsh-shell"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp -R "$ROOT/Resources/." "$RESOURCES/"
chmod +x "$MACOS/dsh-shell"

/usr/bin/codesign --force --deep --sign - "$STAGING_APP"

previous_moved=0
if [[ -e "$APP" || -L "$APP" ]]; then
  mv "$APP" "$PREVIOUS_APP"
  previous_moved=1
fi

if ! mv "$STAGING_APP" "$APP"; then
  print -u2 "Could not install the new app bundle at: $APP"
  if (( previous_moved )); then
    if ! mv "$PREVIOUS_APP" "$APP"; then
      print -u2 "Could not restore the previous app bundle at: $APP"
    fi
  fi
  exit 1
fi

print "Built: $APP"
print "$APP"
