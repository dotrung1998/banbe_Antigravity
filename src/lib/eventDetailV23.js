// v2.3 Event Detail presentation rules (note 81, switch home_v23). Pure, unit-tested (tests/unit/eventDetailV23.test.mjs).
// Copy: { vi, en } pairs or plain strings already in the viewer's language; no dash/semicolon idea separators (note 57).

const L = (vi, en) => ({ vi, en });
const LABEL = { alcohol: L('Đồ uống', 'Alcohol'), dietary: L('Ăn uống', 'Dietary'), age: L('Độ tuổi', 'Age'), refund: L('Hoàn tiền', 'Refund') };

/**
 * "Good to know" as a label / value list (the prototype's knowList), from needToKnowRows (eventDetailPresentation):
 * alcohol, every dietary choice in ONE row, minimum age, then the type's other facts; a refund row last when the
 * event is paid and open. Host-written notes follow the value after " · ". Rows with no value are dropped.
 * Returns [{ key, label: {vi,en} | string, text }].
 */
export function knowRows(needRows = [], { refund = null } = {}) {
  const out = [];
  const join = (...parts) => parts.map(p => String(p ?? '').trim()).filter(Boolean).join(' · ');
  const dietary = (needRows || []).filter(r => r.id === 'dietary');
  for (const r of needRows || []) {
    if (r.id === 'dietary') {
      if (r !== dietary[0]) continue;
      const notes = dietary.map(d => d.sub).filter(Boolean);
      out.push({ key: 'dietary', label: LABEL.dietary, text: join(dietary.map(d => d.title).join(', '), ...notes) });
    } else if (r.id === 'alcohol') out.push({ key: r.key, label: LABEL.alcohol, text: join(r.title, r.sub) });
    else if (r.icon === 'age') out.push({ key: r.key, label: LABEL.age, text: join(r.title, r.sub) });
    else if (r.sub) out.push({ key: r.key, label: r.title, text: r.sub });
  }
  if (refund) out.push({ key: 'refund', label: LABEL.refund, text: refund });
  return out.filter(r => r.text);
}

/** Two-digit editorial numbers for the included list: 01, 02, 03. */
export const listNo = (i) => String(i + 1).padStart(2, '0');

/** Hero parallax for scroll offset y (px): the 140 % tall art moves 0.2× and grows slowly; --dp sinks the title. */
export function heroMotion(y) {
  const t = Math.max(0, Number(y) || 0);
  return { art: `translate3d(0, ${t * 0.2}px, 0) scale(${1 + t / 4000})`, dp: Math.min(1, t / 300) };
}

export const NAV_AT = 140; // px of scroll past which the glass nav with the title and tabs takes over
export const navOn = (y) => (Number(y) || 0) > NAV_AT;

/** Reading progress 0–1 for the line under the tabs. */
export function readProgress(y, scrollHeight, clientHeight) {
  const max = (scrollHeight || 0) - (clientHeight || 0);
  return max > 0 ? Math.min(1, Math.max(0, (y || 0) / max)) : 0;
}
