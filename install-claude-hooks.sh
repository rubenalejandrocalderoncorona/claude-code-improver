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

# ── 5. Build and install ClaudeApproveAll.app (global Cmd+Shift+A hotkey) ──
# Replaces the Automator Quick Action approach (which only fires when an app has
# text selected). This is a tiny LSUIElement background app that registers a
# true global CGEventTap, so the shortcut works from anywhere on macOS.
APP_SRC="$SCRIPT_DIR/hotkey-app"
APP_DEST="$HOME/Applications/ClaudeApproveAll.app"
APP_BINARY="$APP_DEST/Contents/MacOS/ClaudeApproveAll"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.claudecodehooks.approve-all-hotkey.plist"

echo "Building ClaudeApproveAll.app..."
mkdir -p "$APP_DEST/Contents/MacOS"
mkdir -p "$APP_DEST/Contents/Resources"

# Compile the Swift source
if swiftc -O -o "$APP_BINARY" "$APP_SRC/main.swift" 2>/dev/null; then
  echo "✓ Compiled ClaudeApproveAll binary"
else
  echo "ERROR: Swift compilation failed. Ensure Xcode command-line tools are installed."
  echo "  Run: xcode-select --install"
  exit 1
fi

cp "$APP_SRC/Info.plist" "$APP_DEST/Contents/Info.plist"
echo "✓ ClaudeApproveAll.app installed to $APP_DEST"

# Install as a LaunchAgent so it starts automatically at login
cat > "$LAUNCH_AGENT_PLIST" << LAUNCHD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.claudecodehooks.approve-all-hotkey</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_BINARY}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
LAUNCHD

# Start the agent now (stop any previous instance first)
launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
launchctl load -w "$LAUNCH_AGENT_PLIST"
echo "✓ LaunchAgent installed and started: $LAUNCH_AGENT_PLIST"

# ── 6. Remind about macOS notification permissions ─────────────────────────
echo ""
echo "── Done ────────────────────────────────────────────────────────────"
echo ""
echo "REQUIRED: Allow notifications for iTerm2 and Script Editor:"
echo "  System Settings → Notifications → iTerm2 → Alert Style: Alerts"
echo "  System Settings → Notifications → Script Editor → Alert Style: Alerts"
echo "  (Script Editor is used for Approve/question notifications so they"
echo "   don't steal focus from your current window.)"
echo ""
echo "REQUIRED: Restart iTerm2 so the custom tab title format takes effect."
echo ""
echo "SHORTCUT: Cmd+Shift+A toggles Approve-All mode (auto-approves all permissions)."
echo "  Works globally from any app — no extra permissions required."
echo "  ClaudeApproveAll runs as a background LaunchAgent and starts at login."
echo ""
echo "Verify hooks are loaded in Claude Code: /hooks"
