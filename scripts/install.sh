#!/usr/bin/env bash
set -euo pipefail

LABEL="${LABEL:-com.github.Coco422.doubao-voice-wetype-agent}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_SRC="$ROOT/launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
PROGRAM="$HOME/.local/bin/doubao-voice-wetype-agent"

swift build -c release --package-path "$ROOT"

install -d "$HOME/.local/bin"
install -m 755 "$ROOT/.build/release/doubao-voice-wetype-agent" "$HOME/.local/bin/doubao-voice-wetype-agent"
install -m 755 "$ROOT/.build/release/im-switch" "$HOME/.local/bin/im-switch"

install -d "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed \
  -e "s#__HOME__#$HOME#g" \
  -e "s#__LABEL__#$LABEL#g" \
  -e "s#__PROGRAM__#$PROGRAM#g" \
  "$PLIST_SRC" > "$PLIST_DST"

launchctl bootout "gui/$(id -u)" "$PLIST_DST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

cat <<MSG
Installed doubao-voice-wetype-agent.

Grant these permissions to:
  $HOME/.local/bin/doubao-voice-wetype-agent

Required permissions:
  System Settings -> Privacy & Security -> Accessibility
  System Settings -> Privacy & Security -> Input Monitoring

After granting permissions, use the menu bar item or run:
  launchctl kickstart -k gui/\$(id -u)/$LABEL
MSG
