#!/usr/bin/env bash
# Generates WebP derivatives of public/photos into public/photos/optimized/.
#
# The source photos are only 1000px wide but were saved at very high JPEG
# quality — ~360KB each, 3-4x more than that resolution needs. WebP at q82
# is visually indistinguishable (checked side by side on a noisy night shot)
# and lands around 95KB, so the iOS feed pulls roughly a quarter of the
# bytes for the same pixels. Dimensions are left alone, so nothing gets
# softer on a 3x display.
#
# The iOS client asks for the derivative and falls back to the original if
# it isn't there (see RemoteImage), so this staying un-deployed only costs
# speed, never correctness.
#
# Requires cwebp:  brew install webp
# Run from the repo root:  ./apps/ios/Tools/optimize-photos.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
src="$root/public/photos"
out="$src/optimized"

if ! command -v cwebp >/dev/null; then
  echo "cwebp not found — install it with: brew install webp" >&2
  exit 1
fi

mkdir -p "$out"
count=0
for file in "$src"/*.jpg "$src"/*.png; do
  [ -e "$file" ] || continue
  name="$(basename "${file%.*}")"
  target="$out/$name.webp"
  if [ -f "$target" ] && [ "$target" -nt "$file" ]; then continue; fi
  cwebp -quiet -q 82 "$file" -o "$target"
  count=$((count + 1))
done

before=$(find "$src" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' \) -exec stat -f%z {} + | awk '{s+=$1} END {print s}')
after=$(find "$out" -type f -name '*.webp' -exec stat -f%z {} + | awk '{s+=$1} END {print s}')
printf 'Wrote %d file(s) to %s\n' "$count" "$out"
printf 'Originals: %.1f MB → WebP: %.1f MB (%.0f%% smaller)\n' \
  "$(echo "$before/1048576" | bc -l)" \
  "$(echo "$after/1048576" | bc -l)" \
  "$(echo "(1 - $after/$before) * 100" | bc -l)"
