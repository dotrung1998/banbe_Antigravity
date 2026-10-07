# Keychain charm designs - licensing

- All 24 built-in designs (`svg/*.svg` and the PNGs generated from them) are original works authored for banbe in this repository.
- License: (c) banbe, all rights reserved for the app; users may export the PNGs for personal use as keychain charm art.
- No third-party sources: no stock art, icon packs, fonts, emoji sets, licensed or trademarked characters. The cat and bear are generic original shapes.
- No scraped or downloaded material was used.
- User-supplied custom art (the reserved `custom` design) is the responsibility of the user who uploads it; they must hold the rights to it.
- SVG is source-only. It is rasterised at build time by `scripts/build-keychains.mjs` and is never accepted as a user upload (custom art is PNG or WebP only, re-encoded client-side and validated server-side).
