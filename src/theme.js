// Shared design tokens + glass style recipes for the "warm paper" visual system.
// Ported from the Goc Manual.dc.html design handoff — see its README for the
// full rationale. One paper, one ink; color only lives in on-photo state chips.

export const paper = 'var(--bb-bg)';
export const ink = 'var(--bb-fg)';
export const inkDeep = 'var(--bb-ink-deep)';
export const rule = 'var(--bb-rule)';
export const fieldSolid = 'var(--bb-field)';

// Be Vietnam Pro — same geometric, rounded-sans vibe as Poppins (the
// prototype's stand-in face) but designed for full, clean Vietnamese
// diacritic coverage, so tone marks sit right at any weight/size.
export const FACE = "'Be Vietnam Pro', system-ui, sans-serif";
export const DISPLAY_FACE = "'Jost', 'Be Vietnam Pro', system-ui, sans-serif";

// Display/title text: 600, tight tracking.
export const display = (size, extra) => ({
  fontFamily: DISPLAY_FACE, fontWeight: 600, letterSpacing: '-0.02em', fontSize: size, color: ink, ...extra,
});

// ---- Glass recipes (exact, from the handoff) ----

// Safari (and some Chromium builds) fail to clip `backdrop-filter` to
// `border-radius` once a `box-shadow` is also present — the blur bleeds
// past the rounded corners into a rectangular halo. Forcing a no-op mask
// makes the browser composite the element correctly, clipped to its own
// rounded shape. Spread onto every glass recipe below.
const clipBackdropFilter = {
  WebkitMaskImage: '-webkit-radial-gradient(white, black)',
  maskImage: 'radial-gradient(white, black)',
};

// Field glass — inputs, list containers, small tiles.
export const fieldGlass = (extra) => ({
  background: 'linear-gradient(168deg, var(--bb-white) 0%, rgba(255,255,255,0.16) 42%, rgba(255,255,255,0) 100%), var(--bb-card)',
  backdropFilter: 'blur(12px) saturate(1.06)', WebkitBackdropFilter: 'blur(12px) saturate(1.06)',
  boxShadow: 'inset 0 1px 0 var(--bb-white), 0 1px 3px var(--bb-shadow)',
  borderRadius: 12, ...clipBackdropFilter, ...extra,
});

// Card glass — section cards, stat cards, panels.
export const cardGlass = (extra) => ({
  background: 'linear-gradient(168deg, var(--bb-white) 0%, rgba(255,255,255,0.24) 45%, rgba(255,255,255,0.04) 100%), var(--bb-card2)',
  backdropFilter: 'blur(14px) saturate(1.05)', WebkitBackdropFilter: 'blur(14px) saturate(1.05)',
  boxShadow: 'inset 0 1px 0 var(--bb-white), 0 1px 4px var(--bb-shadow)',
  borderRadius: 12, ...clipBackdropFilter, ...extra,
});

// Bar glass — sticky bottom bars.
export const barGlass = (extra) => ({
  background: 'linear-gradient(180deg, rgba(247,244,236,0.35) 0%, rgba(247,244,236,0.78) 45%, rgba(247,244,236,0.92) 100%)',
  backdropFilter: 'blur(16px) saturate(1.04)', WebkitBackdropFilter: 'blur(16px) saturate(1.04)',
  ...clipBackdropFilter, ...extra,
});

// Ink glass button — primary CTAs.
export const inkButton = (extra) => ({
  background: 'linear-gradient(165deg, rgba(255,255,255,0.25) 0%, rgba(255,255,255,0.07) 30%, rgba(255,255,255,0) 55%), var(--bb-button)',
  color: 'var(--bb-button-text)', backdropFilter: 'blur(22px) saturate(1.7)', WebkitBackdropFilter: 'blur(22px) saturate(1.7)',
  border: '1px solid rgba(255,255,255,0.3)',
  boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.45), inset 0 -12px 22px rgba(255,255,255,0.08), 0 14px 34px rgba(27,25,22,0.35)',
  borderRadius: 18, textShadow: '0 1px 2px rgba(27,25,22,0.35)', fontSize: 15, fontWeight: 600,
  textAlign: 'center', cursor: 'pointer', ...clipBackdropFilter, ...extra,
});

// Frosted pill over a photo (back/share buttons, remove chip).
export const photoPill = (extra) => ({
  position: 'absolute',
  background: 'linear-gradient(165deg, rgba(255,255,255,0.42) 0%, rgba(255,255,255,0.12) 34%, rgba(255,255,255,0) 62%), rgba(247,244,236,0.85)',
  backdropFilter: 'blur(16px) saturate(1.6)', WebkitBackdropFilter: 'blur(16px) saturate(1.6)',
  border: '1px solid rgba(255,255,255,0.5)', boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.65), 0 6px 16px rgba(27,25,22,0.22)',
  borderRadius: 11, color: ink, cursor: 'pointer', fontSize: 12, ...clipBackdropFilter, ...extra,
});

// On-photo state chip (the only colored surfaces — translucent, blurred, white label).
export const CHIP_COLORS = {
  going: 'rgba(72,88,52,0.74)',       // olive — paid/going
  cancelled: 'rgba(140,74,48,0.72)',  // clay — cancelled/refunded
  hold: 'rgba(140,96,20,0.72)',       // honey — on hold
  invite: 'rgba(52,84,94,0.72)',      // mist — private/invite-only
  saved: 'rgba(104,84,48,0.74)',      // sand — saved
  past: 'rgba(78,72,58,0.7)',         // neutral ink — past/ended
};

export const photoChip = (bg, extra) => ({
  position: 'absolute', fontSize: 10, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase',
  padding: '6px 10px', borderRadius: 12, color: '#FFFFFF', textShadow: '0 1px 2px rgba(27,25,22,0.4)',
  background: 'linear-gradient(165deg, rgba(255,255,255,0.42) 0%, rgba(255,255,255,0.12) 34%, rgba(255,255,255,0) 62%), ' + bg,
  backdropFilter: 'blur(16px) saturate(1.6)', WebkitBackdropFilter: 'blur(16px) saturate(1.6)',
  border: '1px solid rgba(255,255,255,0.5)', boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.65), 0 6px 16px rgba(27,25,22,0.22)',
  cursor: 'pointer', ...clipBackdropFilter, ...extra,
});

// The one light chip: unsaved "Lưu" — light glass, ink label.
export const lightChip = (extra) => photoChip('rgba(247,244,236,0.62)', { color: ink, textShadow: 'none', ...extra });
