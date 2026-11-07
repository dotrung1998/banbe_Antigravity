import { useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, display, fieldGlass } from '../theme.js';
import { foldText } from '../lib/accountSearch.js';

// Shared reader for the Help & Legal text documents (the Guides and the Q&A).
// Content is plain data (src/data/help/*.js): a list of sections, each with a
// bilingual heading and bilingual blocks —
//   ['p', vi, en]            paragraph
//   ['h', vi, en]            sub-heading
//   ['ul' | 'ol', [[vi, en], ...]]  list
//   ['tip', vi, en]          highlighted note
//   ['q', qVi, qEn, aVi, aEn] question + answer (Q&A)
// The reader adds a clickable table of contents, jump-to-top/bottom buttons
// and a search box that filters to the matching sections and highlights hits.

// Case/diacritic-insensitive match positions of `query` inside `text`,
// mapped back onto the ORIGINAL string so Vietnamese text can be highlighted.
function findRanges(text, tokens) {
  if (!tokens.length) return [];
  let folded = '';
  const map = [];
  for (let i = 0; i < text.length; i++) {
    const f = foldText(text[i]);
    for (let k = 0; k < f.length; k++) { folded += f[k]; map.push(i); }
  }
  const ranges = [];
  for (const t of tokens) {
    let from = 0;
    for (;;) {
      const at = folded.indexOf(t, from);
      if (at < 0) break;
      ranges.push([map[at], map[at + t.length - 1] + 1]);
      from = at + t.length;
    }
  }
  ranges.sort((a, b) => a[0] - b[0]);
  const merged = [];
  for (const r of ranges) {
    const last = merged[merged.length - 1];
    if (last && r[0] <= last[1]) last[1] = Math.max(last[1], r[1]); else merged.push([...r]);
  }
  return merged;
}

function Hl({ text, tokens }) {
  const ranges = findRanges(text, tokens);
  if (!ranges.length) return text;
  const out = [];
  let pos = 0;
  ranges.forEach(([a, b], i) => {
    if (a > pos) out.push(text.slice(pos, a));
    out.push(<mark key={i} style={{ background: 'rgba(214,170,60,0.4)', color: 'inherit', borderRadius: 3, padding: '0 1px' }}>{text.slice(a, b)}</mark>);
    pos = b;
  });
  if (pos < text.length) out.push(text.slice(pos));
  return out;
}

const blockText = (b, EN) => {
  const pick = (vi, en) => (EN ? en : vi);
  switch (b[0]) {
    case 'ul': case 'ol': return b[1].map(([vi, en]) => pick(vi, en)).join(' ');
    case 'q': return `${pick(b[1], b[2])} ${pick(b[3], b[4])}`;
    default: return pick(b[1], b[2]);
  }
};

export default function HelpReader({ title, intro, sections, onBack, backLabel, testId }) {
  const { T, state } = useBanBe();
  const EN = state.lang === 'en';
  const [query, setQuery] = useState('');
  const [tocOpen, setTocOpen] = useState(true);
  const topRef = useRef(null);
  const bottomRef = useRef(null);

  const tokens = useMemo(() => foldText(query).split(/[^a-z0-9]+/).filter(Boolean), [query]);

  // A section matches when every typed word appears somewhere in its heading
  // or body (in the current language); only matching sections are shown.
  const visible = useMemo(() => {
    if (!tokens.length) return sections;
    return sections.filter((sec) => {
      const hay = foldText([EN ? sec.en : sec.vi, ...sec.blocks.map(b => blockText(b, EN))].join(' '));
      return tokens.every(t => hay.includes(t));
    });
  }, [sections, tokens, EN]);

  const jump = (ref) => ref.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  const goSection = (id) => document.getElementById(`${testId}-sec-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });

  const hl = (text) => <Hl text={text} tokens={tokens} />;
  const renderBlock = (b, i) => {
    const pick = (vi, en) => (EN ? en : vi);
    switch (b[0]) {
      case 'h': return <h3 key={i} style={{ fontSize: 13.5, fontWeight: 600, color: ink, margin: '16px 0 4px' }}>{hl(pick(b[1], b[2]))}</h3>;
      case 'ul': return <ul key={i} style={{ margin: '6px 0', padding: '0 0 0 20px', fontSize: 13.5, lineHeight: 1.6, color: ink }}>{b[1].map((it, j) => <li key={j} style={{ margin: '3px 0' }}>{hl(pick(it[0], it[1]))}</li>)}</ul>;
      case 'ol': return <ol key={i} style={{ margin: '6px 0', padding: '0 0 0 22px', fontSize: 13.5, lineHeight: 1.6, color: ink }}>{b[1].map((it, j) => <li key={j} style={{ margin: '3px 0' }}>{hl(pick(it[0], it[1]))}</li>)}</ol>;
      case 'tip': return <div key={i} style={{ ...fieldGlass({ margin: '10px 0', padding: '10px 12px', fontSize: 13, lineHeight: 1.55, color: ink }) }}>💡 {hl(pick(b[1], b[2]))}</div>;
      case 'q': return (
        <div key={i} style={{ margin: '12px 0', paddingBottom: 10, borderBottom: `1px solid ${rule}` }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: ink, lineHeight: 1.45 }}>{hl(pick(b[1], b[2]))}</div>
          <p style={{ fontSize: 13.5, lineHeight: 1.6, color: ink, margin: '4px 0 0', opacity: 0.88 }}>{hl(pick(b[3], b[4]))}</p>
        </div>
      );
      default: return <p key={i} style={{ fontSize: 13.5, lineHeight: 1.65, color: ink, margin: '6px 0' }}>{hl(pick(b[1], b[2]))}</p>;
    }
  };

  const floatBtn = { width: 40, height: 40, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: ink, color: paper, fontSize: 16, cursor: 'pointer', boxShadow: '0 2px 10px rgba(0,0,0,0.25)' };

  return (
    <div style={{ animation: 'banbeFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label={testId} data-testid={testId}>
      <div ref={topRef} />
      <div onClick={onBack} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid={`${testId}-back`}>‹ {backLabel}</div>
      <div style={{ padding: '16px 20px 120px' }}>
        <h1 style={{ ...display(26, { margin: 0, lineHeight: 1.2 }) }}>{title}</h1>
        {intro && <p style={{ fontSize: 13, lineHeight: 1.6, color: ink, opacity: 0.75, margin: '8px 0 0' }}>{intro}</p>}

        <input
          type="search" value={query} onChange={(e) => setQuery(e.target.value)}
          placeholder={T('Tìm trong tài liệu…', 'Search this page…')}
          aria-label={T('Tìm kiếm', 'Search')} data-testid={`${testId}-search`}
          style={{ ...fieldGlass({ marginTop: 16, padding: '12px 14px', border: 'none', width: '100%', boxSizing: 'border-box' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
        />
        {!!tokens.length && (
          <div style={{ fontSize: 12, color: ink, opacity: 0.65, marginTop: 8 }} data-testid={`${testId}-result-count`}>
            {visible.length
              ? T(`${visible.length} mục khớp`, `${visible.length} matching section${visible.length === 1 ? '' : 's'}`)
              : T('Không có kết quả. Thử từ khóa khác.', 'No results. Try different words.')}
          </div>
        )}

        {visible.length > 0 && (
          <nav aria-label={T('Mục lục', 'Table of contents')} style={{ ...fieldGlass({ marginTop: 16, padding: '12px 14px' }) }} data-testid={`${testId}-toc`}>
            <div onClick={() => setTocOpen(o => !o)} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer' }} data-testid={`${testId}-toc-toggle`}>
              <span>{T('Mục lục', 'Contents')}</span><span>{tocOpen ? '▾' : '▸'}</span>
            </div>
            {tocOpen && (
              <ol style={{ margin: '8px 0 0', padding: '0 0 0 20px', fontSize: 13.5, lineHeight: 1.9 }}>
                {visible.map((sec) => (
                  <li key={sec.id}>
                    <span onClick={() => goSection(sec.id)} role="link" tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter') goSection(sec.id); }} data-testid={`${testId}-toc-${sec.id}`} style={{ color: ink, textDecoration: 'underline', textUnderlineOffset: 3, cursor: 'pointer' }}>
                      {EN ? sec.en : sec.vi}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </nav>
        )}

        {visible.map((sec, n) => (
          <section key={sec.id} id={`${testId}-sec-${sec.id}`} style={{ marginTop: 26, scrollMarginTop: 12 }}>
            <h2 style={{ fontSize: 17, fontWeight: 600, color: ink, margin: 0, lineHeight: 1.3 }}>
              {tokens.length ? '' : `${n + 1}. `}{hl(EN ? sec.en : sec.vi)}
            </h2>
            {sec.blocks.map(renderBlock)}
          </section>
        ))}
        <div ref={bottomRef} style={{ height: 1 }} />
      </div>

      <div style={{ position: 'fixed', right: 16, bottom: 96, display: 'flex', flexDirection: 'column', gap: 8, zIndex: 5 }}>
        <div onClick={() => jump(topRef)} role="button" aria-label={T('Lên đầu trang', 'Jump to top')} title={T('Lên đầu trang', 'Jump to top')} data-testid={`${testId}-to-top`} style={floatBtn}>↑</div>
        <div onClick={() => jump(bottomRef)} role="button" aria-label={T('Xuống cuối trang', 'Jump to bottom')} title={T('Xuống cuối trang', 'Jump to bottom')} data-testid={`${testId}-to-bottom`} style={floatBtn}>↓</div>
      </div>
    </div>
  );
}
