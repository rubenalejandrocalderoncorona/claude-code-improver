#!/usr/bin/env bash
# claude-alert-dispatcher.sh  v3.2.0
# Called by claude-notify.sh to show an alerter notification and handle clicks.
#
# Usage:
#   permission <tty> <group> <title> <subtitle> <message>
#   stop       <tty> <group> <title> <subtitle> <message> <cwd>
#   question   <tty> <group> <title> <subtitle> <question_text> <cwd>
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
#   Shows a ClaudeNotifier.app banner alerting the user that input is needed.
#   Clicking focuses the terminal session. Outputs NOTHING — Claude's own
#   built-in question dialog handles the interaction. Approve-all is never
#   checked here; user questions always require real user input.

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

# Returns the bundle ID of the terminal/IDE that owns this hook session.
# Used as -activate so the macOS "Show" button focuses the right app.
terminal_bundle_id() {
  case "${TERM_PROGRAM:-}" in
    vscode)  echo "com.microsoft.VSCode" ; return ;;
    cursor)  echo "com.todesktop.230313mzl4w4u92" ; return ;;
  esac
  if [ -n "${ITERM_SESSION_ID:-}" ]; then
    echo "com.googlecode.iterm2"
    return
  fi
  echo "com.apple.Terminal"
}

# Returns the shell command for -execute (fine-grained tab/window focus).
build_focus_cmd() {
  local cwd="$1"
  case "${TERM_PROGRAM:-}" in
    vscode)  echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.microsoft.VSCode' '$cwd'" ; return ;;
    cursor)  echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.todesktop.230313mzl4w4u92' '$cwd'" ; return ;;
  esac
  if [ -n "${ITERM_SESSION_ID:-}" ]; then
    echo "\"$CLAUDE_NOTIFICATIONS\" focus-window 'com.googlecode.iterm2' '$cwd'"
    return
  fi
  echo "open -a Terminal"
}

# Fire a ClaudeNotifier.app banner. Both -activate and -execute are set so
# the "Show" button (activate) AND body click (execute) both land in the
# right terminal/IDE window.
fire_banner() {
  local title="$1" subtitle="$2" msg="$3" group="$4" cwd="$5"
  local bundle focus_cmd
  bundle=$(terminal_bundle_id)
  focus_cmd=$(build_focus_cmd "$cwd")

  open -W -n -g "$CLAUDE_NOTIFIER_APP" --args \
    -launchedViaLaunchServices \
    -title "$title" \
    -subtitle "$subtitle" \
    -message "$msg" \
    -group "$group" \
    -timeSensitive \
    -activate "$bundle" \
    -execute "$focus_cmd" \
    2>/dev/null &
  disown
}

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
  fire_banner "$TITLE" "$SUBTITLE" "$MSG" "$GROUP" "$CWD"

# ── Question mode ──────────────────────────────────────────────────────────
# Fire a ClaudeNotifier.app banner so the user knows input is needed, then
# output nothing — Claude's own built-in question dialog stays active and
# the user answers there. Approve-all mode is intentionally never checked here.
elif [ "$MODE" = "question" ]; then

  CWD="$OPTIONS_JSON"   # 7th arg is CWD in question mode
  fire_banner "$TITLE" "$SUBTITLE" "$MSG" "$GROUP" "$CWD"

  # Output nothing — Claude keeps its built-in dialog open for the user to answer.

fi
