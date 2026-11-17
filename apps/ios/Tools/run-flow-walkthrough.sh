#!/usr/bin/env bash
# Runs BanbeAppUITests/FlowWalkthroughUITests — one XCUITest that taps and types
# through a real multi-screen flow — and exports one PNG per step, in flow
# order, so the run can be reviewed screen by screen.
#
# Usage:
#   apps/ios/Tools/run-flow-walkthrough.sh                 # booted/new Simulator
#   SIM_ID=<udid> apps/ios/Tools/run-flow-walkthrough.sh   # a specific Simulator
#
# Output:
#   output/ios-flow-walkthrough/steps/NN-slug.png   one file per step
#   output/ios-flow-walkthrough/xcodebuild.log      the full run log
#   output/ios-flow-walkthrough/FlowWalkthrough.xcresult
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
OUTPUT_DIR="$ROOT_DIR/output/ios-flow-walkthrough"
XCRESULT_PATH="$OUTPUT_DIR/FlowWalkthrough.xcresult"
EXPORT_DIR="$OUTPUT_DIR/attachments"
STEPS_DIR="$OUTPUT_DIR/steps"
# Same DerivedData run-on-device.sh uses, so a repeat run is incremental.
DERIVED_DATA="$IOS_DIR/.build/DerivedData"

log() { printf '\033[1;34m[run-flow-walkthrough]\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m[run-flow-walkthrough] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode."
command -v xcrun >/dev/null || fail "xcrun not found."
command -v python3 >/dev/null || fail "python3 not found."

# The .xcodeproj is generated output (see project.yml) — regenerate so a new
# test file is picked up.
if command -v xcodegen >/dev/null; then
    log "Regenerating BanbeApp.xcodeproj via xcodegen…"
    (cd "$IOS_DIR" && xcodegen generate >/dev/null)
fi

# ---------------------------------------------------------------------------
# Destination: an explicit SIM_ID, else the Simulator that is already booted
# (the common case when Xcode/simctl has one running), else the newest iPhone
# runtime's newest iPhone device.
# ---------------------------------------------------------------------------
if [ -z "${SIM_ID:-}" ]; then
    SIM_ID="$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
for entries in json.load(sys.stdin)['devices'].values():
    for d in entries:
        if d.get('state') == 'Booted' and d.get('name', '').startswith('iPhone'):
            print(d['udid']); sys.exit(0)
")"
fi

if [ -z "${SIM_ID:-}" ]; then
    log "No booted iPhone Simulator — creating and booting one…"
    RUNTIME_ID="$(xcrun simctl list runtimes available -j | python3 -c "
import json, sys
rts = [r for r in json.load(sys.stdin)['runtimes'] if r['name'].startswith('iOS')]
rts.sort(key=lambda r: [int(x) for x in r['version'].split('.')])
print(rts[-1]['identifier'] if rts else '')
")"
    DEVICE_TYPE_ID="$(xcrun simctl list devicetypes -j | python3 -c "
import json, sys
dts = [d for d in json.load(sys.stdin)['devicetypes'] if d['name'].startswith('iPhone')]
print(dts[0]['identifier'] if dts else '')
")"
    [ -n "$RUNTIME_ID" ] || fail "No installed iOS Simulator runtime."
    [ -n "$DEVICE_TYPE_ID" ] || fail "No iPhone Simulator device type."
    SIM_ID="$(xcrun simctl create banbe-flow-walkthrough "$DEVICE_TYPE_ID" "$RUNTIME_ID")"
    xcrun simctl boot "$SIM_ID"
    xcrun simctl bootstatus "$SIM_ID" -b >/dev/null
fi

SIM_LABEL="$(xcrun simctl list devices -j | python3 -c "
import json, sys
for entries in json.load(sys.stdin)['devices'].values():
    for d in entries:
        if d.get('udid') == '$SIM_ID':
            print(d.get('name','') + ' (iOS ' + str(d.get('os','')) + ')'); sys.exit(0)
")"
log "Running FlowWalkthroughUITests on: $SIM_LABEL"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$STEPS_DIR"

set +e
xcodebuild test \
    -project "$IOS_DIR/BanbeApp.xcodeproj" \
    -scheme BanbeApp \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:BanbeAppUITests/FlowWalkthroughUITests \
    -resultBundlePath "$XCRESULT_PATH" \
    > "$OUTPUT_DIR/xcodebuild.log" 2>&1
STATUS=$?
set -e

grep -E "Test Case .*(passed|failed)|error:" "$OUTPUT_DIR/xcodebuild.log" | tail -20 || true

[ -d "$XCRESULT_PATH" ] || fail "No result bundle at $XCRESULT_PATH — see $OUTPUT_DIR/xcodebuild.log"

# ---------------------------------------------------------------------------
# Export the step screenshots. xcresulttool writes its own manifest.json
# describing each attachment; `suggestedHumanReadableName` holds our
# `step-NN-slug` plus a "_<index>_<uuid>" suffix it adds, so the suffix is
# stripped and the files are sorted by the zero-padded step number.
# ---------------------------------------------------------------------------
log "Exporting step screenshots…"
xcrun xcresulttool export attachments --path "$XCRESULT_PATH" --output-path "$EXPORT_DIR" >/dev/null
[ -f "$EXPORT_DIR/manifest.json" ] || fail "xcresulttool produced no manifest.json"

python3 - "$EXPORT_DIR" "$STEPS_DIR" <<'PY'
import json, re, shutil, sys
from pathlib import Path

export_dir, steps_dir = Path(sys.argv[1]), Path(sys.argv[2])
suffix = re.compile(r"_\d+_[0-9A-Fa-f-]{36}\.(\w+)$")

written = 0
for test_entry in json.loads((export_dir / "manifest.json").read_text()):
    for att in test_entry.get("attachments", []):
        name = att.get("suggestedHumanReadableName", "")
        src = export_dir / att.get("exportedFileName", "")
        if not name.startswith("step-") or not src.suffix.lower() == ".png":
            continue
        core = suffix.sub("", name)
        shutil.copyfile(src, steps_dir / f"{core}.png")
        written += 1

if not written:
    sys.exit("no step screenshots were exported")
print(f"{written} step screenshot(s)")
PY

log "Done. Steps:"
ls -1 "$STEPS_DIR"

if [ "$STATUS" -ne 0 ]; then
    fail "The walkthrough failed — read $OUTPUT_DIR/xcodebuild.log (steps above show how far it got)."
fi
