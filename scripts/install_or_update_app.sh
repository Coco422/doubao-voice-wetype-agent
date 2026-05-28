#!/usr/bin/env bash
set -euo pipefail

LABEL="${LABEL:-com.github.Coco422.doubao-voice-wetype-agent}"
APP_NAME="${APP_NAME:-Doubao Voice WeType Agent.app}"
APP_INSTALL_DIR="${APP_INSTALL_DIR:-$HOME/Applications}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_NAME="com.github.Coco422.doubao-voice-wetype-agent.plist.template"

find_first_existing() {
  for candidate in "$@"; do
    if [ -e "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&#]/\\&/g'
}

APP_SRC="${APP_SRC:-}"
if [ -z "$APP_SRC" ]; then
  APP_SRC="$(find_first_existing \
    "$SCRIPT_DIR/$APP_NAME" \
    "$SCRIPT_DIR/../dist/$APP_NAME" \
    "$SCRIPT_DIR/../$APP_NAME" \
    || true)"
fi

PLIST_SRC="${PLIST_SRC:-}"
if [ -z "$PLIST_SRC" ]; then
  PLIST_SRC="$(find_first_existing \
    "$SCRIPT_DIR/launchd/$PLIST_NAME" \
    "$SCRIPT_DIR/../launchd/$PLIST_NAME" \
    || true)"
fi

APP_DST="$APP_INSTALL_DIR/$APP_NAME"
PROGRAM="$APP_DST/Contents/MacOS/doubao-voice-wetype-agent"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -d "$APP_SRC" ]; then
  echo "App bundle not found: $APP_SRC" >&2
  exit 1
fi

if [ ! -f "$PLIST_SRC" ]; then
  echo "LaunchAgent template not found: $PLIST_SRC" >&2
  exit 1
fi

mkdir -p "$APP_INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
ditto "$APP_SRC" "$APP_DST"
chmod +x "$PROGRAM"

if [ -f "$APP_DST/Contents/Resources/im-switch" ]; then
  chmod +x "$APP_DST/Contents/Resources/im-switch"
fi

sed \
  -e "s#__HOME__#$(escape_sed_replacement "$HOME")#g" \
  -e "s#__LABEL__#$(escape_sed_replacement "$LABEL")#g" \
  -e "s#__PROGRAM__#$(escape_sed_replacement "$PROGRAM")#g" \
  "$PLIST_SRC" > "$PLIST_DST"

launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

cat <<MSG
Installed or updated Doubao Voice WeType Agent.

App:
  $APP_DST

Grant permissions to this executable on first install:
  $PROGRAM

Required permissions:
  System Settings -> Privacy & Security -> Accessibility
  System Settings -> Privacy & Security -> Input Monitoring

After granting both permissions, click the menu bar item "豆 !" and choose
"Retry permissions/tap". It should become "豆 OK".

Updates keep the same app path and LaunchAgent label. To minimize permission churn,
sign release builds with the same codesigning identity each time.
MSG
