# Claude Code Improver

macOS quality-of-life hooks for Claude Code: iTerm2 tab status titles and native notifications.

## What it does

| Event | Tab title | Notification |
|---|---|---|
| Session starts | `project [claude]` | — |
| Claude is running a tool | `project [running]` | — |
| Claude finished, waiting for input | `project [waiting]` | `Claude — project: session finished. Your input is needed.` |
| Permission request | `project [AUTH NEEDED]` | `Claude — project: permission needed for Bash: <command>` |

Notifications use **iTerm2's native OSC 9 escape** — clicking "Show" redirects to the exact session that needs attention.

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
1. Installs `jq` and `terminal-notifier` via Homebrew if missing
2. Copies `hooks/claude-notify.sh` to `~/.claude/hooks/`
3. Merges hook entries into `~/.claude/settings.json`
4. Patches your iTerm2 default profile to use `\(user.tabTitle)` as tab title format (suppresses the `(python)` / `(node)` suffix)

## Post-install steps

**Allow notifications for iTerm2:**
> System Settings → Notifications → iTerm2 → Allow Notifications

**Restart iTerm2** so the new tab title format takes effect.

**Verify hooks are loaded** in Claude Code:
```
/hooks
```

## How it works

Claude Code fires hook events at key moments. The hook script (`hooks/claude-notify.sh`) receives a JSON payload on stdin and:

- Walks its process tree to find the TTY of the Claude process that spawned it
- Sets `user.tabTitle` on that specific iTerm2 session via AppleScript
- Sends an **iTerm2 native notification** by writing the OSC 9 escape sequence (`\e]9;message\a`) to the session via AppleScript `write text` — this is the same mechanism iTerm2 uses internally, so clicking "Show" focuses the exact session

The `PermissionRequest` event (not `Notification`) handles permission alerts — fires exactly once, includes tool name and command.

The iTerm2 plist patch sets `Title = 128` (custom format mode) and `Custom Tab Title = \(user.tabTitle)` on the default profile.

## Files

```
hooks/claude-notify.sh     # The hook script (installed to ~/.claude/hooks/)
install-claude-hooks.sh    # Installer
```

## Changelog

### v0.0.2
- Replace `terminal-notifier` with iTerm2's native OSC 9 notification escape
- Clicking "Show" in the banner now correctly focuses the exact session that needs attention
- TTY detection via process-tree walk ensures the right session is targeted across multiple windows

### v0.0.1
- Switch from `Notification` to `PermissionRequest` hook event — fires exactly once, includes tool name and command
- Use `terminal-notifier -group` to replace stale notifications instead of stacking them
- Notification shows title / subtitle (tool) / message (command) in a clear 3-line format
- `PostToolUse` clears the permission notification automatically once the tool runs

