#!/usr/bin/env bash
# claude-alert-dispatcher.sh  v2.0.0
# Called by claude-notify.sh to show an alerter notification and handle clicks.
#
# Usage:
#   permission <tty> <group> <title> <subtitle> <message>
#   stop       <tty> <group> <title> <subtitle> <message>
#   question   <tty> <group> <title> <subtitle> <question_text> <options_json>
#
# permission mode (synchronous):
#   If approve-all.flag exists → immediately prints allow JSON and exits.
#   Otherwise shows alerter, blocks, then prints a JSON PermissionRequest
#   decision to stdout so claude-notify.sh can forward it to Claude Code.
#   Uses com.apple.scripteditor2 as sender so clicking Approve does NOT
#   bring iTerm2 forward — the user stays in their current app.
#
# stop mode (runs in background):
#   Shows alerter with Show/Ignore. "Show" focuses the iTerm2 session.
#   Uses com.googlecode.iterm2 as sender (intentional: we want iTerm2 to
#   come forward when the user explicitly clicks Show).
#
# question mode (synchronous):
#   Shows alerter with each answer option as a button + "Show" button.
#   Clicking an option prints a PreToolUse updatedInput JSON decision.
#   Clicking Show focuses the session (no JSON — Claude shows its own dialog).
#   Uses com.apple.scripteditor2 so clicking an answer doesn't open iTerm2.

MODE="$1"
TTY="$2"
GROUP="$3"
TITLE="$4"
SUBTITLE="$5"
MSG="$6"          # message for permission/stop; question_text for question mode
OPTIONS_JSON="$7" # JSON array of option labels, only used in question mode

ALERTER="/opt/homebrew/bin/alerter"
APPROVE_ALL_FLAG="$HOME/.claude/hooks/approve-all.flag"

# ── Helpers ────────────────────────────────────────────────────────────────

# Focus the iTerm2 session matching TTY (selects the exact tab, not just the session)
focus_session() {
  osascript 2>/dev/null <<OSASCRIPT || true
    tell application "iTerm2"
      repeat with w in every window
        repeat with t in every tab of w
          repeat with s in every session of t
            if tty of s contains "$TTY" then
              tell w to select t
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

# ── Permission mode ────────────────────────────────────────────────────────
if [ "$MODE" = "permission" ]; then

  # Approve-all shortcut: skip the notification entirely.
  if [ -f "$APPROVE_ALL_FLAG" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
  fi

  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$MSG" \
    --actions "Approve" \
    --close-label "Dismiss" \
    --sender com.apple.scripteditor2 \
    --group "$GROUP" \
    --sound "Glass" \
    2>/dev/null)

  case "$RESULT" in
    "Approve")
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      ;;
    "@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
    *)
      # Dismiss / timeout → deny
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
      ;;
  esac

# ── Stop mode ──────────────────────────────────────────────────────────────
elif [ "$MODE" = "stop" ]; then

  # Keep com.googlecode.iterm2 here — we WANT iTerm2 to come forward on Show.
  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$MSG" \
    --actions "Show" \
    --close-label "Ignore" \
    --sender com.googlecode.iterm2 \
    --group "$GROUP" \
    --sound "Purr" \
    2>/dev/null)

  case "$RESULT" in
    "Show"|"@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
  esac

# ── Question mode ──────────────────────────────────────────────────────────
elif [ "$MODE" = "question" ]; then

  QUESTION_TEXT="$MSG"

  # Build comma-separated actions list from options JSON array.
  # Limit to 3 options to stay within alerter's reliable button range.
  # Always append "Show" so the user can switch to the terminal instead.
  ACTIONS=$(echo "$OPTIONS_JSON" | jq -r '
    [ .[:3][] ] | map(.label) | join(",")
  ' 2>/dev/null)
  [ -n "$ACTIONS" ] && ACTIONS="${ACTIONS},Show" || ACTIONS="Show"

  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$QUESTION_TEXT" \
    --actions "$ACTIONS" \
    --close-label "Dismiss" \
    --sender com.apple.scripteditor2 \
    --group "$GROUP" \
    --sound "Glass" \
    2>/dev/null)

  case "$RESULT" in
    "Show"|"@CONTENTCLICKED"|"@TITLECLICKED")
      # Let Claude Code show its own dialog; just focus the window.
      focus_session
      ;;
    "@CLOSED"|"Dismiss"|"")
      # User dismissed — let Claude Code show its own dialog (no JSON output).
      ;;
    *)
      # User clicked one of the option buttons — answer the question.
      # Build the full updatedInput JSON with the chosen answer.
      # OPTIONS_JSON is an array of {label: "..."} objects.
      CHOSEN="$RESULT"
      # Re-read original questions JSON from the tool_input passed as OPTIONS_JSON.
      # We stored the raw tool_input.questions JSON in OPTIONS_JSON (set by claude-notify.sh).
      ANSWER_JSON=$(jq -n \
        --argjson questions "$OPTIONS_JSON" \
        --arg qtext "$QUESTION_TEXT" \
        --arg answer "$CHOSEN" \
        '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: {
              questions: $questions,
              answers: { ($qtext): $answer }
            }
          }
        }')
      printf '%s' "$ANSWER_JSON"
      ;;
  esac

fi
