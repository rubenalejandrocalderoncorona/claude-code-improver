#!/usr/bin/env bash
# claude-alert-dispatcher.sh  v3.0.0
# Called by claude-notify.sh to show an alerter notification and handle clicks.
#
# Usage:
#   permission <tty> <group> <title> <subtitle> <message>
#   stop       <tty> <group> <title> <subtitle> <message> <cwd>
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
#   Shows a ClaudeNotifier.app banner (signed macOS app — real banners).
#   Clicking the notification runs focus-window for VS Code or open -a iTerm
#   for iTerm2. ClaudeNotifier handles dedup via -group.
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
OPTIONS_JSON="$7" # JSON array of option labels (question mode) or CWD (stop mode)

ALERTER="/opt/homebrew/bin/alerter"
APPROVE_ALL_FLAG="$HOME/.claude/hooks/approve-all.flag"
HOOK_DIR="$HOME/.claude/hooks"
CLAUDE_NOTIFICATIONS="$HOOK_DIR/claude-notifications"
CLAUDE_NOTIFIER_APP="$HOOK_DIR/ClaudeNotifier.app"

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
    "@TIMEOUT")
      # Timeout elapsed with no user action → deny so Claude doesn't hang forever.
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
      ;;
    *)
      # Dismissed / swiped away / close button / notification center cleared:
      # output nothing — Claude Code keeps waiting and will show its own dialog.
      ;;
  esac

# ── Stop mode ──────────────────────────────────────────────────────────────
elif [ "$MODE" = "stop" ]; then

  CWD="$OPTIONS_JSON"   # 7th arg is CWD in stop mode

  # Build the click-to-focus command for ClaudeNotifier.app's -execute flag.
  # Detect which terminal owns this session via env vars inherited by the hook.
  build_focus_cmd() {
    # VS Code sets TERM_PROGRAM=vscode; Cursor sets it to cursor
    case "${TERM_PROGRAM:-}" in
      vscode)  echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.microsoft.VSCode' '$CWD'" ; return ;;
      cursor)  echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.todesktop.230313mzl4w4u92' '$CWD'" ; return ;;
    esac
    # iTerm2 sets ITERM_SESSION_ID — use focus-window for exact tab targeting
    if [ -n "${ITERM_SESSION_ID:-}" ]; then
      echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.googlecode.iterm2' '$CWD'"
      return
    fi
    # Fallback: activate whatever terminal is frontmost
    echo "open -a Terminal"
  }

  FOCUS_CMD=$(build_focus_cmd)

  # Fire ClaudeNotifier.app via LaunchServices (required for UNUserNotificationCenter).
  # -timeSensitive keeps the banner on screen until dismissed and bypasses Focus Mode.
  # Runs in background — we don't block on the banner.
  open -W -n -g "$CLAUDE_NOTIFIER_APP" --args \
    -launchedViaLaunchServices \
    -title "$TITLE" \
    -subtitle "$SUBTITLE" \
    -message "$MSG" \
    -group "$GROUP" \
    -timeSensitive \
    -execute "$FOCUS_CMD" \
    2>/dev/null &
  disown

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
