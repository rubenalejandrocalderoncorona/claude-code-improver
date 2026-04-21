#!/usr/bin/env bash
# toggle-approve-all.sh
# Toggles Approve-All mode for Claude Code permission notifications.
# When the flag is set every PermissionRequest is auto-approved silently.
#
# Usage: bash toggle-approve-all.sh
# Bind to a global shortcut via the Claude Approve-All.workflow service.

FLAG="$HOME/.claude/hooks/approve-all.flag"
ALERTER="/opt/homebrew/bin/alerter"

if [ -f "$FLAG" ]; then
  rm -f "$FLAG"
  afplay /System/Library/Sounds/Funk.aiff 2>/dev/null || true
  "$ALERTER" \
    --title "Claude Approve-All" \
    --message "OFF — permission prompts restored" \
    --close-label "OK" \
    --sender com.apple.scripteditor2 \
    --timeout 3 \
    2>/dev/null &
else
  touch "$FLAG"
  afplay /System/Library/Sounds/Blow.aiff 2>/dev/null || true
  "$ALERTER" \
    --title "Claude Approve-All" \
    --message "ON — all permissions will be auto-approved" \
    --close-label "OK" \
    --sender com.apple.scripteditor2 \
    --timeout 3 \
    2>/dev/null &
fi
