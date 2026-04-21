# Claude Code Hooks

macOS notifications and global keyboard shortcut for Claude Code. Get actionable alerts when Claude needs permission or finishes a task — without leaving your current window.

## What it does

| Event | Notification | Behavior |
|---|---|---|
| Permission request | Tool name + command | **Approve** without switching to terminal |
| Session finished | "Claude has finished" | **Show** jumps to the exact iTerm2 tab |
| AskUserQuestion | Question + answer buttons | Click to answer without switching windows |

**Global shortcut `Cmd+Ctrl+B`** — toggles Approve-All mode. All future permission prompts are auto-approved silently. Press again to turn off.

## Install

```bash
git clone https://github.com/rubenalejandrocalderoncorona/claude-code-improver.git
cd claude-code-improver
bash install-claude-hooks.sh
```

## Required permissions (one-time, after install)

**1. iTerm2 — notification alerts** (for "Session finished" notifications)
> System Settings → Notifications → iTerm2 → Alert Style: **Alerts**

**2. Terminal — notification alerts** (for permission/question notifications)
> System Settings → Notifications → Terminal → Alert Style: **Alerts**

**3. Hammerspoon — Accessibility** (for the global shortcut)

Hammerspoon prompts automatically on first launch. Click "Open System Settings", add **Hammerspoon.app**, toggle it ON.

> **macOS Sequoia note:** After every Hammerspoon launch/restart, you must toggle its Accessibility permission **off then back on** for key events to register. Go to System Settings → Privacy & Security → Accessibility → toggle Hammerspoon OFF → wait 2s → toggle ON.

Then verify the shortcut works:
```bash
bash hooks/test-hooks.sh shortcut
```

**Restart iTerm2** after install so the custom tab title format takes effect.

## Verify

```bash
bash hooks/test-hooks.sh             # all tests
bash hooks/test-hooks.sh permission  # Approve button, no focus steal
bash hooks/test-hooks.sh stop        # Show button, correct tab focus
bash hooks/test-hooks.sh shortcut    # Cmd+Ctrl+B global hotkey
```

Check hooks are loaded in Claude Code:
```
/hooks
```

## Files

```
hooks/
  claude-notify.sh            Main hook — tab titles + dispatches notifications
  claude-alert-dispatcher.sh  Blocks on alerter, routes Approve/Show/answer clicks
  toggle-approve-all.sh       Toggles ~/.claude/hooks/approve-all.flag
  test-hooks.sh               Smoke tests for each notification type
install-claude-hooks.sh       One-command setup
```

## How it works

- `claude-notify.sh` receives a JSON event on stdin, finds the TTY of the Claude process via process-tree walk, and sets `user.tabTitle` on that specific iTerm2 session via AppleScript.
- For `PermissionRequest` it runs `claude-alert-dispatcher.sh` synchronously — blocks on `alerter`, then writes `{"behavior":"allow"}` or deny JSON to stdout which Claude Code reads.
- For `Stop` it runs the dispatcher in the background — clicking Show calls `tell w to select t` + `select s` + `activate` to bring the exact tab forward.
- Permission and question notifications use `--sender com.apple.Terminal` so clicking Approve does **not** bring any terminal forward.
- The global shortcut uses **Hammerspoon** (`~/.hammerspoon/init.lua`). Requires Accessibility. Starts at login.

## Changelog

### v2.0.0
- **Fix: Approve no longer opens the terminal** — switched sender to `com.apple.Terminal`
- **Fix: Show now jumps to the correct iTerm2 tab** — added `tell w to select t` before `select s`
- **Fix: global shortcut** — replaced broken Automator Quick Action with Hammerspoon (`Cmd+Ctrl+B`)
- Added `hooks/test-hooks.sh` smoke tests

### v1.0.1
- Fix double alerts and Approve button not sending to correct session

### v1.0.0
- Approve button in permission notification — approves without switching windows
- Two notification types: permission (Approve/Dismiss) and stop (Show/Ignore)
- Rich context: project name, tool name, full command/file path
- Session focus via AppleScript TTY lookup

### v0.0.2
- Replace `terminal-notifier` with iTerm2 OSC 9 notifications
- Clicking Show focuses the exact session

### v0.0.1
- Initial: `PermissionRequest` hook with `terminal-notifier`
