#!/usr/bin/env bash
# Claude Code notification + iTerm2 tab-rename hook
# Events: PermissionRequest, Stop, SessionStart, PreToolUse, PostToolUse
#
# Requires: jq, terminal-notifier (brew install terminal-notifier)

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# ── iTerm2 tab title ───────────────────────────────────────────────────────
set_tab_title() {
  local title="$1"
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      tell current window
        tell current tab
          tell current session
            set variable named "user.tabTitle" to "$title"
          end tell
        end tell
      end tell
    end tell
OSASCRIPT
}

# ── Single notification — replaces previous one with same group ID ─────────
# -group ensures only ONE notification per project is ever shown (no stacking).
# -activate + clicking the banner brings iTerm2 to front.
notify_iterm() {
  local title="$1"
  local subtitle="$2"
  local msg="$3"
  local sound="${4:-Glass}"
  "$NOTIFIER" \
    -title "$title" \
    -subtitle "$subtitle" \
    -message "$msg" \
    -sound "$sound" \
    -group "claude-${PROJECT}" \
    -activate com.googlecode.iterm2 \
    -sender com.googlecode.iterm2 \
    2>/dev/null || true
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
    # Remove any stale permission notification once the tool ran
    "$NOTIFIER" -remove "claude-${PROJECT}" 2>/dev/null || true
    ;;

  Stop)
    set_tab_title "${PROJECT} [waiting]"
    notify_iterm \
      "Claude — ${PROJECT}" \
      "Session finished" \
      "Claude thinking session finished. Your input is needed." \
      "Purr"
    ;;

  PermissionRequest)
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
    CMD=$(echo "$INPUT" | jq -r '
      if .tool_name == "Bash" then .tool_input.command // ""
      elif .tool_name == "Write" or .tool_name == "Edit" then .tool_input.file_path // ""
      else (.tool_input | to_entries | map("\(.key): \(.value)") | join(", "))
      end' | cut -c1-80)
    set_tab_title "${PROJECT} [AUTH NEEDED]"
    notify_iterm \
      "Claude — ${PROJECT}" \
      "Requires permission: ${TOOL}" \
      "${CMD}" \
      "Glass"
    ;;

esac

exit 0
