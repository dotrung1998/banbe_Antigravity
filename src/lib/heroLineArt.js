// Line-art illustrations for Home's hero end cards (the "See all N" card when there are too few photos to fan, and the
// "Try instead" suggestion cards). One sketch per meaning, drawn like an architectural line sketch: thin uniform
// strokes, round caps and joins, no fills. Every sketch lives in a 228 × 140 box (the card's inner width at 1:1), so
// a 1.5 stroke renders as 1.5 px / pt on both apps.
//
// This file is the ONE source of the drawings. Web renders it inline (src/components/home/HeroLineArt.jsx, stroke =
// currentColor); iOS ships the same paths as template vector imagesets in Resources/Assets.xcassets/HeroArt*.imageset,
// written by `node scripts/gen-hero-line-art.mjs` (tests/unit/heroLineArt.test.mjs fails when they drift apart).

export const HERO_ART_BOX = { width: 228, height: 140, stroke: 1.5 };

const scallops = (n, w) => Array.from({ length: n }, () => `a${w / 2} ${w / 2} 0 0 0 ${w} 0`).join('');

export const HERO_LINE_ART = {
  // A street of shopfronts at night: lit shop windows, a balcony, a lamp post, crescent moon and stars.
  tonight: [
    'M6 128H222',
    'M14 128V50H74V128M10 50H74M12 45H74M12 45V50',
    'M22 60h14v16H22zM52 60h14v16H52zM29 60v16M59 60v16M25 72l4-4M55 72l4-4',
    'M16 92H72L68 100H20ZM30 92l-1 8M44 92v8M58 92l1 8',
    'M20 106h30v22H20zM35 106v5M31 115a4 4 0 0 1 8 0zM56 128V106h12v22',
    'M74 128V40L104 22L134 40V128M100 34a4 4 0 1 0 8 0a4 4 0 1 0-8 0',
    'M82 50h12v16H82zM98 50h12v16H98zM114 50h12v16H114z',
    'M80 70H128M80 76H128M80 70v6M88 70v6M96 70v6M104 70v6M112 70v6M120 70v6M128 70v6',
    'M78 82h52v8H78zM86 128V110a18 18 0 0 1 36 0V128M104 92V128M86 110H122',
    'M134 128V56H194V128M134 56H198',
    'M142 64h14v16H142zM172 64h14v16H172zM149 64v16M179 64v16',
    `M136 92H192M136 92v6M192 92v6M136 98${scallops(7, 8)}`,
    'M140 104h30v24M140 104v24M146 112h18M176 128V104h12v24',
    'M206 128V80q0-10 8-10M200 128h12M212 68h8l-2 7h-4zM216 79v4M211 78l-2.5 3M221 78l2.5 3',
    'M198 14a10 10 0 1 0 8 16a8 8 0 0 1-8-16z',
    'M60 18v6M57 21h6M150 12v5M147.5 14.5h5M30 28v4M28 30h4M170 30v4M168 32h4',
  ],
  // A park pavilion on a weekend afternoon: hip roof, railings, string lights to two trees, sun and birds.
  weekend: [
    'M6 128H222',
    'M70 58L114 34L158 58ZM114 34v-8M82 51.5H146M95 44.5H133M66 58H162v4H66z',
    'M74 62V122M98 62V122M130 62V122M154 62V122M68 122H160V128M68 122V128',
    'M74 100H98M130 100H154M80 100v22M86 100v22M92 100v22M136 100v22M142 100v22M148 100v22',
    'M14 98c-7-1-7-12 1-14c-1-9 9-14 15-9c5-6 16-2 15 6c7 2 7 13 0 15c-2 2-5 2-7 2zM28 128V98M28 110l-6-6M28 106l6-6',
    'M186 98c-7-1-7-12 1-14c-1-9 9-14 15-9c5-6 16-2 15 6c7 2 7 13 0 15c-2 2-5 2-7 2zM200 128V98M200 110l6-6M200 106l-6-6',
    'M66 60Q54 76 42 84M162 60Q174 76 188 84M58 68v3M50 75v3M170 68v3M178 75v3',
    'M183 26a7 7 0 1 0 14 0a7 7 0 1 0-14 0M190 13v-4M190 39v4M177 26h-4M203 26h4M180.8 16.8l-2.8-2.8M199.2 16.8l2.8-2.8',
    'M30 30q4-4 8 0q4-4 8 0M52 22q3-3 6 0q3-3 6 0',
  ],
  // A city block skyline: window grids, a setback tower with an antenna, a domed hall, a slanted tower, a water tank.
  all: [
    'M6 128H222',
    'M16 128V64H44V128M20 74h20M20 84h20M20 94h20M20 104h20M30 70v40M26 128v-8h8v8',
    'M50 128V48H56V38H62V30H70V38H76V48H82V128M66 30V16M58 56v60M66 56v60M74 56v60M54 60h24M54 72h24M54 84h24M54 96h24M54 108h24',
    'M90 128V82H138V128M98 82a16 16 0 0 1 32 0M114 66v-6M90 92H138M98 92v36M106 92v36M114 92v36M122 92v36M130 92v36',
    'M146 128V50L174 40V128M150 62h20M150 76h20M150 90h20M150 104h20M150 118h20',
    'M180 128V76H214V128M190 76V68M202 76V68M186 68h20M188 68V58h16V68M188 58l8-4l8 4',
    'M186 86h8v8h-8zM200 86h8v8h-8zM186 102h8v8h-8zM200 102h8v8h-8z',
    'M104 24h24M114 30h30M20 40h16',
  ],
  // Browse by type: five small vignettes, a supper table, a gallery frame, a speaker and notes, a clothes rack, a
  // market stall.
  browse: [
    'M10 62H66M14 52H62M20 52V62M56 52V62',
    'M22 34q0 10 4 10q4 0 4-10zM26 44v8M23 52h6',
    'M38 52V40h4v12M40 40v-3M40 36c-2-2-1-4 0-6c1 2 2 4 0 6z',
    'M45 48h14M46 48a6 4 0 0 0 12 0',
    'M88 62h52M92 14h44v34H92zM96 18h36v26H96zM98 40l10-10l8 7l5-4l9 7M121.5 25a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M100 14L114 6L128 14M98 58h32M102 58v4M126 58v4',
    'M164 62h52M170 22h22v40h-22zM175 48a6 6 0 1 0 12 0a6 6 0 1 0-12 0M178 32a3 3 0 1 0 6 0a3 3 0 1 0-6 0',
    'M200.5 34V20l10-3v14M195.5 34a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M205.5 31a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
    'M44 130H184',
    'M50 86h52M54 86v44M98 86v44M48 130h12M92 130h12',
    'M64 90v-2a2 2 0 1 1 2-2M58 94L64 90L70 94M58 94L55 116H73L70 94',
    'M86 90v-2a2 2 0 1 1 2-2M79 94L86 90L93 94M79 94L75 100L78 102L79 99V115H93V99L94 102L97 100L93 94M84 94l2 3l2-3',
    `M128 130V92M176 130V92M124 92L132 80H172L180 92M124 92H180M124 92${scallops(8, 7)}M140 80l-2 12M152 80v12M164 80l2 12`,
    'M128 112h48M128 118h48M134 112a4 4 0 0 1 8 0M144 112a4 4 0 0 1 8 0M154 112a4 4 0 0 1 8 0M164 112a4 4 0 0 1 8 0',
  ],
  // For You: a cosy café corner, arched window with a star, pendant lamp, a table for two, a cup and a plant.
  foryou: [
    'M6 128H222',
    'M32 100V52a24 24 0 0 1 48 0V100ZM56 28V100M32 70H80M28 100h56',
    'M44 38q1 7 8 8q-7 1-8 8q-1-7-8-8q7-1 8-8z',
    'M140 0V30M128 42L134 30h12l6 12zM137 46a3 3 0 0 0 6 0',
    'M118 96h44M140 96v28M130 128l10-4l10 4',
    'M132 96v-8h10v8M142 89c4 0 4 5 0 5M135 84c-2-3 2-5 0-8M139 84c-2-3 2-5 0-8',
    'M152 96v-6h5v6M154.5 90v-6M152.5 82a2 2 0 1 0 4 0a2 2 0 1 0-4 0',
    'M164 104h18M182 104V76q0-4 4-4M166 104l-2 24M180 104l2 24',
    'M98 104h18M98 104V76q0-4-4-4M100 104l-2 24M114 104l2 24',
    'M192 110h16l-2 18h-12zM200 110c0-12-8-18-12-20c2 8 4 14 12 20M200 110c0-14 6-22 12-24c0 10-4 18-12 24M200 110V94',
  ],
};

/** The sketch for a hero tab ('foryou' | 'tonight' | 'weekend' | 'all') or the Browse by type card ('browse'). */
export function heroArtKind(id) {
  return HERO_LINE_ART[id] ? id : 'all';
}

/** One art as a standalone SVG document (iOS imagesets). `stroke` is the colour; iOS renders it as a template. */
export function heroArtSvg(kind, stroke = '#000') {
  const { width, height, stroke: sw } = HERO_ART_BOX;
  const d = HERO_LINE_ART[kind].join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`
    + `<path d="${d}" fill="none" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round"/></svg>\n`;
}

/** iOS asset name of an art: HeroArtTonight, HeroArtForyou, … */
export const heroArtAsset = kind => `HeroArt${kind[0].toUpperCase()}${kind.slice(1)}`;
