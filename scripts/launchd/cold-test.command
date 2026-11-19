#!/bin/bash
# Cold-launch proof for com.banbe.daily-audit, with hard assertions.
#
# Usage, from Terminal (not from inside Freebuff: quitting the app ends the
# process that would otherwise run the test):
#
#   ./scripts/launchd/cold-test.command
#
# Prints RESULT: PASS or RESULT: FAIL - <reason>, and appends the transcript to
# ~/Library/Logs/banbe-coldtest.log. Freebuff reopens on its own.
set -uo pipefail
LOG="$HOME/Library/Logs/banbe-coldtest.log"
AGENT_LOG="$HOME/Library/Logs/banbe-daily-audit.log"
GOAL="$HOME/Library/Application Support/banbe/audit-goal.txt"
exec > >(tee -a "$LOG") 2>&1

fail() { echo "RESULT: FAIL - $1"; exit 1; }
main_pid() { /bin/ps -axo pid,command | /usr/bin/awk '/Freebuff\.app\/Contents\/MacOS\/Freebuff$/ {print $1}' | /usr/bin/head -1; }

echo "=== $(/bin/date '+%F %T %Z') cold test (asserting) ==="
echo "waiting 30s so the chat can finish..."
/bin/sleep 30

OLD_PID=$(main_pid)
echo "main pid before quit: ${OLD_PID:-none}"
[ -n "$OLD_PID" ] || fail "no Freebuff main process to quit"
LOG_BEFORE=$(/usr/bin/tail -1 "$AGENT_LOG" 2>/dev/null || true)

/bin/kill -TERM "$OLD_PID" 2>/dev/null || true
for i in $(/usr/bin/seq 1 40); do
  [ -z "$(main_pid)" ] && break
  /bin/sleep 1
done
if [ -n "$(main_pid)" ]; then
  echo "still running after 40s; sending SIGKILL"
  /bin/kill -KILL "$OLD_PID" 2>/dev/null || true
  /bin/sleep 3
fi
[ -z "$(main_pid)" ] || fail "Freebuff did not quit (pid $(main_pid) still alive)"
echo "main processes after quit: 0"

/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.banbe.daily-audit"
KS=$?
echo "kickstart exit: $KS"
[ "$KS" -eq 0 ] || fail "kickstart returned $KS"

NEW_PID=""
for i in $(/usr/bin/seq 1 30); do
  NEW_PID=$(main_pid)
  [ -n "$NEW_PID" ] && break
  /bin/sleep 1
done
[ -n "$NEW_PID" ] || fail "Freebuff did not start after kickstart"
[ "$NEW_PID" != "$OLD_PID" ] || fail "same pid $NEW_PID; this was not a cold start"
echo "cold-launched pid: $NEW_PID"
/bin/ps -p "$NEW_PID" -o pid,lstart,command | /usr/bin/tail -1

LOG_AFTER=$(/usr/bin/tail -1 "$AGENT_LOG")
[ "$LOG_AFTER" != "$LOG_BEFORE" ] || fail "agent log did not gain a line"
echo "$LOG_AFTER" | /usr/bin/grep -q "notification=sent" || fail "agent logged no notification"
echo "agent log: $LOG_AFTER"

ACTUAL=$(/usr/bin/pbpaste | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
EXPECTED=$(/usr/bin/shasum -a 256 "$GOAL" | /usr/bin/awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || fail "clipboard hash mismatch"
echo "clipboard: MATCH ($(/usr/bin/pbpaste | /usr/bin/wc -c | /usr/bin/tr -d ' ') chars)"

echo "RESULT: PASS - cold start, clipboard, and notification post verified"
echo "NOTE: banner display still depends on Focus/permission; watch the screen."
