#!/bin/bash
# Daily audit nudge, started by launchd at 09:00 every day.
#
#   1. Puts the Mission goal on the clipboard.
#   2. Brings Freebuff Desktop up.
#   3. Posts a notification naming the one manual step: Cmd+O, choose banbe.
#
# Why this is installed outside the repo: a LaunchAgent cannot read ~/Downloads
# (macOS TCC), and that is where the project lives. install.sh copies this runner
# and the extracted goal to ~/Library/Application Support/banbe/, which launchd
# can read, and the plist points there. The repo copy is the source.
#
# Freebuff Desktop has no project deep link: the freebuff:// scheme only handles
# auth and the app declares no document types, so the folder argument below is a
# best-effort hint that the app ignores. When it ignores it, the app reopens its
# last project; otherwise the notification is the reminder to pick banbe.
#
# Logs: ~/Library/Logs/banbe-daily-audit.log (and .err.log)
set -euo pipefail

PROJECT_DIR="/Users/thetrungdo/Downloads/banbe"
HERE="$(cd "$(dirname "$0")" && pwd)"
GOAL_FILE="${AUDIT_GOAL_FILE:-$HERE/audit-goal.txt}"

[ -f "$GOAL_FILE" ] || { echo "missing goal file: $GOAL_FILE" >&2; exit 1; }

# No trailing-newline surprises: the file is written by install.sh.
GOAL=$(/bin/cat "$GOAL_FILE")
[ -n "$GOAL" ] || { echo "empty goal file: $GOAL_FILE" >&2; exit 1; }

printf '%s\n' "$GOAL" | /usr/bin/pbcopy

/usr/bin/open -a Freebuff "$PROJECT_DIR" 2>/dev/null || /usr/bin/open -a Freebuff

# The folder argument is ignored, so say the step out loud. Notification
# permission decides whether this is visible; the log line always records it.
if /usr/bin/osascript -e 'display notification "If banbe is not already open, press Cmd+O and choose Downloads/banbe. The audit brief is on your clipboard." with title "banbe audit" sound name "Glass"' >/dev/null 2>&1; then
  NOTIFY="notification=sent"
else
  NOTIFY="notification=failed (enable Script Editor in Notifications)"
fi

CHARS=$(printf '%s' "$GOAL" | /usr/bin/wc -c | /usr/bin/tr -d ' ')
echo "$(/bin/date '+%F %T %Z') clipboard=${CHARS} chars; next: Cmd+O -> $PROJECT_DIR; $NOTIFY"
