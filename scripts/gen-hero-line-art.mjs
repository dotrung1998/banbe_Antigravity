// Writes the iOS twins of Home's hero line art (src/lib/heroLineArt.js) as template vector imagesets in the app's
// existing asset catalog, so both apps draw the exact same sketches. Run after changing a drawing:
//   node scripts/gen-hero-line-art.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { HERO_LINE_ART, heroArtSvg, heroArtAsset } from '../src/lib/heroLineArt.js';

const catalog = new URL('../apps/ios/BanbeApp/Resources/Assets.xcassets/', import.meta.url).pathname;
for (const kind of Object.keys(HERO_LINE_ART)) {
  const name = heroArtAsset(kind);
  const dir = join(catalog, `${name}.imageset`);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${name}.svg`), heroArtSvg(kind));
  writeFileSync(join(dir, 'Contents.json'), `${JSON.stringify({
    images: [{ filename: `${name}.svg`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
  }, null, 2)}\n`);
  console.log(`wrote ${name}.imageset`);
}
