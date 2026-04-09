# Claude Code Improver

macOS quality-of-life hooks for Claude Code: iTerm2 tab status titles and native notifications.

## What it does

| Event | Tab title | Notification |
|---|---|---|
| Session starts | `project [claude]` | — |
| Claude is running a tool | `project [running]` | — |
| Claude finished, waiting for input | `project [waiting]` | `Claude — project` / `Session finished` / `Claude thinking session finished...` |
| Permission request | `project [AUTH NEEDED]` | `Claude — project` / `Requires permission: Bash` / `the command here` |

Notifications are attributed to **iTerm2** — clicking one brings the right window to front. Only **one** notification per project is shown at a time (old ones are replaced, not stacked).

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

- Sets a `user.tabTitle` variable on the current iTerm2 session via AppleScript — iTerm2 renders this as the tab title with no job-name suffix
- Sends notifications via `terminal-notifier` with `-sender com.googlecode.iterm2` (iTerm2 icon, clicking activates iTerm2) and `-group claude-<project>` so new notifications **replace** old ones instead of stacking

The `PermissionRequest` event (not `Notification`) is used for permission alerts — it fires exactly once per prompt and includes the tool name and command in its payload.

The iTerm2 plist patch sets `Title = 128` (custom format mode) and `Custom Tab Title = \(user.tabTitle)` on the default profile.

## Files

```
hooks/claude-notify.sh     # The hook script (installed to ~/.claude/hooks/)
install-claude-hooks.sh    # Installer
```

## Changelog

### v0.0.1
- Switch from `Notification` to `PermissionRequest` hook event — fires exactly once, includes tool name and command
- Use `terminal-notifier -group` to replace stale notifications instead of stacking them
- Notification shows title / subtitle (tool) / message (command) in a clear 3-line format
- `PostToolUse` clears the permission notification automatically once the tool runs

