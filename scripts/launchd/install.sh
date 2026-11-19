#!/bin/bash
# Installs the daily audit nudge and keeps the clipboard copy in sync with
# docs/audit-brief.md. Re-run this after editing the brief.
#
# A LaunchAgent cannot read ~/Downloads on macOS (TCC), so the runner and the
# extracted goal live in ~/Library/Application Support/banbe/. The plist in
# ~/Library/LaunchAgents points at the installed runner, not at this repo.
set -euo pipefail

PROJECT_DIR="/Users/thetrungdo/Downloads/banbe"
DEST="$HOME/Library/Application Support/banbe"
PLIST="$HOME/Library/LaunchAgents/com.banbe.weekly-audit.plist"
LABEL="com.banbe.weekly-audit"
DOMAIN="gui/$(id -u)"

[ -f "$PROJECT_DIR/docs/audit-brief.md" ] || { echo "missing audit brief" >&2; exit 1; }

/bin/mkdir -p "$DEST"

/usr/bin/awk '/GOAL-START/{f=1;next} /GOAL-END/{f=0} f' "$PROJECT_DIR/docs/audit-brief.md" \
  | /usr/bin/sed -e '/^```/d' -e '/./,$!d' > "$DEST/audit-goal.txt"
[ -s "$DEST/audit-goal.txt" ] || { echo "goal block is empty" >&2; exit 1; }

/bin/cp "$PROJECT_DIR/scripts/launchd/weekly-audit-open.sh" "$DEST/audit-runner.sh"
/bin/chmod +x "$DEST/audit-runner.sh"
/bin/cp "$PROJECT_DIR/scripts/launchd/com.banbe.weekly-audit.plist" "$PLIST"
/usr/bin/plutil -lint "$PLIST"

# Reload on the spot if the job is already registered, so edits take effect.
if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  /bin/launchctl bootout "$DOMAIN/$LABEL"
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "reloaded $LABEL"
fi

echo "installed $DEST/audit-runner.sh ($(/usr/bin/wc -c < "$DEST/audit-goal.txt" | /usr/bin/tr -d ' ') goal chars)"
