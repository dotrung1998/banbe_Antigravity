#!/usr/bin/env bash
# Builds PersonalTeamDebug, installs it and launches it on a physical iPhone — one command.
#
#   ./apps/ios/Tools/run-on-device.sh                 # TD Pro Max (the owner's phone)
#   ./apps/ios/Tools/run-on-device.sh "Some iPhone"   # any connected device, by name
#   ./apps/ios/Tools/run-on-device.sh <UDID>
#
# PersonalTeamDebug is the free/personal-Apple-ID config
# (.claude/notes/18-ios-personal-team-signing.md): no Push, no Associated Domains,
# bundle id com.thetrung.banbe.dev, Home Screen name "Banbe Dev" — so it installs
# beside a normal "banbe" build. It names its own team in
# Config/PersonalTeamDebug.xcconfig, so no DEVELOPMENT_TEAM has to be passed here.
# Debug/Release sign with the paid team from Config/Team.xcconfig and are NOT what
# this script builds.
#
# Requirements: Xcode with the personal Apple Account signed in (Xcode > Settings >
# Accounts), the iPhone paired (plugged in or on the same Wi-Fi), xcodegen installed,
# and the iPhone unlocked and trusted while this runs.
#
# See also: docs/push-setup.md once there is a paid Apple Developer account.

set -euo pipefail

scheme="PersonalTeamDebug"
configuration="PersonalTeamDebug"
requested="${1:-TD Pro Max}"

ios_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ios_dir"

# --- device --------------------------------------------------------------------------------------
if [[ "$requested" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}- ]]; then
  udid="$requested"
else
  # `devicectl list devices` prints a table; the Reality column says "physical" for real
  # hardware, and the Identifier column carries the UDID right before " (UDID)". Take the
  # token before that marker rather than assuming a shape: a real iPhone's UDID looks like
  # 00008130-000431883A21001C (8-16), not a simulator's 8-4-4-4-12 UUID.
  udid="$(xcrun devicectl list devices 2>/dev/null \
    | grep -F "physical" \
    | grep -F "$requested" \
    | sed -nE 's/.*[[:space:]]([0-9A-Fa-f-]{7,}) \(UDID\).*/\1/p' \
    | head -1 || true)"
fi

if [[ -z "${udid:-}" ]]; then
  echo "No connected iPhone matching \"$requested\". Physical devices right now:" >&2
  xcrun devicectl list devices 2>/dev/null | grep -F "physical" >&2 || echo "  (none)" >&2
  exit 1
fi

echo "▸ Device: $requested ($udid)"

# --- build ---------------------------------------------------------------------------------------
# BanbeApp.xcodeproj is generated output (not committed) and goes stale as soon as a
# source file is added or removed, so regenerate it every time — it is fast.
xcodegen generate >/dev/null
echo "▸ Building $scheme… (the first build takes a few minutes)"

derived="$ios_dir/.build/DerivedData"
build_log="$(mktemp -t banbe-ios-build)"
if ! xcodebuild \
  -project BanbeApp.xcodeproj \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination "id=$udid" \
  -allowProvisioningUpdates \
  -derivedDataPath "$derived" \
  build >"$build_log" 2>&1; then
  echo "✗ Build failed. Last lines of the log ($build_log):" >&2
  tail -40 "$build_log" >&2
  exit 1
fi
echo "✓ Built"

app="$derived/Build/Products/$configuration-iphoneos/BanbeApp.app"
if [[ ! -d "$app" ]]; then
  echo "✗ Built app not found at $app" >&2
  exit 1
fi
bundle_id="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")"

# --- install + launch ----------------------------------------------------------------------------
echo "▸ Installing $bundle_id (keep the iPhone unlocked)…"
xcrun devicectl device install app --device "$udid" "$app" >/dev/null

echo "▸ Launching…"
xcrun devicectl device process launch --device "$udid" "$bundle_id" >/dev/null

echo "✓ Running on $requested"
