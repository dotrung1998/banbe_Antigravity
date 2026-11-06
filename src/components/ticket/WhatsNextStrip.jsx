import { useId, useState } from 'react';
import { ink, ink2, paper, block } from '../../theme.js';

// Slim "What's next" strip at the top of the paper ticket (note 78). One line (heading + optional tail); tapping it
// expands the explanation and the one existing action that fits. The tone paints the disc, the tint and the dot ONLY:
// every text here is ink (tone-coloured text fails 4.5:1 on its own tint in light, tests/unit/designTokens.test.mjs).
// `solid` (checked in) fills with the tone and reads paper on it.

const ICONS = {
  cancelled: <path d="M7 7l10 10M17 7 7 17" />,
  expired: <path d="M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9s8 4 8 9" />,
  review: <><circle cx="12" cy="12" r="8.5" /><path d="M12 11v5M12 8h.01" /></>,
  holding: <path d="M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9s8 4 8 9" />,
  awaiting: <><rect x="3" y="6" width="18" height="12" rx="2.5" /><path d="M3 10h18" /></>,
  ended: <path d="M6 21V4M6 5h11l-2 4 2 4H6" />,
  checkedIn: <path d="M5 12.5l4.5 4.5L19 7.5" />,
  today: <><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></>,
  upcoming: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
};

export const stripTint = (tone) => `color-mix(in srgb, ${tone} 13%, ${block})`;

export default function WhatsNextStrip({ caseKey, tone, solid = false, heading, sub, tail, tailTestId, detail, link, onLink, reduceMotion = false }) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const expandable = !!(detail || link);
  const fg = solid ? paper : ink;
  const fg2 = solid ? paper : ink2;
  const row = (
    <>
      <span aria-hidden style={{ flex: 'none', width: 26, height: 26, borderRadius: '50%', background: solid ? paper : tone, color: solid ? tone : paper, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">{ICONS[caseKey]}</svg>
      </span>
      <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1, textAlign: 'left' }}>
        <span data-testid="confirmed-strip-heading" style={{ fontSize: 13, fontWeight: 600, lineHeight: 1.3, color: fg, overflowWrap: 'anywhere' }}>{heading}</span>
        {sub && <span style={{ fontSize: 12, lineHeight: 1.35, color: fg2, overflowWrap: 'anywhere' }}>{sub}</span>}
      </span>
      {tail && <span data-testid={tailTestId} style={{ flex: 'none', fontSize: 13, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: fg }}>{tail}</span>}
      {expandable && (
        <svg aria-hidden width="8" height="14" viewBox="0 0 8 14" fill="none" stroke={fg} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
          style={{ flex: 'none', transform: open ? 'rotate(90deg)' : 'none', transition: reduceMotion ? 'none' : 'transform .2s' }}><path d="M1.5 1.5 6.5 7l-5 5.5" /></svg>
      )}
    </>
  );
  const rowStyle = { width: '100%', boxSizing: 'border-box', border: 'none', borderRadius: 14, padding: '9px 12px', minHeight: 44, display: 'flex', alignItems: 'center', gap: 10, fontFamily: 'inherit', color: fg,
    background: solid ? tone : stripTint(tone), transition: reduceMotion ? 'none' : 'background .2s' };
  return (
    <div data-testid="confirmed-strip" data-case={caseKey} style={{ borderRadius: 14, background: solid ? tone : stripTint(tone) }}>
      {expandable ? (
        <button type="button" className="bb-press" onClick={() => setOpen(v => !v)} aria-expanded={open} aria-controls={panelId} data-testid="confirmed-strip-toggle"
          style={{ ...rowStyle, cursor: 'pointer' }}>{row}</button>
      ) : (
        <div style={rowStyle}>{row}</div>
      )}
      {expandable && (
        <div id={panelId} data-testid="confirmed-strip-panel" aria-hidden={!open}
          style={{ display: 'grid', gridTemplateRows: open ? '1fr' : '0fr', visibility: open ? 'visible' : 'hidden', transition: reduceMotion ? 'none' : 'grid-template-rows .25s, visibility .25s' }}>
          <div style={{ minHeight: 0, overflow: 'hidden' }}>
            <div style={{ padding: '2px 12px 12px 48px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              {detail && <p data-testid="confirmed-strip-detail" style={{ margin: 0, fontSize: 12.5, lineHeight: 1.5, color: fg2 }}>{detail}</p>}
              {link && (link.href ? (
                <a href={link.href} target="_blank" rel="noopener noreferrer" data-testid="confirmed-strip-link" style={{ alignSelf: 'flex-start', minHeight: 44, display: 'inline-flex', alignItems: 'center', fontSize: 12.5, fontWeight: 600, color: fg, textDecoration: 'underline', textUnderlineOffset: 3 }}>{link.label} ›</a>
              ) : (
                <button type="button" onClick={onLink} data-testid="confirmed-strip-link" style={{ alignSelf: 'flex-start', minHeight: 44, display: 'inline-flex', alignItems: 'center', padding: 0, border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, color: fg, textDecoration: 'underline', textUnderlineOffset: 3, cursor: 'pointer' }}>{link.label} ›</button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
