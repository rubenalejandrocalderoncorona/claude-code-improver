#!/usr/bin/env bash
# test-hooks.sh — manually fire each notification type to verify the setup
# Usage: bash hooks/test-hooks.sh [test-name]
#   test-name: permission | stop | question | approve-all | all (default: all)

set -euo pipefail

DISPATCHER="$(cd "$(dirname "$0")" && pwd)/claude-alert-dispatcher.sh"
TOGGLE="$(cd "$(dirname "$0")" && pwd)/toggle-approve-all.sh"

# Find the TTY of this terminal so "Show" and focus_session work correctly
TTY_DEVICE=$(tty | sed 's|/dev/||')

pass() { echo "  ✓ $1"; }
info() { echo "  → $1"; }

run_test() {
  local name="$1"
  case "$name" in

    permission)
      echo ""
      echo "TEST: Permission notification"
      info "A notification should appear with an [Approve] and [Dismiss] button."
      info "Clicking Approve should NOT open or focus iTerm2 — you stay in your current app."
      info "Clicking the notification body focuses this terminal tab."
      bash "$DISPATCHER" permission \
        "$TTY_DEVICE" \
        "claude-test-perm" \
        "Claude — test-project" \
        "Permission required: Bash" \
        "rm -rf /tmp/test-file"
      pass "permission test complete (result: $?)"
      ;;

    stop)
      echo ""
      echo "TEST: Stop notification (session finished)"
      info "A notification should appear with a [Show] button."
      info "Clicking Show should bring iTerm2 forward and switch to THIS exact tab."
      bash "$DISPATCHER" stop \
        "$TTY_DEVICE" \
        "claude-test-stop" \
        "Claude — test-project" \
        "Session finished" \
        "Claude has finished. Click Show to switch to the session." &
      disown
      pass "stop notification launched in background"
      ;;

    question)
      echo ""
      echo "TEST: Question notification"
      info "A notification should appear with [Yes] [No] [Maybe] [Show] buttons."
      info "Clicking an option should NOT open iTerm2."
      info "The chosen answer JSON will be printed below."
      RESULT=$(bash "$DISPATCHER" question \
        "$TTY_DEVICE" \
        "claude-test-question" \
        "Claude — test-project" \
        "User question" \
        "Should I proceed with this refactor?" \
        '[{"label":"Yes"},{"label":"No"},{"label":"Maybe"}]')
      if [ -n "$RESULT" ]; then
        pass "question test complete — answer JSON:"
        echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
      else
        pass "question dismissed (no JSON — expected if you clicked Show or Dismiss)"
      fi
      ;;

    approve-all)
      echo ""
      echo "TEST: Approve-All toggle"
      info "Running toggle — watch for a notification confirming ON or OFF."
      bash "$TOGGLE"
      pass "toggle executed"
      echo ""
      info "TEST: Permission with Approve-All ON (should auto-approve silently)"
      FLAG="$HOME/.claude/hooks/approve-all.flag"
      if [ ! -f "$FLAG" ]; then
        touch "$FLAG"
        echo "  (flag created for test)"
        CREATED=1
      fi
      RESULT=$(bash "$DISPATCHER" permission \
        "$TTY_DEVICE" \
        "claude-test-perm-auto" \
        "Claude — test-project" \
        "Permission required: Write" \
        "/tmp/test.txt")
      echo "  Result: $RESULT"
      if echo "$RESULT" | grep -q '"allow"'; then
        pass "auto-approved correctly — no notification shown"
      else
        echo "  FAIL: expected allow, got: $RESULT"
      fi
      # Restore flag state
      if [ "${CREATED:-0}" = "1" ]; then
        rm -f "$FLAG"
        echo "  (flag removed after test)"
      fi
      ;;

    all)
      run_test permission
      run_test stop
      run_test question
      run_test approve-all
      echo ""
      echo "── All tests complete ──"
      echo "Global shortcut test: press Cmd+Shift+A from any app."
      echo "  You should hear a sound and see a notification confirming ON or OFF."
      echo "  Requires ClaudeApproveAll.app running + Accessibility permission granted."
      ;;

    *)
      echo "Unknown test: $name"
      echo "Usage: bash test-hooks.sh [permission|stop|question|approve-all|all]"
      exit 1
      ;;
  esac
}

TEST="${1:-all}"
run_test "$TEST"
