#!/usr/bin/env bash
# claude-alert-dispatcher.sh  v2.1.0
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
#   Uses com.apple.Terminal as sender — notification permission is pre-granted
#   and clicking Approve does NOT bring Terminal forward (verified).
#
# stop mode (runs in background):
#   Shows alerter with Show/Ignore. "Show" focuses the iTerm2 session.
#   Uses com.googlecode.iterm2 as sender (intentional: we want iTerm2 to
#   come forward when the user explicitly clicks Show).
#   Deduplication: if an alerter for this group is already running, exits
#   immediately (the existing process will handle the notification).
#
# question mode (synchronous):
#   Shows alerter with each answer option as a button + "Show" button.
#   Clicking an option prints a PreToolUse updatedInput JSON decision.
#   Clicking Show focuses the session (no JSON — Claude shows its own dialog).
#   Uses com.apple.Terminal so clicking an answer doesn't open iTerm2.

MODE="$1"
TTY="$2"
GROUP="$3"
TITLE="$4"
SUBTITLE="$5"
MSG="$6"          # message for permission/stop; question_text for question mode
OPTIONS_JSON="$7" # JSON array of option labels, only used in question mode

ALERTER="/opt/homebrew/bin/alerter"
APPROVE_ALL_FLAG="$HOME/.claude/hooks/approve-all.flag"
LOCKS_DIR="$HOME/.claude/hooks/locks"

# ── Helpers ────────────────────────────────────────────────────────────────

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

  if [ -f "$APPROVE_ALL_FLAG" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
  fi

  # Register a FIFO so approve-all-pending.sh can bulk-approve waiting prompts.
  PENDING_DIR="$HOME/.claude/hooks/pending"
  mkdir -p "$PENDING_DIR"

  # Clean up FIFOs whose owner process is gone.
  for stale in "$PENDING_DIR"/*; do
    [ -p "$stale" ] || continue
    owner=$(basename "$stale")
    kill -0 "$owner" 2>/dev/null || rm -f "$stale"
  done

  FIFO="$PENDING_DIR/$$"
  mkfifo "$FIFO"
  trap 'rm -f "$FIFO"' EXIT

  # alerter blocks until user acts; run it in background writing to the FIFO.
  # We open the FIFO for writing in a subshell first so `cat` below doesn't
  # block on the open — the subshell holds the write-end open while alerter runs.
  (
    exec 3>"$FIFO"
    "$ALERTER" \
      --title "$TITLE" \
      --subtitle "$SUBTITLE" \
      --message "$MSG" \
      --actions "Approve" \
      --close-label "Dismiss" \
      --sender com.apple.Terminal \
      --group "$GROUP" \
      --sound "Glass" \
      --timeout 120 \
      2>/dev/null >&3
    exec 3>&-
  ) &
  ALERTER_SUBSHELL=$!

  RESULT=$(cat "$FIFO")
  kill "$ALERTER_SUBSHELL" 2>/dev/null || true

  case "$RESULT" in
    "Approve")
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      ;;
    "@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      # No JSON output → Claude Code shows its own built-in dialog.
      ;;
    *)
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
      ;;
  esac

# ── Stop mode ──────────────────────────────────────────────────────────────
elif [ "$MODE" = "stop" ]; then

  # Deduplication: only one Stop alerter per group at a time.
  # If the lock file exists and its PID is still alive, exit immediately —
  # the running process will handle (and replace) the notification.
  mkdir -p "$LOCKS_DIR"
  LOCKFILE="$LOCKS_DIR/stop-${GROUP}"
  if [ -f "$LOCKFILE" ]; then
    existing_pid=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      exit 0
    fi
  fi
  echo $$ > "$LOCKFILE"
  trap 'rm -f "$LOCKFILE"' EXIT

  RESULT=$("$ALERTER" \
    --title "$TITLE" \
    --subtitle "$SUBTITLE" \
    --message "$MSG" \
    --actions "Show" \
    --close-label "Ignore" \
    --sender com.googlecode.iterm2 \
    --group "$GROUP" \
    --sound "Purr" \
    --timeout 30 \
    2>/dev/null)

  case "$RESULT" in
    "Show"|"@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
  esac

# ── Question mode ──────────────────────────────────────────────────────────
elif [ "$MODE" = "question" ]; then

  QUESTION_TEXT="$MSG"

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
    --sender com.apple.Terminal \
    --group "$GROUP" \
    --sound "Glass" \
    2>/dev/null)

  case "$RESULT" in
    "Show"|"@CONTENTCLICKED"|"@TITLECLICKED")
      focus_session
      ;;
    "@CLOSED"|"Dismiss"|"")
      ;;
    *)
      CHOSEN="$RESULT"
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
