#!/usr/bin/env bash
# Claude Code notification + iTerm2 tab-rename hook  v1.0.0
# Events: PermissionRequest, Stop, SessionStart, PreToolUse, PostToolUse
#
# Permission notification: [Approve] button sends "y" to Claude, clicking body focuses session
# Stop notification:       clicking body focuses session
# Requires: jq, alerter  (install via install-claude-hooks.sh)

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT"   | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

ALERTER="/opt/homebrew/bin/alerter"
DISPATCHER="$(dirname "$0")/claude-alert-dispatcher.sh"

# ── Find TTY of the Claude process that spawned this hook ─────────────────
find_tty() {
  local pid=$$
  while [ "$pid" -gt 1 ]; do
    local tty
    tty=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d ' ')
    if [ -n "$tty" ] && [ "$tty" != "??" ]; then
      echo "$tty"
      return
    fi
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
  done
}

SESSION_TTY=$(find_tty)

# ── iTerm2 tab title (targeted to this session by TTY) ────────────────────
set_tab_title() {
  local title="$1"
  [ -z "$SESSION_TTY" ] && return
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      repeat with w in every window
        repeat with t in every tab of w
          repeat with s in every session of t
            if tty of s contains "$SESSION_TTY" then
              set variable named "user.tabTitle" to "$title"
              return
            end if
          end repeat
        end repeat
      end repeat
    end tell
OSASCRIPT
}

# ── Event dispatch ─────────────────────────────────────────────────────────
case "$EVENT" in

  SessionStart)
    set_tab_title "${PROJECT} [claude]"
    ;;

  PreToolUse)
    set_tab_title "${PROJECT} [running]"
    ;;

  PostToolUse)
    set_tab_title "${PROJECT} [claude]"
    # Clear any stale permission alert
    "$ALERTER" --remove "claude-perm-${PROJECT}" 2>/dev/null || true
    ;;

  Stop)
    set_tab_title "${PROJECT} [waiting]"
    # Launch dispatcher in background — it blocks on alerter until user acts
    bash "$DISPATCHER" stop \
      "$SESSION_TTY" \
      "claude-stop-${PROJECT}" \
      "Claude — ${PROJECT}" \
      "Session finished" \
      "Claude has finished thinking. Your input is needed to continue." \
      &
    disown
    ;;

  PermissionRequest)
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
    CMD=$(echo "$INPUT" | jq -r '
      if .tool_name == "Bash" then .tool_input.command // ""
      elif .tool_name == "Write" or .tool_name == "Edit" then .tool_input.file_path // ""
      else (.tool_input | to_entries | map("\(.key): \(.value)") | join(", "))
      end' | cut -c1-100)
    set_tab_title "${PROJECT} [AUTH NEEDED]"
    # Launch dispatcher in background — blocks until Approve or Dismiss
    bash "$DISPATCHER" permission \
      "$SESSION_TTY" \
      "claude-perm-${PROJECT}" \
      "Claude — ${PROJECT}" \
      "Permission required: ${TOOL}" \
      "${CMD}" \
      &
    disown
    ;;

esac

exit 0
