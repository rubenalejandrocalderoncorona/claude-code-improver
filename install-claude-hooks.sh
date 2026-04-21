#!/usr/bin/env bash
# install-claude-hooks.sh
# Replicates Claude Code notification + iTerm2 tab-rename setup on any macOS machine.
# Usage: bash install-claude-hooks.sh

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "── Claude Code Notification Hook Installer ──"

# ── 1. Dependencies ────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."; brew install jq
fi
if ! command -v osascript &>/dev/null; then
  echo "ERROR: osascript not found. This script requires macOS."; exit 1
fi
# alerter: multi-button macOS notifications with click callbacks
if [ ! -f "/opt/homebrew/bin/alerter" ]; then
  echo "Installing alerter..."
  TMP=$(mktemp -d)
  curl -sL "https://github.com/vjeantet/alerter/releases/download/v26.5/alerter-26.5.zip" -o "$TMP/alerter.zip"
  unzip -q "$TMP/alerter.zip" -d "$TMP"
  cp "$TMP/alerter" /opt/homebrew/bin/alerter
  chmod +x /opt/homebrew/bin/alerter
  rm -rf "$TMP"
fi
echo "✓ Dependencies OK (jq, alerter)"

# ── 2. Install hook scripts ────────────────────────────────────────────────
mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/hooks/claude-notify.sh"          "$HOOK_DIR/claude-notify.sh"
cp "$SCRIPT_DIR/hooks/claude-alert-dispatcher.sh" "$HOOK_DIR/claude-alert-dispatcher.sh"
cp "$SCRIPT_DIR/hooks/toggle-approve-all.sh"     "$HOOK_DIR/toggle-approve-all.sh"
chmod +x "$HOOK_DIR/claude-notify.sh" \
         "$HOOK_DIR/claude-alert-dispatcher.sh" \
         "$HOOK_DIR/toggle-approve-all.sh"
echo "✓ Hook scripts installed to $HOOK_DIR"

# ── 3. Merge hooks into ~/.claude/settings.json ───────────────────────────
# PreToolUse has TWO entries:
#   1. Synchronous (no async) for AskUserQuestion — the hook blocks and returns a JSON answer.
#   2. Async catch-all for all other tools — just updates the tab title.
HOOKS_JSON='{
  "SessionStart":      [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "Stop":              [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}],
  "PermissionRequest": [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh"}]}],
  "PreToolUse": [
    {"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh"}]},
    {"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}
  ],
  "PostToolUse":       [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/hooks/claude-notify.sh","async":true}]}]
}'

if [ -f "$SETTINGS" ]; then
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
profile["Title"] = 128
profile["Custom Tab Title"] = r"\(user.tabTitle)"
profile["BM Growl"] = False

prefs["New Bookmarks"] = bookmarks
with open(plist_path, 'wb') as f:
    plistlib.dump(prefs, f, fmt=plistlib.FMT_BINARY)

print("✓ iTerm2 default profile set to custom title format \\(user.tabTitle)")
print("  → Restart iTerm2 (or reload prefs) for this to take effect.")
PYEOF
fi

# ── 5. Install Hammerspoon for global Cmd+Ctrl+B hotkey ───────────────────
# Hammerspoon is a properly Apple-signed app. It uses Accessibility permission
# which macOS honours reliably — unlike ad-hoc signed or Homebrew CLI binaries.
HS_CONFIG="$HOME/.hammerspoon/init.lua"
HS_LINE='hs.hotkey.bind({"cmd","ctrl"},"b",function() hs.task.new("/bin/bash",function() end,{os.getenv("HOME").."/.claude/hooks/toggle-approve-all.sh"}):start() end)'

if ! command -v hs &>/dev/null && [ ! -d "/Applications/Hammerspoon.app" ]; then
  echo "Installing Hammerspoon..."
  brew install --cask hammerspoon
fi
echo "✓ Hammerspoon installed"

HS_PRELUDE='hs.ipc.cliInstall()'
HS_COMMENT='-- Claude Code: toggle approve-all mode with Cmd+Ctrl+B'
HS_LINE='hs.hotkey.bind({"cmd","ctrl"},"b",function() hs.task.new("/bin/bash",function() end,{os.getenv("HOME").."/.claude/hooks/toggle-approve-all.sh"}):start() end)'

mkdir -p "$(dirname "$HS_CONFIG")"
if ! grep -q "toggle-approve-all" "$HS_CONFIG" 2>/dev/null; then
  # Prepend ipc install (enables hs -c from terminal), then append hotkey
  { echo "$HS_PRELUDE"; echo ""; cat "$HS_CONFIG" 2>/dev/null; } > "$HS_CONFIG.tmp" && mv "$HS_CONFIG.tmp" "$HS_CONFIG" || true
  echo "" >> "$HS_CONFIG"
  echo "$HS_COMMENT" >> "$HS_CONFIG"
  echo "$HS_LINE" >> "$HS_CONFIG"
fi
echo "✓ Hammerspoon config written: $HS_CONFIG"

# Launch Hammerspoon (it will prompt for Accessibility on first run)
open /Applications/Hammerspoon.app 2>/dev/null || true
echo "✓ Hammerspoon launched"

# ── 6. Remind about macOS permissions ─────────────────────────────────────
echo ""
echo "── Done ────────────────────────────────────────────────────────────"
echo ""
echo "REQUIRED: Allow notifications for iTerm2 and Terminal:"
echo "  System Settings → Notifications → iTerm2    → Alert Style: Alerts"
echo "  System Settings → Notifications → Terminal  → Alert Style: Alerts"
echo ""
echo "REQUIRED: Restart iTerm2 so the custom tab title format takes effect."
echo ""
echo "REQUIRED FOR SHORTCUT (Cmd+Ctrl+B):"
echo "  1. Hammerspoon will prompt for Accessibility — click 'Open System Settings'"
echo "  2. Add Hammerspoon.app and toggle it ON"
echo "  3. Then reload: hs -c 'hs.reload()'"
echo ""
echo "Verify hooks are loaded in Claude Code: /hooks"
