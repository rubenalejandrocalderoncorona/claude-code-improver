#!/usr/bin/env bash
# test-hooks.sh — manually fire each notification type to verify the setup
# Usage: bash hooks/test-hooks.sh [test-name]
#   test-name: permission | stop | question | approve-all | all (default: all)

set -uo pipefail

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
      FLAG="$HOME/.claude/hooks/approve-all.flag"
      FLAG_WAS_SET=0
      [ -f "$FLAG" ] && FLAG_WAS_SET=1
      # Guarantee flag is restored to its original state on exit or interrupt
      trap '[ "$FLAG_WAS_SET" = "1" ] && touch "$FLAG" || rm -f "$FLAG"; trap - EXIT INT TERM' EXIT INT TERM

      info "Running toggle — watch for a notification confirming ON or OFF."
      bash "$TOGGLE"
      pass "toggle executed"
      echo ""
      info "TEST: Permission with Approve-All ON (should auto-approve silently)"
      touch "$FLAG"
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
      # Restore original flag state
      if [ "$FLAG_WAS_SET" = "1" ]; then
        touch "$FLAG"
        echo "  (flag restored to ON)"
      else
        rm -f "$FLAG"
        echo "  (flag restored to OFF)"
      fi
      trap - EXIT INT TERM
      ;;

    shortcut)
      echo ""
      echo "TEST: Global shortcut (Cmd+Ctrl+B)"

      # Check Hammerspoon is running
      if ! pgrep -x Hammerspoon > /dev/null 2>&1; then
        echo "  FAIL: Hammerspoon is not running."
        echo "  Run: open /Applications/Hammerspoon.app"
        echo "  Then grant Accessibility when prompted and run: hs -c 'hs.reload()'"
        return
      fi
      info "Hammerspoon running (PID $(pgrep -x Hammerspoon))"

      FLAG="$HOME/.claude/hooks/approve-all.flag"
      FLAG_WAS_SET=0
      [ -f "$FLAG" ] && FLAG_WAS_SET=1
      BEFORE_STATE=$FLAG_WAS_SET

      echo ""
      echo "  ► Press Cmd+Ctrl+B now (you have 20 seconds, from ANY app)..."
      echo ""

      FIRED=0
      for i in $(seq 1 20); do
        sleep 1
        CURRENT=0
        [ -f "$FLAG" ] && CURRENT=1
        if [ "$CURRENT" != "$BEFORE_STATE" ]; then
          FIRED=1
          break
        fi
      done

      if [ "$FIRED" = "1" ]; then
        pass "shortcut fired — approve-all flag toggled"
        # Restore original state
        if [ "$FLAG_WAS_SET" = "1" ]; then touch "$FLAG"; else rm -f "$FLAG"; fi
        echo "  (flag restored to original state)"
      else
        echo "  FAIL: flag state did not change within 20 seconds."
        echo "  Check: System Settings → Privacy & Security → Accessibility → Hammerspoon enabled?"
        echo "  Check: hs -c 'hs.reload()' to reload config after granting permission"
      fi
      ;;

    all)
      run_test permission
      run_test stop
      run_test question
      run_test approve-all
      run_test shortcut
      echo ""
      echo "── All tests complete ──"
      ;;

    *)
      echo "Unknown test: $name"
      echo "Usage: bash test-hooks.sh [permission|stop|question|approve-all|shortcut|all]"
      exit 1
      ;;
  esac
}

TEST="${1:-all}"
run_test "$TEST"
