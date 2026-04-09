#!/usr/bin/env bash
# Claude Code notification + iTerm2 tab-rename hook
# Events: Notification, Stop, SessionStart, PreToolUse, PostToolUse
#
# Requires: jq, terminal-notifier (brew install terminal-notifier)

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

NOTIFIER=$(command -v terminal-notifier 2>/dev/null || echo "/opt/homebrew/bin/terminal-notifier")

# ── iTerm2 tab title ───────────────────────────────────────────────────────
# Sets user.tabTitle on the CURRENT iTerm2 session.
# Requires iTerm2 profile Title=128 with Custom Tab Title = \(user.tabTitle)
# so it renders our variable and ignores the job name entirely.
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

# ── Notification attributed to iTerm2 (not Script Editor) ─────────────────
# terminal-notifier with -sender com.googlecode.iterm2 makes the notification
# show the iTerm2 icon. Clicking it activates iTerm2 directly.
notify_iterm() {
  local title="$1"
  local msg="$2"
  local sound="${3:-Glass}"
  "$NOTIFIER" \
    -title "$title" \
    -message "$msg" \
    -sound "$sound" \
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
    ;;

  Stop)
    set_tab_title "${PROJECT} [waiting]"
    notify_iterm "Claude — ${PROJECT}" "Finished. Your input is needed." "Purr"
    ;;

  Notification)
    NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "idle"')
    case "$NOTIF_TYPE" in
      permission_prompt)
        set_tab_title "${PROJECT} [AUTH NEEDED]"
        notify_iterm "Claude — ${PROJECT}" "⚠ Permission request waiting for your answer." "Glass"
        ;;
      *)
        notify_iterm "Claude — ${PROJECT}" "Needs your attention (${NOTIF_TYPE})." "Glass"
        ;;
    esac
    ;;

esac

exit 0
