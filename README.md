# Claude Code Hooks

macOS notifications and global keyboard shortcut for Claude Code. Get actionable alerts when Claude needs permission or finishes a task — without leaving your current window.

## What it does

| Event | Notification | Behavior |
|---|---|---|
| Permission request | Tool name + command | **Approve** without switching to terminal |
| Session finished | "Claude has finished" | **Show** jumps to the exact iTerm2 tab |
| AskUserQuestion | Question + answer buttons | Click to answer without switching windows |

**Toggle Approve-All mode** — turns auto-approval ON or OFF for **all running Claude Code sessions** on this machine simultaneously. When ON, every permission request is silently approved without a notification. When OFF, normal per-request prompts resume.

Run from any terminal:
```bash
bash ~/.claude/hooks/toggle-approve-all.sh
```

Or use the global shortcut **`Cmd+Shift+M`** (via the installed macOS Service) from Finder or any app that doesn't intercept that combo. iTerm2 users: use the terminal command above when iTerm2 is focused.

> **Note:** The shortcut toggles the global approve-all flag — it does not approve a single pending request. Use it before starting a batch of trusted work, then toggle it back OFF when done.

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

**3. Hammerspoon — Accessibility** (optional — skip on MDM-managed machines)

Hammerspoon is installed but on MDM-managed machines (e.g. SAP, Jamf) the Accessibility grant may be blocked by policy. The `Cmd+Shift+M` Service shortcut works without any special permissions.

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
bash hooks/test-hooks.sh shortcut    # Cmd+Shift+M global shortcut
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

### v2.1.0
- **Global shortcut `Cmd+Shift+M`** via macOS Automator Service — no Accessibility permission required, works on MDM-managed machines
- Approve-All toggle now clearly documented: affects **all running Claude Code sessions** simultaneously, not a single request
- Updated shortcut test to be shortcut-agnostic (watches flag state, not a specific key combo)
- Removed Hammerspoon dependency for shortcut (kept installed but no longer required)

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
