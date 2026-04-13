#!/usr/bin/env bash
# claude-alert-dispatcher.sh
# Called by claude-notify.sh in background to show an alerter notification
# and handle the user's button click.
#
# Usage:
#   claude-alert-dispatcher.sh permission <tty> <group> <title> <subtitle> <message>
#   claude-alert-dispatcher.sh stop       <tty> <group> <title> <subtitle> <message>

MODE="$1"
TTY="$2"
GROUP="$3"
TITLE="$4"
SUBTITLE="$5"
MSG="$6"

ALERTER="/opt/homebrew/bin/alerter"

focus_session() {
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      repeat with w in every window
        repeat with t in every tab of w
          repeat with s in every session of t
            if tty of s contains "$TTY" then
              select s
              activate
              return
            end if
          end repeat
        end repeat
      end repeat
    end tell
OSASCRIPT
}

send_approve() {
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      repeat with w in every window
        repeat with t in every tab of w
          repeat with s in every session of t
            if tty of s contains "$TTY" then
              write text "y"
              return
            end if
          end repeat
        end repeat
      end repeat
    end tell
OSASCRIPT
}

if [ "$MODE" = "permission" ]; then
  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$MSG" \
    --actions "Approve" \
    --close-label "Dismiss" \
    --sender com.googlecode.iterm2 \
    --group "$GROUP" \
    --sound "Glass" \
    2>/dev/null)

  case "$RESULT" in
    "@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
    "Approve")
      send_approve
      ;;
  esac

elif [ "$MODE" = "stop" ]; then
  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$MSG" \
    --close-label "Dismiss" \
    --sender com.googlecode.iterm2 \
    --group "$GROUP" \
    --sound "Purr" \
    2>/dev/null)

  case "$RESULT" in
    "@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
  esac
fi
