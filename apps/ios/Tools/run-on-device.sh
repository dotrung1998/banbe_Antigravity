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
# Before building it fetches origin/main and merges it into the current branch,
# so one command always installs the newest commits rather than whatever happens
# to be checked out. That step is conservative: an offline fetch, a detached
# HEAD, a dirty tree, or a merge conflict never leaves the checkout worse — see
# sync_origin_main below, which prints what it decided.
#
# See also: docs/push-setup.md once there is a paid Apple Developer account.

set -euo pipefail

scheme="PersonalTeamDebug"
configuration="PersonalTeamDebug"
requested="${1:-TD Pro Max}"
# PersonalTeamDebug's app id; its widget's profile is <this>.LiveActivity.
app_bundle_id="com.thetrung.banbe.dev"
# Warn this many days before the profile expires (override: BANBE_PROFILE_WARN_DAYS).
profile_warn_days="${BANBE_PROFILE_WARN_DAYS:-3}"

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

# --- newest commits -------------------------------------------------------------------------------
# Fetch and integrate origin/main so the phone gets the newest code, not whatever is
# checked out. Never destructive: no fetch (offline), no git checkout, detached HEAD or
# uncommitted tracked changes all just build the local checkout, and a conflicted merge is
# aborted back to exactly the state it started in.
repo_root="$(cd "$ios_dir/../.." && pwd)"

sync_origin_main() {
  local head_before incoming dirty merge_log conflicts

  if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "▸ Not a git checkout — building the files here as they are"
    return 0
  fi
  if [ -z "$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null)" ]; then
    echo "▸ Detached HEAD — not updating, building what is checked out"
    return 0
  fi

  head_before="$(git -C "$repo_root" rev-parse --short HEAD)"
  if ! git -C "$repo_root" fetch --quiet origin main 2>/dev/null; then
    echo "▸ Could not fetch origin/main (offline?) — building the local checkout at $head_before" >&2
    return 0
  fi

  incoming="$(git -C "$repo_root" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "$incoming" = "0" ]; then
    echo "▸ Already at origin/main ($head_before)"
    return 0
  fi

  dirty="$(git -C "$repo_root" status --porcelain --untracked-files=no)"
  if [ -n "$dirty" ]; then
    echo "▸ origin/main is $incoming commit(s) ahead, but this checkout has uncommitted changes"
    echo "  — building them as they are; commit or stash to include the new commits next run"
    return 0
  fi

  echo "▸ Integrating $incoming commit(s) from origin/main…"
  merge_log="$(mktemp -t banbe-ios-merge)"
  if ! git -C "$repo_root" merge --no-edit origin/main >"$merge_log" 2>&1; then
    conflicts="$(grep -E '^CONFLICT' "$merge_log" | head -10 || true)"
    echo "✗ Could not merge origin/main into $(git -C "$repo_root" rev-parse --abbrev-ref HEAD):" >&2
    if [ -n "$conflicts" ]; then
      echo "$conflicts" >&2
    else
      tail -10 "$merge_log" >&2
    fi
    git -C "$repo_root" merge --abort 2>/dev/null || true
    echo "  Merge aborted — the checkout is exactly as it was ($head_before). Resolve by hand, then rerun." >&2
    exit 1
  fi
  echo "✓ Now at $(git -C "$repo_root" rev-parse --short HEAD) — $(git -C "$repo_root" log -1 --format=%s)"
}

sync_origin_main

# --- build ---------------------------------------------------------------------------------------
# BanbeApp.xcodeproj is generated output (not committed) and goes stale as soon as a
# source file is added or removed, so regenerate it every time — it is fast.
xcodegen generate >/dev/null

# The team is never committed: PersonalTeamDebug includes this gitignored file optionally.
team_file="$ios_dir/Config/PersonalTeam.xcconfig"
if [[ ! -f "$team_file" ]]; then
  echo "! No Config/PersonalTeam.xcconfig — create it once with your own team ID:" >&2
  echo "    echo \"DEVELOPMENT_TEAM = <10-character team id>\" > Config/PersonalTeam.xcconfig" >&2
  echo "  (Xcode > Settings > Accounts shows the ID.)" >&2
fi

# --- profile expiry -------------------------------------------------------------------------------
# A free Apple ID's device profile only lasts about a week. The build below passes
# -allowProvisioningUpdates, which normally re-issues an expiring profile, and pressing
# Run once in Xcode does too — but without a warning an expired profile otherwise shows
# up as a confusing "developer cannot be verified"/signing failure on the phone.
check_profile_expiry() {
  local dir f decoded appid exp exp_epoch now earliest_epoch="" earliest_exp="" earliest_file="" found=0 days

  now="$(date +%s)"
  for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
             "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.mobileprovision; do
      [ -f "$f" ] || continue
      decoded="$(mktemp -t banbe-profile)"
      # A .mobileprovision is a CMS-signed plist; a plain plist (already decoded) also
      # works, which keeps this independent of how the profile was stored.
      if ! security cms -D -i "$f" >"$decoded" 2>/dev/null; then
        cp "$f" "$decoded"
      fi
      appid="$(plutil -extract Entitlements.application-identifier raw -o - "$decoded" 2>/dev/null || true)"
      exp="$(plutil -extract ExpirationDate raw -o - "$decoded" 2>/dev/null || true)"
      rm -f "$decoded"
      # Matches both the app and its Live Activity widget profile.
      case "$appid" in
        *"$app_bundle_id"*) ;;
        *) continue ;;
      esac
      exp_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s 2>/dev/null || true)"
      [ -n "$exp_epoch" ] || continue
      found=$((found + 1))
      if [ -z "$earliest_epoch" ] || [ "$exp_epoch" -lt "$earliest_epoch" ]; then
        earliest_epoch="$exp_epoch"
        earliest_exp="$exp"
        earliest_file="$(basename "$f")"
      fi
    done
  done

  if [ "$found" = "0" ]; then
    echo "▸ No provisioning profile for $app_bundle_id yet — Xcode creates one during the build"
    return 0
  fi

  days=$(( (earliest_epoch - now) / 86400 ))
  if [ "$earliest_epoch" -le "$now" ]; then
    echo "✗ Provisioning profile EXPIRED on $earliest_exp ($earliest_file)." >&2
    echo "  Installing will fail until it is renewed: run this script again once Xcode re-issues" >&2
    echo "  it, or open BanbeApp.xcodeproj in Xcode and press Run once." >&2
  elif [ "$days" -lt "$profile_warn_days" ]; then
    echo "! Provisioning profile expires in $days day(s), on $earliest_exp ($earliest_file)." >&2
    echo "  Free Apple IDs issue ~7-day profiles. The build below passes -allowProvisioningUpdates," >&2
    echo "  which normally renews it; if the app later refuses to launch, rerun this script." >&2
  else
    echo "▸ Provisioning profile valid until $earliest_exp ($days days)"
  fi
}

check_profile_expiry

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
