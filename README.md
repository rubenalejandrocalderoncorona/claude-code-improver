# Claude Code Hooks

macOS notifications and global keyboard shortcut for Claude Code. Get actionable alerts when Claude needs permission or finishes a task — without leaving your current window.

## What it does

| Event | Notification | Behavior |
|---|---|---|
| Permission request | Tool name + command | **Approve** without switching to terminal |
| Session finished | "Claude has finished" | **Show** jumps to the exact iTerm2 tab |
| AskUserQuestion | Question + answer buttons | Click to answer without switching windows |

**Global shortcut `Cmd+Shift+A`** — toggles Approve-All mode. All future permission prompts are auto-approved silently. Press again to turn off.

## Install

```bash
git clone https://github.com/rubenalejandrocalderoncorona/claude-code-improver.git
cd claude-code-improver
bash install-claude-hooks.sh
```

That's it. The script installs dependencies, compiles the hotkey app, wires up the hooks, and starts everything.

## Required permissions (one-time, after install)

**1. iTerm2 — notification alerts** (for "Session finished" notifications)
> System Settings → Notifications → iTerm2 → Alert Style: **Alerts**

**2. Terminal — notification alerts** (for permission/question notifications)
> System Settings → Notifications → Terminal → Alert Style: **Alerts**

**3. Hammerspoon — Accessibility** (for the global shortcut)

Hammerspoon will prompt automatically on first launch. Click "Open System Settings", add **Hammerspoon.app** and toggle it ON, then reload:
```bash
hs -c "hs.reload()"
```

**Restart iTerm2** after install so the custom tab title format takes effect.

## Verify

Run hooks smoke tests:

```bash
bash hooks/test-hooks.sh
```

Individual tests:

```bash
bash hooks/test-hooks.sh permission   # Approve button, no focus steal
bash hooks/test-hooks.sh stop         # Show button, correct tab focus
bash hooks/test-hooks.sh question     # Answer buttons, no focus steal
bash hooks/test-hooks.sh approve-all  # Auto-approve + toggle
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
- For `PermissionRequest` it runs `claude-alert-dispatcher.sh` synchronously — the script blocks on `alerter`, then writes a `{"behavior":"allow"}` or deny JSON to stdout which Claude Code reads.
- For `Stop` it runs the dispatcher in the background — clicking Show calls `tell w to select t` + `select s` + `activate` to bring the exact tab forward.
- Permission and question notifications use `--sender com.apple.Terminal` so clicking Approve/answer buttons does **not** bring any terminal forward.
- The global shortcut uses **Hammerspoon** (a properly Apple-signed app). Config lives in `~/.hammerspoon/init.lua`. It requires Accessibility permission and starts at login.

## Changelog

### v2.0.0
- **Fix: Approve no longer opens the terminal** — switched permission/question notification sender from `com.googlecode.iterm2` to `com.apple.scripteditor2`
- **Fix: Show now jumps to the correct iTerm2 tab** — `focus_session` now calls `tell w to select t` before `select s`
- **Fix: global Cmd+Shift+A shortcut now works everywhere** — replaced broken Automator Quick Action with a compiled Swift Carbon `RegisterEventHotKey` daemon installed as a `LaunchAgent`; no Accessibility permission required
- Added `hooks/test-hooks.sh` for smoke-testing each notification type
- Added `hotkey-app/` Swift source for the global hotkey daemon

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
