#!/usr/bin/env bash
# manage-claude-hooks.sh
# Disable, re-enable, or fully uninstall the Claude Code notification hooks.
#
# Usage:
#   bash manage-claude-hooks.sh disable    # Remove hooks from settings.json (keep files)
#   bash manage-claude-hooks.sh enable     # Re-add hooks to settings.json
#   bash manage-claude-hooks.sh uninstall  # Remove hooks + all installed files

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
HOOK_DIR="$HOME/.claude/hooks"
NOTIFY_CMD="~/.claude/hooks/claude-notify.sh"

usage() {
  echo "Usage: bash manage-claude-hooks.sh <disable|enable|uninstall>"
  echo ""
  echo "  disable    Remove claude-notify.sh hooks from settings.json (files kept)"
  echo "  enable     Re-add claude-notify.sh hooks to settings.json"
  echo "  uninstall  Remove hooks from settings.json AND delete all installed files"
  exit 1
}

[ $# -eq 1 ] || usage

# ── helpers ──────────────────────────────────────────────────────────────────

settings_exists() {
  [ -f "$SETTINGS" ]
}

backup_settings() {
  cp "$SETTINGS" "${SETTINGS}.bak"
  echo "✓ Backed up settings.json → ${SETTINGS}.bak"
}

# Removes every hook entry whose command contains claude-notify.sh.
# Works on any event key (SessionStart, Stop, PermissionRequest, etc.).
remove_notify_hooks() {
  python3 - "$SETTINGS" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.get("hooks", {})
for event, matchers in list(hooks.items()):
    kept = []
    for entry in matchers:
        filtered = [h for h in entry.get("hooks", [])
                    if "claude-notify.sh" not in h.get("command", "")]
        if filtered:
            entry = dict(entry, hooks=filtered)
            kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]

cfg["hooks"] = hooks
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)
print("✓ Removed claude-notify.sh entries from hooks")
PYEOF
}

# Adds the standard hook entries if they are not already present.
add_notify_hooks() {
  python3 - "$SETTINGS" <<'PYEOF'
import json, sys

NOTIFY = "~/.claude/hooks/claude-notify.sh"

NEW_HOOKS = {
    "SessionStart":      [{"matcher": "", "hooks": [{"type": "command", "command": NOTIFY, "async": True}]}],
    "Stop":              [{"matcher": "", "hooks": [{"type": "command", "command": NOTIFY, "async": True}]}],
    "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": NOTIFY}]}],
    "PreToolUse": [
        {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": NOTIFY}]},
        {"matcher": "",               "hooks": [{"type": "command", "command": NOTIFY, "async": True}]},
    ],
    "PostToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": NOTIFY, "async": True}]}],
}

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.get("hooks", {})
added = []

for event, new_entries in NEW_HOOKS.items():
    existing_cmds = {
        h.get("command", "")
        for entry in hooks.get(event, [])
        for h in entry.get("hooks", [])
    }
    for entry in new_entries:
        for h in entry.get("hooks", []):
            if h.get("command") not in existing_cmds:
                hooks.setdefault(event, []).insert(0, entry)
                added.append(event)
                break

cfg["hooks"] = hooks
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)

if added:
    print(f"✓ Added claude-notify.sh entries for: {', '.join(sorted(set(added)))}")
else:
    print("✓ claude-notify.sh hooks already present — nothing changed")
PYEOF
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_disable() {
  if ! settings_exists; then
    echo "✗ $SETTINGS not found — nothing to disable"; exit 1
  fi
  backup_settings
  remove_notify_hooks
  echo ""
  echo "Hooks disabled. Restart Claude Code for the change to take effect."
  echo "Re-enable any time with:  bash manage-claude-hooks.sh enable"
}

cmd_enable() {
  if ! settings_exists; then
    echo "✗ $SETTINGS not found — run install-claude-hooks.sh first"; exit 1
  fi
  backup_settings
  add_notify_hooks
  echo ""
  echo "Hooks enabled. Restart Claude Code for the change to take effect."
}

cmd_uninstall() {
  echo "── Uninstalling Claude Code notification hooks ──"
  echo ""

  # 1. Remove from settings.json
  if settings_exists; then
    backup_settings
    remove_notify_hooks
  else
    echo "⚠  $SETTINGS not found — skipping settings cleanup"
  fi

  # 2. Delete hook scripts
  for f in claude-notify.sh claude-alert-dispatcher.sh toggle-approve-all.sh; do
    target="$HOOK_DIR/$f"
    if [ -f "$target" ]; then
      rm "$target"
      echo "✓ Removed $target"
    fi
  done

  # 3. Remove Hammerspoon hotkey lines
  HS_CONFIG="$HOME/.hammerspoon/init.lua"
  if [ -f "$HS_CONFIG" ] && grep -q "toggle-approve-all" "$HS_CONFIG"; then
    grep -v "toggle-approve-all\|Claude Code: toggle" "$HS_CONFIG" > "${HS_CONFIG}.tmp" \
      && mv "${HS_CONFIG}.tmp" "$HS_CONFIG"
    echo "✓ Removed Hammerspoon hotkey lines from $HS_CONFIG"
    echo "  → Reload Hammerspoon to apply: hs -c 'hs.reload()'"
  fi

  # 4. Remove the Automator Service (Cmd+Shift+M)
  SERVICE_PATH="$HOME/Library/Services/Claude Toggle Approve-All.workflow"
  if [ -d "$SERVICE_PATH" ]; then
    rm -rf "$SERVICE_PATH"
    echo "✓ Removed Automator Service: $SERVICE_PATH"
  fi

  # 5. Revert iTerm2 tab-title setting (optional — non-destructive)
  echo ""
  echo "NOTE: iTerm2 custom tab title format was not reverted automatically."
  echo "  To restore default titles: iTerm2 → Preferences → Profiles → General"
  echo "  → Title: set back to 'Session Name' (or your preference)"

  echo ""
  echo "── Uninstall complete ──"
  echo "Restart Claude Code for settings changes to take effect."
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$1" in
  disable)   cmd_disable   ;;
  enable)    cmd_enable    ;;
  uninstall) cmd_uninstall ;;
  *)         usage         ;;
esac
