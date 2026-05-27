#!/usr/bin/env bash
set -euo pipefail

LABEL="${LABEL:-com.github.Coco422.doubao-voice-wetype-agent}"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_DST" >/dev/null 2>&1 || true
rm -f "$PLIST_DST"

cat <<MSG
Uninstalled LaunchAgent:
  $PLIST_DST

Binaries are intentionally left in place:
  $HOME/.local/bin/doubao-voice-wetype-agent
  $HOME/.local/bin/im-switch
MSG
