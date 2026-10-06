// Opening message shown as the first host bubble when a goer taps "Message
// <host>" (migrations 156/157). Display-only: never stored as a message.
//
// Resolution: the host's text in the app language; if empty, the host's other
// language; if both empty, a built-in localized default picked
// deterministically per event key (only variant 0 names the organizer).
const DEFAULTS = [
  { vi: (n) => `Chào bạn, mình là ${n}. Cứ nhắn mình thoải mái nhé!`, en: (n) => `Hi, this is ${n}. Feel free to message me anytime!` },
  { vi: () => 'Xin chào! Bạn có câu hỏi gì về sự kiện này không? Cứ hỏi nhé.', en: () => 'Hello! Got a question about this event? Just ask.' },
  { vi: () => 'Cảm ơn bạn đã quan tâm đến sự kiện. Cần biết thêm gì, nhắn mình nhé!', en: () => 'Thanks for your interest in the event. Message me if you need to know anything!' },
  { vi: () => 'Chào bạn! Mình sẵn sàng giải đáp mọi thắc mắc trước giờ diễn ra.', en: () => 'Hi there! Happy to answer any questions before the event.' },
  { vi: () => 'Hẹn gặp bạn ở sự kiện! Cần hỗ trợ gì cứ nhắn ở đây.', en: () => 'Looking forward to seeing you! Message here if you need anything.' },
];

function hashKey(key) {
  let h = 0;
  for (const ch of String(key || '')) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return h;
}

export function resolveChatGreeting({ vi, en, lang, eventKey, hostName }) {
  const v = (vi || '').trim();
  const e = (en || '').trim();
  const chosen = lang === 'en' ? (e || v) : (v || e);
  if (chosen) return chosen;
  const d = DEFAULTS[hashKey(eventKey) % DEFAULTS.length];
  const name = (hostName || '').trim();
  // Variant 0 needs a name; without one use a neutral variant instead.
  const pick = (d === DEFAULTS[0] && !name) ? DEFAULTS[1] : d;
  return (lang === 'en' ? pick.en : pick.vi)(name);
}
