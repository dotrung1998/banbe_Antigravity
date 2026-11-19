// v2.3 Event Detail look (note 81, switch home_v23), from docs/prototypes/homescreen-event-detail-motion-v2-3.html:
// a serif display face, Liquid-Glass material for the nav and the floating reserve bar, the motion tokens, and the
// entrance (stub rises, sections reveal on scroll, bar slides up). Everything is scoped under `.bbv23` so nothing
// else in the app changes. Colours are the app's own tokens; the glass line/shadow have a dark-theme twin.
// Reduce Transparency (--bb-rt-*) turns the glass opaque; Reduce Motion (OS) and return visits (.bbv23-noent) skip
// every entrance.

// The prototype's serif (system faces only, no download): Iowan on Apple devices, Palatino / Georgia elsewhere.
// Note 83: follows the chosen font (--bb-font-accent, src/lib/fontPref.js); the serif when nothing is set.
export const SERIF = "var(--bb-font-accent, 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, 'Times New Roman', serif)";

export const glassBar = {
  background: 'var(--bb-rt-bar, rgba(var(--bb-bg-rgb), 0.84))',
  backdropFilter: 'var(--bb-rt-blur, blur(30px) saturate(1.7))',
  WebkitBackdropFilter: 'var(--bb-rt-blur, blur(30px) saturate(1.7))',
};

export const V23_CSS = `
.bbv23 { --v23-line: rgba(255,255,255,.62); --v23-shadow: 0 18px 44px rgba(24,20,16,.16), 0 2px 6px rgba(24,20,16,.06);
  --v23-rim: inset 0 1px 0 rgba(255,255,255,.7); --v23-stub-shadow: 0 34px 80px rgba(24,20,16,.22), 0 3px 12px rgba(24,20,16,.08);
  --v23-spring: cubic-bezier(.2,1.04,.3,1); --v23-out: cubic-bezier(.22,.61,.36,1); --v23-soft: cubic-bezier(.32,.72,0,1);
  color: var(--bb-fg); }
[data-bb-theme="dark"] .bbv23 { --v23-line: rgba(255,255,255,.09); --v23-shadow: 0 18px 44px rgba(0,0,0,.55), 0 2px 6px rgba(0,0,0,.35);
  --v23-rim: inset 0 1px 0 rgba(255,255,255,.06); --v23-stub-shadow: 0 34px 80px rgba(0,0,0,.5), 0 3px 12px rgba(0,0,0,.3); }
.bbv23 button { font-family: inherit; }
.bbv23-scroll { scrollbar-width: none; }
.bbv23-scroll::-webkit-scrollbar { display: none; }
@keyframes bbV23In { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
@keyframes bbV23StubRise { from { opacity: 0; transform: translateY(22px) scale(.985); } to { opacity: 1; transform: none; } }
@keyframes bbV23BarUp { from { transform: translateY(130%); } to { transform: none; } }
@keyframes bbV23Pop { 0% { transform: scale(.92); } 55% { transform: scale(1.06); } 100% { transform: scale(1); } }
@keyframes bbV23Shake { 0%, 100% { transform: none; } 30% { transform: translateX(-3px); } 60% { transform: translateX(3px); } }
@keyframes bbV23StepIn { from { opacity: 0; transform: scale(.86); } to { opacity: 1; transform: none; } }
@keyframes bbV23Toast { from { opacity: 0; transform: translate(-50%, 10px); } to { opacity: 1; transform: translate(-50%, 0); } }
.bbv23-in { animation: bbV23In .28s var(--v23-out) backwards; }
.bbv23-stub { animation: bbV23StubRise .52s var(--v23-spring) .38s backwards; }
.bbv23-bar { animation: bbV23BarUp .46s var(--v23-spring) .16s backwards; }
.bbv23-sec { opacity: 0; transform: translateY(14px); transition: opacity .42s var(--v23-out), transform .42s var(--v23-out); }
.bbv23-sec.in { opacity: 1; transform: none; }
.bbv23-ttl { transform: translateY(calc(var(--dp, 0) * -24px)); opacity: calc(1 - var(--dp, 0) * .8); will-change: transform, opacity; }
.bbv23-nav { transform: translateY(-100%); opacity: 0; pointer-events: none; transition: transform .28s var(--v23-soft), opacity .18s var(--v23-out); }
.bbv23-nav.on { transform: none; opacity: 1; pointer-events: auto; }
.bbv23-tabs { transform: translateY(8px); opacity: 0; transition: transform .28s var(--v23-out), opacity .18s var(--v23-out); }
.bbv23-nav.on .bbv23-tabs { transform: none; opacity: 1; }
.bbv23-back { transition: transform .11s var(--v23-out), opacity .18s var(--v23-out); }
.bbv23-back.hide { opacity: 0; pointer-events: none; }
.bbv23-press { transition: transform .11s var(--v23-out), opacity .18s, background-color .18s, color .18s; }
.bbv23-press:active { transform: scale(.94); }
.bbv23-reserve:active { transform: scale(.975); }
.bbv23-pop { animation: bbV23Pop .32s var(--v23-spring); }
.bbv23-more svg { transition: transform .28s var(--v23-spring); }
.bbv23-more[aria-expanded="true"] svg { transform: rotate(180deg); }
.bbv23-ink { transition: left .28s var(--v23-spring), width .28s var(--v23-spring), opacity .16s .12s; }
.bbv23-slot { transition: flex-basis .34s var(--v23-spring), flex-grow .34s var(--v23-spring), background-color .22s var(--v23-out); }
.bbv23-fold { transition: flex-basis .34s var(--v23-spring), flex-grow .34s var(--v23-spring), opacity .16s, color .18s; }
.bbv23-step { animation: bbV23StepIn .38s var(--v23-spring) both; }
.bbv23-photo { transition: transform .28s var(--v23-out); }
.bbv23-photo:active { transform: scale(.97); }
.bbv23-heroimg { transition: opacity .18s ease-out; }
.bbv23-noent .bbv23-in, .bbv23-noent .bbv23-stub, .bbv23-noent .bbv23-bar { animation: none; }
.bbv23-noent .bbv23-sec { opacity: 1; transform: none; transition: none; }
@media (prefers-reduced-motion: reduce) {
  .bbv23 *, .bbv23 *::before, .bbv23 *::after { animation-duration: 1ms !important; animation-iteration-count: 1 !important; transition-duration: 1ms !important; }
  .bbv23-stub, .bbv23-bar, .bbv23-in { animation: none !important; }
  .bbv23-sec { opacity: 1; transform: none; }
  .bbv23-ttl { transform: none; opacity: 1; }
}
`;
