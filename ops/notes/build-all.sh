#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
TSV="$REPO_ROOT/ops/notes/sites.tsv"

while IFS=$'\t' read -r slug vault repo title serve_port public_port; do
  [ -z "${slug:-}" ] && continue
  case "$slug" in \#*) continue;; esac
  [ -d "$vault" ] || { echo "missing vault: $vault"; exit 1; }

  rm -f "$QUARTZ_DIR/content-$slug"
  ln -s "$vault" "$QUARTZ_DIR/content-$slug"

  # v5.1.0 không có -C: đặt config đúng vào quartz.config.yaml trước khi build.
  cp "$QUARTZ_DIR/quartz.config.$slug.yaml" "$QUARTZ_DIR/quartz.config.yaml"

  mkdir -p "$SITES_ROOT/$slug"
  rm -rf "$SITES_ROOT/$slug/public"
  ( cd "$QUARTZ_DIR" && CI=1 npx quartz build \
      -d "content-$slug" \
      -o "$SITES_ROOT/$slug/public" )

  # Quartz 5.1.0 folder-page only covers subfolders, never the content root, so a
  # vault without index.md gets no /index.html. Publish its home page at / instead.
  if [ ! -f "$SITES_ROOT/$slug/public/index.html" ]; then
    for home in home readme start-here; do
      if [ -f "$SITES_ROOT/$slug/public/$home.html" ]; then
        cp "$SITES_ROOT/$slug/public/$home.html" "$SITES_ROOT/$slug/public/index.html"
        echo "index.html from $home.html ($slug)"
        break
      fi
    done
  fi

  test -f "$SITES_ROOT/$slug/public/index.html"
  test ! -e "$SITES_ROOT/$slug/public/.obsidian"
  echo "built $slug"
done < "$TSV"
