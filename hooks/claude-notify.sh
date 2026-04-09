#!/usr/bin/env bash
# Claude Code notification + iTerm2 tab-rename hook
# Events: PermissionRequest, Stop, SessionStart, PreToolUse, PostToolUse
#
# Uses iTerm2's native OSC 9 notification escape — clicking "Show" in the
# notification redirects to the exact session that needs attention.
# Requires: jq

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# ── Find the TTY of the Claude process that spawned this hook ──────────────
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

# ── Send iTerm2 native notification via OSC 9 ─────────────────────────────
# OSC 9 causes iTerm2 to post a native notification attributed to itself.
# Clicking "Show" in the banner focuses the exact session that sent it.
# Separate title from body with a newline — iTerm2 renders the first line bold.
notify_iterm() {
  local msg="$1"
  [ -z "$SESSION_TTY" ] && return
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      repeat with w in every window
        repeat with t in every tab of w
          repeat with s in every session of t
            if tty of s contains "$SESSION_TTY" then
              set esc to ASCII character 27
              set bel to ASCII character 7
              write text (esc & "]9;$msg" & bel)
              return
            end if
          end repeat
        end repeat
      end repeat
    end tell
OSASCRIPT
}

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
    # Clear any stale terminal-notifier banners from before
    "$NOTIFIER" -remove "claude-${PROJECT}" 2>/dev/null || true
    ;;

  Stop)
    set_tab_title "${PROJECT} [waiting]"
    notify_iterm "Claude — ${PROJECT}: session finished. Your input is needed."
    ;;

  PermissionRequest)
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
    CMD=$(echo "$INPUT" | jq -r '
      if .tool_name == "Bash" then .tool_input.command // ""
      elif .tool_name == "Write" or .tool_name == "Edit" then .tool_input.file_path // ""
      else (.tool_input | to_entries | map("\(.key): \(.value)") | join(", "))
      end' | cut -c1-80)
    set_tab_title "${PROJECT} [AUTH NEEDED]"
    notify_iterm "Claude — ${PROJECT}: permission needed for ${TOOL}: ${CMD}"
    ;;

esac

exit 0
