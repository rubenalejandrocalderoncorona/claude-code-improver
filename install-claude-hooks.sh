#!/usr/bin/env bash
# install-claude-hooks.sh
# Replicates Claude Code notification + iTerm2 tab-rename setup on any macOS machine.
# Usage: bash install-claude-hooks.sh

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="$HOOK_DIR/claude-notify.sh"
SETTINGS="$HOME/.claude/settings.json"
ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "── Claude Code Notification Hook Installer ──"

# ── 1. Dependencies ────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."; brew install jq
fi
if ! command -v terminal-notifier &>/dev/null; then
  echo "Installing terminal-notifier..."; brew install terminal-notifier
fi
if ! command -v osascript &>/dev/null; then
  echo "ERROR: osascript not found. This script requires macOS."; exit 1
fi
echo "✓ Dependencies OK (jq, terminal-notifier)"

# ── 2. Install hook script ─────────────────────────────────────────────────
mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/hooks/claude-notify.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"
echo "✓ Hook script installed to $HOOK_SCRIPT"

# ── 3. Merge hooks into ~/.claude/settings.json ───────────────────────────
HOOKS_JSON='{
  "SessionStart":  [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "Stop":          [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "Notification":  [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "PreToolUse":    [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "PostToolUse":   [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}]
}'

if [ -f "$SETTINGS" ]; then
  # Merge: preserve existing settings, add/replace hooks key
  MERGED=$(jq --argjson h "$HOOKS_JSON" '. + {hooks: $h}' "$SETTINGS")
  echo "$MERGED" > "$SETTINGS"
  echo "✓ Merged hooks into existing $SETTINGS"
else
  mkdir -p "$(dirname "$SETTINGS")"
  echo "{\"hooks\": $HOOKS_JSON}" | jq . > "$SETTINGS"
  echo "✓ Created $SETTINGS with hooks"
fi

# ── 4. Configure iTerm2 profile to use \(user.tabTitle) as tab title ───────
if [ ! -f "$ITERM_PLIST" ]; then
  echo "⚠  iTerm2 plist not found at $ITERM_PLIST — skipping iTerm2 config."
  echo "   Open iTerm2 at least once, then re-run this script."
else
  # Back up plist
  cp "$ITERM_PLIST" "${ITERM_PLIST}.backup"
  echo "✓ iTerm2 plist backed up to ${ITERM_PLIST}.backup"

  python3 << 'PYEOF'
import plistlib, os, sys

plist_path = os.path.expanduser("~/Library/Preferences/com.googlecode.iterm2.plist")

with open(plist_path, 'rb') as f:
    prefs = plistlib.load(f)

bookmarks = prefs.get("New Bookmarks", [])
if not bookmarks:
    print("⚠  No profiles found in iTerm2 plist — skipping.")
    sys.exit(0)

profile = bookmarks[0]
profile["Title"] = 128                      # Custom title format mode
profile["Custom Tab Title"] = r"\(user.tabTitle)"  # Use our variable

prefs["New Bookmarks"] = bookmarks
with open(plist_path, 'wb') as f:
    plistlib.dump(prefs, f, fmt=plistlib.FMT_BINARY)

print("✓ iTerm2 default profile set to custom title format \\(user.tabTitle)")
print("  → Restart iTerm2 (or reload prefs) for this to take effect.")
PYEOF
fi

# ── 5. Remind about macOS notification permissions ─────────────────────────
echo ""
echo "── Done ────────────────────────────────────────────────────────────"
echo ""
echo "REQUIRED: Allow notifications for iTerm2:"
echo "  System Settings → Notifications → iTerm2 → Allow Notifications"
echo ""
echo "REQUIRED: Restart iTerm2 so the custom tab title format takes effect."
echo ""
echo "Verify hooks are loaded in Claude Code: /hooks"
