#!/usr/bin/env bash
# Terminal-driven "Screenshot Catalog" for the iOS app.
#
# Boots a dedicated named Simulator, runs ONLY
# BanbeAppUITests/ScreenshotCatalogTests via xcodebuild, exports every
# screenshot attachment that suite recorded, and generates
# docs/demo-screenshots/README.md + manifest.json for presentation use.
#
# Usage:
#   bash scripts/capture_ios_catalog.sh
#
# No manual Xcode clicking, no real device — Simulator only.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/apps/ios"
OUTPUT_DIR="$ROOT_DIR/output/ios-screenshot-catalog"
XCRESULT_PATH="$OUTPUT_DIR/ScreenshotCatalog.xcresult"
EXPORT_DIR="$OUTPUT_DIR/attachments"
DOCS_DIR="$ROOT_DIR/docs/demo-screenshots"

SIM_NAME="${SIM_NAME:-banbe-screenshot-catalog}"
SIM_DEVICE_TYPE="${SIM_DEVICE_TYPE:-iPhone 16 Pro}"
SIM_RUNTIME_NAME="${SIM_RUNTIME_NAME:-}" # empty = newest iOS runtime installed

log() { printf '\033[1;34m[capture_ios_catalog]\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m[capture_ios_catalog] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode command line tools."
command -v xcrun >/dev/null || fail "xcrun not found."
command -v python3 >/dev/null || fail "python3 not found."

# ---------------------------------------------------------------------------
# 1. Regenerate the Xcode project (XcodeGen) — same convention every other
#    build/test invocation in this repo already uses (see .claude/notes and
#    apps/ios/project.yml's own comment: the .xcodeproj is never hand-edited
#    or committed).
# ---------------------------------------------------------------------------
command -v xcodegen >/dev/null || fail "xcodegen not found — 'brew install xcodegen'."
log "Regenerating BanbeApp.xcodeproj via xcodegen…"
(cd "$IOS_DIR" && xcodegen generate)

# ---------------------------------------------------------------------------
# 2. Create/boot a dedicated named Simulator — isolated from whatever
#    Simulators the developer already has, so this suite's signed-in state
#    (the shared fast-suite test account — see ScreenshotCatalogTests.swift's
#    own header comment) doesn't collide with other work.
# ---------------------------------------------------------------------------
resolve_runtime_id() {
    if [ -n "$SIM_RUNTIME_NAME" ]; then
        xcrun simctl list runtimes available -j \
            | python3 -c "import json,sys; rts=json.load(sys.stdin)['runtimes']; m=[r for r in rts if r['name']=='$SIM_RUNTIME_NAME']; print(m[0]['identifier'] if m else '')"
    else
        # Newest available iOS runtime — simulators run any OS >= the app's
        # own deployment target (17.0, apps/ios/project.yml), so "newest" is
        # deliberately not pinned to that minimum.
        xcrun simctl list runtimes available -j \
            | python3 -c "
import json, sys
rts = [r for r in json.load(sys.stdin)['runtimes'] if r['name'].startswith('iOS')]
rts.sort(key=lambda r: [int(x) for x in r['version'].split('.')])
print(rts[-1]['identifier'] if rts else '')
"
    fi
}

resolve_devicetype_id() {
    xcrun simctl list devicetypes -j \
        | python3 -c "
import json, sys
dts = json.load(sys.stdin)['devicetypes']
m = [d for d in dts if d['name'] == '$SIM_DEVICE_TYPE']
if not m:
    m = [d for d in dts if d['name'].startswith('iPhone')]
print(m[0]['identifier'] if m else '')
"
}

RUNTIME_ID="$(resolve_runtime_id)"
[ -n "$RUNTIME_ID" ] || fail "No installed iOS Simulator runtime found (xcrun simctl list runtimes available)."
DEVICETYPE_ID="$(resolve_devicetype_id)"
[ -n "$DEVICETYPE_ID" ] || fail "No iPhone Simulator device type found (xcrun simctl list devicetypes)."

SIM_ID="$(xcrun simctl list devices -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, entries in devices.items():
    for d in entries:
        if d.get('name') == '$SIM_NAME':
            print(d['udid']); sys.exit(0)
")"

if [ -z "$SIM_ID" ]; then
    log "Creating Simulator '$SIM_NAME'…"
    SIM_ID="$(xcrun simctl create "$SIM_NAME" "$DEVICETYPE_ID" "$RUNTIME_ID")"
else
    log "Reusing existing Simulator '$SIM_NAME' ($SIM_ID)"
fi

SIM_STATE="$(xcrun simctl list devices -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, entries in devices.items():
    for d in entries:
        if d.get('udid') == '$SIM_ID':
            print(d.get('state','')); sys.exit(0)
")"
if [ "$SIM_STATE" != "Booted" ]; then
    log "Booting Simulator…"
    xcrun simctl boot "$SIM_ID" 2>/dev/null || true
fi
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null

SIM_MODEL_NAME="$SIM_NAME"
SIM_OS_VERSION="$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
rts = json.load(sys.stdin)['runtimes']
m = [r for r in rts if r['identifier'] == '$RUNTIME_ID']
print(m[0]['version'] if m else '')
")"

# ---------------------------------------------------------------------------
# 3. Build + run ONLY ScreenshotCatalogTests.
# ---------------------------------------------------------------------------
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

log "Running ScreenshotCatalogTests on '$SIM_NAME' (iOS $SIM_OS_VERSION)…"
set +e
xcodebuild test \
    -project "$IOS_DIR/BanbeApp.xcodeproj" \
    -scheme BanbeApp \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -only-testing:BanbeAppUITests/ScreenshotCatalogTests \
    -resultBundlePath "$XCRESULT_PATH" \
    | tee "$OUTPUT_DIR/xcodebuild.log" \
    | grep -E "Test Suite|Test Case|error:|BUILD|\*\*" || true
XCODEBUILD_STATUS="${PIPESTATUS[0]}"
set -e

[ -d "$XCRESULT_PATH" ] || fail "xcodebuild did not produce a result bundle at $XCRESULT_PATH — see $OUTPUT_DIR/xcodebuild.log"

# A screenshot suite failing an XCTAssertTrue (e.g. sign-in itself failing)
# should stop the catalog build clearly rather than silently generating a
# partial/misleading README — opportunistic flows use `skip(_:)` (a
# non-failing activity note) precisely so THEIR absence doesn't trip this.
if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
    log "xcodebuild reported failures — inspecting whether any screenshots were still captured…"
fi

# ---------------------------------------------------------------------------
# 4. Export every screenshot + metadata attachment.
#
#    Per this ticket's own instruction: inspected
#    `xcrun xcresulttool export attachments --help` (and --schema) first,
#    rather than guessing. Confirmed syntax on this machine (xcresulttool
#    25115):
#      xcrun xcresulttool export attachments --path <xcresult> \
#          --output-path <dir>
#    which exports every attachment as a flat file AND writes its own
#    manifest.json describing each one: {testIdentifier, attachments:
#    [{exportedFileName, suggestedHumanReadableName, ...}]}.
#    `suggestedHumanReadableName` is what carries the `XCTAttachment.name`
#    we set in ScreenshotCatalogTests.swift's `capture()` helper
#    (`<group>/<order>-<slug>` for the PNG, `<group>/<order>-<slug>.meta`
#    for its JSON sidecar) — the python step below reads that back out.
# ---------------------------------------------------------------------------
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
log "Exporting attachments…"
xcrun xcresulttool export attachments \
    --path "$XCRESULT_PATH" \
    --output-path "$EXPORT_DIR"

[ -f "$EXPORT_DIR/manifest.json" ] || fail "xcresulttool did not produce $EXPORT_DIR/manifest.json"

# ---------------------------------------------------------------------------
# 5. Rename exported files deterministically, build
#    docs/demo-screenshots/README.md + manifest.json.
# ---------------------------------------------------------------------------
log "Building docs/demo-screenshots/ …"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
python3 "$ROOT_DIR/scripts/lib/build_screenshot_catalog.py" \
    --export-dir "$EXPORT_DIR" \
    --docs-dir "$DOCS_DIR" \
    --sim-name "$SIM_MODEL_NAME" \
    --sim-os "$SIM_OS_VERSION" \
    --generated-at "$GENERATED_AT"

log "Done. See $DOCS_DIR/README.md"
if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
    log "Note: xcodebuild exited non-zero (some assertions failed) — check $OUTPUT_DIR/xcodebuild.log. The catalog above reflects whatever WAS captured before/around that failure."
    exit "$XCODEBUILD_STATUS"
fi
