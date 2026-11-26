// One email rule for Login, Sign up, Reserve and surveys. The old check
// (/x@y.z/) let "ban@gmail.c" and "ban@gmail.co" through, so the person only
// found out when the code never arrived.
// - Format: a real-looking domain whose last part is 2+ letters (or punycode).
// - Typos of the big mailbox providers ("gmail.co", "gmial.com", "yahoo.con")
//   are refused with a one-tap suggestion: those domains never receive mail.
// Twin: apps/ios/BanbeApp/Lib/EmailRules.swift (same lists, same results).

const FORMAT = /^[^\s@.]+(?:\.[^\s@.]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,}|xn--[a-z0-9-]+)$/i;

// Providers whose only real domain is name.com.
const PROVIDERS = ['gmail', 'yahoo', 'hotmail', 'outlook', 'icloud'];
// Misspellings of the provider name itself.
const NAME_TYPOS = {
  gmial: 'gmail', gmal: 'gmail', gmai: 'gmail', gamil: 'gmail', gnail: 'gmail', gmaill: 'gmail', gmali: 'gmail', gmil: 'gmail', gmsil: 'gmail',
  yaho: 'yahoo', yahooo: 'yahoo', yhoo: 'yahoo',
  hotmal: 'hotmail', hotmial: 'hotmail', hotmai: 'hotmail', homail: 'hotmail',
  outlok: 'outlook', outloo: 'outlook', oulook: 'outlook',
  iclod: 'icloud', icoud: 'icloud', iclould: 'icloud',
};
// Last parts that are a mistyped ".com" for these providers.
const COM_TYPOS = new Set(['c', 'co', 'cm', 'om', 'con', 'cmo', 'comm', 'vom', 'xom', 'cpm', 'coom']);

/** The corrected address when the domain is a known typo, else null. */
export function emailTypoSuggestion(value) {
  const email = String(value ?? '').trim();
  const at = email.lastIndexOf('@');
  if (at < 1) return null;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1).toLowerCase();
  const parts = domain.split('.');
  if (parts.length !== 2 || !parts[1]) return null;
  const [name, tld] = parts;
  const fixedName = NAME_TYPOS[name] || name;
  if (!PROVIDERS.includes(fixedName)) return null;
  const fixedTld = tld === 'com' ? 'com' : COM_TYPOS.has(tld) ? 'com' : null;
  // gmail has no country domains at all, so any other ending is a typo.
  const tldOut = fixedTld || (fixedName === 'gmail' ? 'com' : null);
  if (!tldOut) return null;
  const fixed = `${fixedName}.${tldOut}`;
  return fixed === domain ? null : `${local}@${fixed}`;
}

export function emailFormatValid(value) {
  return FORMAT.test(String(value ?? '').trim());
}

/** Accepts an address only when its format is right and its domain is not a known typo. */
export function emailIsValid(value) {
  return emailFormatValid(value) && !emailTypoSuggestion(value);
}
