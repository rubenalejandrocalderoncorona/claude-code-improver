# Claude Code Improver

macOS quality-of-life hooks for Claude Code: iTerm2 tab status titles and actionable notifications.

## What it does

| Event | Tab title | Notification | Buttons |
|---|---|---|---|
| Session starts | `project [claude]` | — | — |
| Claude running a tool | `project [running]` | — | — |
| Claude finished, needs input | `project [waiting]` | Title + "Session finished" + message | Click to focus session |
| Permission request | `project [AUTH NEEDED]` | Title + tool name + full command | **Approve** (sends `y`) · Dismiss |

- **Approve** button sends the approval directly to Claude without switching windows
- Clicking the notification body focuses the exact iTerm2 session that needs attention
- Permission notifications clear automatically once the tool runs

## Requirements

- macOS
- [iTerm2](https://iterm2.com)
- [Homebrew](https://brew.sh)
- [Claude Code](https://claude.ai/code)

## Install

```bash
git clone https://github.com/rubenalejandrocalderoncorona/claude-code-improver.git
cd claude-code-improver
bash install-claude-hooks.sh
```

The installer:
1. Installs `jq` and `alerter` if missing
2. Copies `hooks/claude-notify.sh` and `hooks/claude-alert-dispatcher.sh` to `~/.claude/hooks/`
3. Merges hook entries into `~/.claude/settings.json`
4. Patches your iTerm2 default profile to use `\(user.tabTitle)` as tab title format (suppresses the `(python)` / `(node)` suffix)

## Post-install steps

**Allow notifications for iTerm2:**
> System Settings → Notifications → iTerm2 → Allow Notifications → Alert Style: Alerts

**Restart iTerm2** so the new tab title format takes effect.

**Verify hooks are loaded** in Claude Code:
```
/hooks
```

## How it works

Claude Code fires hook events at key moments. `claude-notify.sh` receives a JSON payload on stdin, then:

1. Walks its process tree to find the TTY of the Claude process that spawned it
2. Sets `user.tabTitle` on that specific iTerm2 session via AppleScript (clean tab title, no job-name suffix)
3. Launches `claude-alert-dispatcher.sh` in the background, which calls `alerter` and blocks until the user clicks

When the user clicks **Approve**, the dispatcher uses AppleScript `write text "y"` to send the confirmation directly to the Claude session — no window switch needed.

When the user clicks the notification body, the dispatcher calls `select s` + `activate` on the exact iTerm2 session identified by TTY.

`alerter` is used instead of `terminal-notifier` because it supports custom action buttons with click callbacks. The `--sender com.googlecode.iterm2` flag gives the notification the iTerm2 icon.

## Files

```
hooks/claude-notify.sh            # Main hook — tab titles + launches dispatcher
hooks/claude-alert-dispatcher.sh  # Blocks on alerter, handles Approve/Show clicks
install-claude-hooks.sh           # One-command setup for any macOS machine
```

## Changelog

### v1.0.0
- **Approve button**: click Approve in the permission notification to send `y` to Claude without switching windows
- **Two distinct notification types**: permission alerts have [Approve] + [Dismiss]; finish alerts have click-to-focus only
- **Rich context**: notification shows project name, tool name, and the full command/file being requested
- Replace OSC 9 iTerm2 escape with `alerter` for full button control; session focus via AppleScript TTY lookup
- Separate `claude-alert-dispatcher.sh` handles blocking alerter call + click routing in background

### v0.0.2
- Replace `terminal-notifier` with iTerm2's native OSC 9 notification escape
- Clicking "Show" in the banner now correctly focuses the exact session that needs attention
- TTY detection via process-tree walk ensures the right session is targeted across multiple windows

### v0.0.1
- Switch from `Notification` to `PermissionRequest` hook event — fires exactly once, includes tool name and command
- Use `terminal-notifier -group` to replace stale notifications instead of stacking them
- Notification shows title / subtitle (tool) / message (command) in a clear 3-line format
- `PostToolUse` clears the permission notification automatically once the tool runs

