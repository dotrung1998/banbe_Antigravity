// Inline line-art sketch for Home's hero end cards (src/lib/heroLineArt.js holds the drawings, shared with iOS's
// HeroArt* template imagesets). Decorative: hidden from assistive tech. Colour comes from `currentColor`, so the
// caller sets it (the hero cards draw it white at ~62% over their glass).
import { HERO_LINE_ART, HERO_ART_BOX, heroArtKind } from '../../lib/heroLineArt.js';

export default function HeroLineArt({ kind, style, testId }) {
  const k = heroArtKind(kind);
  const { width, height, stroke } = HERO_ART_BOX;
  return (
    <svg aria-hidden="true" focusable="false" data-testid={testId} data-art={k} width={width} height={height} viewBox={`0 0 ${width} ${height}`}
      fill="none" stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" style={{ display: 'block', ...style }}>
      <path d={HERO_LINE_ART[k].join('')} />
    </svg>
  );
}
