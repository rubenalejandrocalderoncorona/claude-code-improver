# Claude Code Improver

macOS quality-of-life hooks for Claude Code: iTerm2 tab status titles and native notifications.

## What it does

| Event | Tab title | Notification |
|---|---|---|
| Session starts | `project [claude]` | — |
| Claude is running a tool | `project [running]` | — |
| Claude finished, waiting for input | `project [waiting]` | Banner + sound (Purr) |
| Permission request needs your answer | `project [AUTH NEEDED]` | Banner + sound (Glass) |

Notifications are attributed to **iTerm2** — clicking one brings the right window to front.

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

- Sets a `user.tabTitle` variable on the current iTerm2 session via AppleScript — iTerm2 renders this as the tab title
- Sends notifications via `terminal-notifier` using `-sender com.googlecode.iterm2`, so they appear with the iTerm2 icon and clicking them activates iTerm2

The iTerm2 plist patch sets `Title = 128` (custom format mode) and `Custom Tab Title = \(user.tabTitle)` on the default profile, which tells iTerm2 to display our variable instead of its default `name — jobName` format.

## Files

```
hooks/claude-notify.sh     # The hook script (installed to ~/.claude/hooks/)
install-claude-hooks.sh    # Installer
```
