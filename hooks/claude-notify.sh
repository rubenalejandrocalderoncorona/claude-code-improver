#!/usr/bin/env bash
# Claude Code notification + iTerm2 tab-rename hook  v2.0.0
# Events: PermissionRequest, Stop, SessionStart, PreToolUse, PostToolUse
#
# PermissionRequest: SYNCHRONOUS — blocks on alerter (or approve-all flag),
#   then outputs JSON decision to stdout which Claude Code reads.
#
# PreToolUse / AskUserQuestion: SYNCHRONOUS — shows option buttons in a
#   notification; chosen answer is returned as PreToolUse updatedInput JSON.
#
# Stop: runs dispatcher in background; "Show" focuses the session.
#
# Approve-all mode: touch ~/.claude/hooks/approve-all.flag to auto-approve
#   all PermissionRequest hooks silently. Toggle with toggle-approve-all.sh.
#
# Requires: jq, alerter  (install via install-claude-hooks.sh)

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TOOL=$(echo "$INPUT"  | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT"   | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

ALERTER="/opt/homebrew/bin/alerter"
DISPATCHER="$(dirname "$0")/claude-alert-dispatcher.sh"
APPROVE_ALL_FLAG="$HOME/.claude/hooks/approve-all.flag"

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
    if [ "$TOOL" = "AskUserQuestion" ]; then
      # Extract the first question and its options from the tool_input.
      QUESTION_TEXT=$(echo "$INPUT" | jq -r '.tool_input.questions[0].question // ""')
      QUESTION_HEADER=$(echo "$INPUT" | jq -r '.tool_input.questions[0].header // "Question"')
      # Pass the full questions array so the dispatcher can rebuild updatedInput.
      OPTIONS_JSON=$(echo "$INPUT" | jq -c '.tool_input.questions[0].options // []')

      set_tab_title "${PROJECT} [question]"

      # Run synchronously — dispatcher blocks on alerter then prints JSON.
      bash "$DISPATCHER" question \
        "$SESSION_TTY" \
        "claude-question-${PROJECT}" \
        "Claude — ${PROJECT}" \
        "$QUESTION_HEADER" \
        "$QUESTION_TEXT" \
        "$OPTIONS_JSON"
      exit 0
    else
      # All other tools: just update tab title asynchronously.
      set_tab_title "${PROJECT} [running]"
    fi
    ;;

  PostToolUse)
    set_tab_title "${PROJECT} [claude]"
    # Clear any stale permission alert
    "$ALERTER" --remove "claude-perm-${PROJECT}" 2>/dev/null || true
    ;;

  Stop)
    set_tab_title "${PROJECT} [waiting]"
    # Launch dispatcher in background — it blocks on alerter until user acts.
    bash "$DISPATCHER" stop \
      "$SESSION_TTY" \
      "claude-stop-${PROJECT}" \
      "Claude — ${PROJECT}" \
      "Session finished" \
      "Claude has finished. Click Show to switch to the session." \
      &
    disown
    ;;

  PermissionRequest)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
    CMD=$(echo "$INPUT" | jq -r '
      if .tool_name == "Bash" then .tool_input.command // ""
      elif .tool_name == "Write" or .tool_name == "Edit" then .tool_input.file_path // ""
      else (.tool_input | to_entries | map("\(.key): \(.value)") | join(", "))
      end' | cut -c1-100)

    # Reflect approve-all mode in the tab title so the user knows it's active.
    if [ -f "$APPROVE_ALL_FLAG" ]; then
      set_tab_title "${PROJECT} [APPROVE-ALL]"
    else
      set_tab_title "${PROJECT} [AUTH NEEDED]"
    fi

    # Run synchronously — dispatcher checks the flag, then shows the alert if
    # needed, and finally prints the allow/deny JSON to stdout.
    bash "$DISPATCHER" permission \
      "$SESSION_TTY" \
      "claude-perm-${PROJECT}" \
      "Claude — ${PROJECT}" \
      "Permission required: ${TOOL_NAME}" \
      "${CMD}"
    exit 0
    ;;

esac

exit 0
