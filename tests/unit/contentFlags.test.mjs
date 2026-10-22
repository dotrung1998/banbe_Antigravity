import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { contentOn, filterHelpSections, filterPolicyRows } from '../../src/lib/contentFlags.js';
import { GUIDES, FAQ_SECTIONS } from '../../src/data/help/index.js';

// Feature-switched content (note 59). Mirrored by apps/ios/BanbeAppTests/ContentFlagsTests.swift.
const OFF = { rewards: false };
const ON = { rewards: true };
const ON_V2 = { rewards: true, rewards_v2: true };
const MISSING = {};
const DOCS = { personal: GUIDES.personal.sections, host: GUIDES.host.sections, admin: GUIDES.admin.sections, faq: FAQ_SECTIONS };

// Everything a reader could see or search: section titles (the TOC) and every block, in one language.
const textOf = (sections, lang) => sections.map(s => [lang === 'en' ? s.en : s.vi, ...s.blocks.map(b => {
  const i = lang === 'en' ? 1 : 0;
  if (b[0] === 'ul' || b[0] === 'ol') return b[1].map(it => it[i]).join(' ');
  if (b[0] === 'q') return lang === 'en' ? `${b[2]} ${b[4]}` : `${b[1]} ${b[3]}`;
  return lang === 'en' ? b[2] : b[1];
})].join(' ')).join(' ');
// Rewards vocabulary. ("Verified" host badge and the admin pending-count badge are not Rewards and stay.)
const REWARDS_EN = /\b(rewards?|coins?|streaks?|grace weeks?|monthly goal|keychain designs? .*coins)\b/i;
const REWARDS_VI = /(phần thưởng|(?<!\p{L})xu(?!\p{L}| hướng)|chuỗi (ngày|tuần)|tuần nghỉ|mục tiêu tháng)/iu;

test('content keys follow the platform switches', () => {
  assert.equal(contentOn(OFF, 'rewards'), false);
  assert.equal(contentOn(ON, 'rewards'), true);
  assert.equal(contentOn(MISSING, 'rewards'), true, 'a missing rewards key counts as on (same as the app)');
  assert.equal(contentOn(ON, 'rewards_daily'), true);
  assert.equal(contentOn(ON, 'rewards_v2'), false, 'rewards_v2 is off unless set');
  assert.equal(contentOn(ON_V2, 'rewards_v2'), true);
  assert.equal(contentOn(ON_V2, 'rewards_daily'), false);
  assert.equal(contentOn({ rewards: false, rewards_v2: true }, 'rewards_v2'), false, 'v2 content needs Rewards on');
  assert.equal(contentOn(ON, 'nope'), false, 'unknown keys never show');
  assert.equal(contentOn(OFF, undefined), true, 'untagged content always shows');
});

test('Rewards OFF: no guide, TOC entry or Q&A mentions rewards, in either language', () => {
  for (const [name, secs] of Object.entries(DOCS)) {
    const f = filterHelpSections(secs, OFF);
    assert.ok(!f.some(s => s.id === 'rewards'), `${name}: rewards section gone from the TOC`);
    for (const lang of ['vi', 'en']) {
      const t = textOf(f, lang);
      const m = t.match(lang === 'en' ? REWARDS_EN : REWARDS_VI);
      assert.equal(m, null, `${name}/${lang} still mentions "${m?.[0]}"`);
    }
  }
});

test('Rewards OFF: searching for reward words finds nothing (search runs on the filtered sections)', () => {
  for (const secs of Object.values(DOCS)) {
    const f = filterHelpSections(secs, OFF);
    const en = textOf(f, 'en').toLowerCase(), vi = textOf(f, 'vi').toLowerCase();
    for (const word of ['coin', 'reward', 'streak', 'grace week']) assert.ok(!en.includes(word), word);
    for (const word of ['phần thưởng', 'tuần nghỉ', 'chuỗi ngày']) assert.ok(!vi.includes(word), word);
    assert.doesNotMatch(vi, /(?<!\p{L})xu(?!\p{L}| hướng)/u); // "xu hướng" = trends
  }
});

test('Rewards ON (or key missing): the guide section, the keychain line and the Q&A topic appear', () => {
  for (const flags of [ON, MISSING]) {
    const personal = filterHelpSections(GUIDES.personal.sections, flags);
    assert.ok(personal.some(s => s.id === 'rewards'));
    assert.match(textOf(personal, 'en'), /A few extra locked designs can be unlocked with coins/);
    assert.match(textOf(personal, 'vi'), /mở bằng xu/);
    const faq = filterHelpSections(FAQ_SECTIONS, flags);
    assert.ok(faq.some(s => s.id === 'rewards'));
    assert.match(textOf(faq, 'en'), /Do coins expire\?/);
    assert.match(textOf(faq, 'vi'), /Xu có hết hạn không\?/);
  }
});

test('daily vs weekly streak text follows rewards_v2, so the guide never describes a streak the app does not show', () => {
  const daily = textOf(filterHelpSections(GUIDES.personal.sections, ON), 'en');
  assert.match(daily, /Miss a day and the streak starts again from 0/);
  assert.doesNotMatch(daily, /grace week|Monday to Sunday|monthly goal|Badges have tiers/i);
  const weekly = textOf(filterHelpSections(GUIDES.personal.sections, ON_V2), 'en');
  assert.match(weekly, /Monday to Sunday/);
  assert.match(weekly, /grace week/);
  assert.match(weekly, /Badges have tiers/);
  assert.doesNotMatch(weekly, /Miss a day/);
});

test('the facts the guide must state (both languages)', () => {
  const en = textOf(filterHelpSections(GUIDES.personal.sections, ON_V2), 'en');
  for (const fact of [/no cash value/, /cannot be bought, sold, transferred to anyone or cashed out/, /do not expire today/,
    /between 3 hours before and 24 hours after the start/, /does not use up the monthly limit/, /At most 10 events/,
    /balance can go negative/, /If the event is restored, the coins come back/, /grace week/, /within 14 days/, /pays no coins and no badge/,
    /time zone/i]) assert.match(en, fact);
  const vi = textOf(filterHelpSections(GUIDES.personal.sections, ON_V2), 'vi');
  for (const fact of [/không có giá trị tiền/, /không hết hạn/, /3 giờ trước đến 24 giờ sau/, /tối đa 10 sự kiện/, /số dư có thể âm/, /tuần nghỉ/, /14 ngày/])
    assert.match(vi, fact);
  assert.doesNotMatch(en + vi, /cashback|1 coin =|exchange rate|hurry|last chance|you'll lose/i);
});

test('filtering removes a list item, unwraps a flagged block and drops a section left empty', () => {
  const secs = [
    { id: 'a', vi: 'A', en: 'A', blocks: [['ul', [['x', 'x'], ['y', 'y', 'rewards']]], ['flag', 'rewards', ['p', 'p', 'p']]] },
    { id: 'b', vi: 'B', en: 'B', blocks: [['flag', 'rewards', ['p', 'q', 'q']]] },
    { id: 'c', vi: 'C', en: 'C', flag: 'rewards', blocks: [['p', 'r', 'r']] },
  ];
  assert.deepEqual(filterHelpSections(secs, OFF), [{ id: 'a', vi: 'A', en: 'A', blocks: [['ul', [['x', 'x']]]] }]);
  const on = filterHelpSections(secs, ON);
  assert.deepEqual(on.map(s => s.id), ['a', 'b', 'c']);
  assert.deepEqual(on[0].blocks, [['ul', [['x', 'x'], ['y', 'y']]], ['p', 'p', 'p']]);
});

test('policy rows: flagged rows follow the switch, plain rows always stay', () => {
  const rows = [['a'], { flag: 'rewards', cells: ['b'] }, { flag: 'rewards_v2', cells: ['c'] }];
  assert.deepEqual(filterPolicyRows(rows, OFF), [['a']]);
  assert.deepEqual(filterPolicyRows(rows, ON), [['a'], ['b']]);
  assert.deepEqual(filterPolicyRows(rows, ON_V2), [['a'], ['b'], ['c']]);
  assert.deepEqual(filterPolicyRows(rows, null, () => false), [['a']], 'flags not loaded yet: nothing switched shows');
});

test('the policy screen only shows rewards text inside on(...) guards', () => {
  // Static check of src/screens/Policy.jsx: every passage that names coins/rewards sits inside an on('rewards…') block
  // or a { flag } row. Cheap guard against a future edit adding unguarded rewards text.
  const src = readFileSync(new URL('../../src/screens/Policy.jsx', import.meta.url), 'utf8');
  let unguarded = src;
  // Strip guarded blocks from the innermost out (A9 holds nested on('rewards_daily'/'rewards_v2') blocks).
  const innermost = /\{on\('rewards[a-z_0-9]*'\) && \((?:(?!\{on\()[\s\S])*?\n\s*\)\}/g;
  for (let prev = ''; prev !== unguarded;) { prev = unguarded; unguarded = unguarded.replace(innermost, ''); }
  unguarded = unguarded
    .replace(/\{ flag: 'rewards[a-z_0-9]*', cells: \[[^\]]*\] \}/g, '')
    .replace(/\/\/[^\n]*/g, '')                       // code comments
    .replace(/on\('rewards[a-z_0-9]*'\)/g, '');         // the guard calls themselves
  const hit = unguarded.match(/(?<!\p{L})(coins?|rewards|streaks?|xu)(?!\p{L}| hướng)|phần thưởng/iu);
  assert.equal(hit, null, `unguarded rewards text near: ${hit ? unguarded.slice(Math.max(0, hit.index - 80), hit.index + 40) : ''}`);
});
