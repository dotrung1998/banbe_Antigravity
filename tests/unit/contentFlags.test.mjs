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

// ---- Event Project Hub (note 76): five content keys named after the five switches, all dark until set.
const PROJECT_KEYS = ['event_project_hub', 'project_qr_invite', 'project_delegate_checkin', 'project_delegate_payments', 'project_delegate_refunds'];
const STEP_KEYS = PROJECT_KEYS.slice(1);
const HUB = { event_project_hub: true };
const ALL_PROJECT = Object.fromEntries(PROJECT_KEYS.map(k => [k, true]));
// Words only the project text uses (the admin guide's "Quản lý sự kiện" = Manage events, so not bare "Quản lý").
const PROJECT_EN = /event projects?|event team|Projects I'm in|Finance & door|Lane lead|Day-of|Start a team project|Invite by QR|Refunds to send|Payments to check/i;
const PROJECT_VI = /dự án|Tài chính & cổng|Trưởng hạng mục|Ngày G|đội sự kiện|Lập dự án cho đội|Mời bằng mã QR/i;
const COHOST = /co[-_ ]?host|đồng tổ chức/i;

test('project content keys: in CONTENT_KEYS, dark until set, steps also need the hub', async () => {
  const { CONTENT_KEYS } = await import('../../src/lib/contentFlags.js');
  for (const k of PROJECT_KEYS) {
    assert.ok(CONTENT_KEYS.includes(k), k);
    assert.equal(contentOn({}, k), false, `${k}: missing = off`);
    assert.equal(contentOn({ [k]: false }, k), false);
  }
  assert.equal(contentOn(HUB, 'event_project_hub'), true);
  for (const k of STEP_KEYS) {
    assert.equal(contentOn({ [k]: true }, k), false, `${k} without the hub stays hidden`);
    assert.equal(contentOn(HUB, k), false, `${k} needs its own switch`);
    assert.equal(contentOn({ ...HUB, [k]: true }, k), true);
  }
});

test('Event projects OFF (production today): no guide, TOC entry, search hit or Q&A mentions them', () => {
  for (const flags of [{}, { ...ALL_PROJECT, event_project_hub: false }]) {
    for (const [name, secs] of Object.entries(DOCS)) {
      const f = filterHelpSections(secs, flags);
      assert.ok(!f.some(s => s.id === 'projects'), `${name}: projects section gone`);
      for (const lang of ['vi', 'en']) {
        const m = textOf(f, lang).match(lang === 'en' ? PROJECT_EN : PROJECT_VI);
        assert.equal(m, null, `${name}/${lang} still mentions "${m?.[0]}"`);
      }
    }
  }
});

test('hub ON: host guide, personal guide and Q&A sections appear, delegated and QR text only with their switch', () => {
  const host = filterHelpSections(GUIDES.host.sections, HUB);
  assert.ok(host.some(s => s.id === 'projects'));
  const en = textOf(host, 'en'), vi = textOf(host, 'vi');
  for (const fact of [/Start a team project/, /Manager/, /Finance & door/, /Lane lead/, /Helper/, /Working roles are private/,
    /valid for 48 hours/, /doesn't see those messages/, /Day-of/, /ends 7 days after the event/,
    /30 days after the event the project becomes read-only/, /90 days after the event the project is deleted/, /for 7 days/,
    /kept with the booking/, /Payout and cancelling always stay with you/]) assert.match(en, fact);
  for (const fact of [/Lập dự án cho đội/, /Quản lý/, /Tài chính & cổng/, /48 giờ/, /banbe không thấy các tin nhắn đó/, /chỉ xem/, /90 ngày/])
    assert.match(vi, fact);
  // Off-switch steps are absent with only the hub on.
  assert.doesNotMatch(en, /Invite by QR|up to 20 people|door list|Payments to check|View transfer proof|Refunds to send|Finance can refund alone|Let the team handle this refund/);
  assert.doesNotMatch(vi, /Mời bằng mã QR|Hoàn tiền cần gửi|Thanh toán cần kiểm tra/);
  const personal = filterHelpSections(GUIDES.personal.sections, HUB);
  assert.ok(personal.some(s => s.id === 'projects'));
  assert.match(textOf(personal, 'en'), /Projects I'm in/);
  assert.match(textOf(personal, 'en'), /Join an event team with a code/);
  assert.doesNotMatch(textOf(personal, 'en'), /Scan a QR code/);
  const faq = filterHelpSections(FAQ_SECTIONS, HUB);
  const qs = faq.find(s => s.id === 'projects').blocks.filter(b => b[0] === 'q');
  assert.ok(qs.length >= 4 && qs.length <= 6, `${qs.length} questions with only the hub on`);
  assert.doesNotMatch(textOf(faq, 'en'), /Can my team confirm payments|Can the team send refunds/);
});

test('each delegated step shows its own text and nothing else', () => {
  const t = (flags) => textOf(filterHelpSections(GUIDES.host.sections, flags), 'en');
  assert.match(t({ ...HUB, project_qr_invite: true }), /Invite by QR.*up to 20 people/);
  const checkin = t({ ...HUB, project_delegate_checkin: true });
  assert.match(checkin, /guest names only, no amounts, ticket codes or dates of birth/);
  assert.doesNotMatch(checkin, /View transfer proof|Refunds to send/);
  const pay = t({ ...HUB, project_delegate_payments: true });
  assert.match(pay, /View transfer proof" opens the proof of that booking only/);
  assert.match(pay, /never see invoices or receipts/);
  assert.doesNotMatch(pay, /door list|Refunds to send/);
  const refunds = t({ ...HUB, project_delegate_refunds: true });
  for (const fact of [/Refunds to send/, /By default you approve/, /the guest is told only after you approve/, /Finance can refund alone/,
    /Let the team handle this refund/, /7, 14 or 30 days/, /ends when the dispute closes/, /refunds are back with you/]) assert.match(refunds, fact);
  assert.doesNotMatch(refunds, /door list|View transfer proof/);
  const faqAll = textOf(filterHelpSections(FAQ_SECTIONS, ALL_PROJECT), 'en');
  assert.match(faqAll, /Can my team confirm payments\?/);
  assert.match(faqAll, /Can the team send refunds without me\?/);
  assert.match(textOf(filterHelpSections(GUIDES.personal.sections, ALL_PROJECT), 'en'), /Scan a QR code/);
});

test('"Manager" vs the organizer-profile team member: exactly one contrasting block, nowhere else in help data', () => {
  const hits = [];
  for (const [name, secs] of Object.entries(DOCS)) for (const s of secs) for (const b of s.blocks) {
    if (COHOST.test(JSON.stringify(b)) || COHOST.test(s.en) || COHOST.test(s.vi)) hits.push(`${name}/${s.id}`);
  }
  assert.deepEqual(hits, ['host/projects']);
  const host = textOf(filterHelpSections(GUIDES.host.sections, HUB), 'en');
  assert.match(host, /"Manager" is a role inside one project only\. It is not the same as a co-host on your organizer profile/);
  assert.match(textOf(filterHelpSections(GUIDES.host.sections, HUB), 'vi'), /"Quản lý" là vai trò chỉ trong một dự án, không giống đồng tổ chức/);
});

test('project help text uses no dash or semicolon idea separators (note 57)', () => {
  const secs = [GUIDES.host, GUIDES.personal].map(g => g.sections.find(s => s.id === 'projects')).concat(FAQ_SECTIONS.find(s => s.id === 'projects'));
  for (const lang of ['vi', 'en']) {
    const t = textOf(filterHelpSections(secs, ALL_PROJECT), lang);
    assert.doesNotMatch(t, /\s[–—-]\s|;/, `${lang} has a dash/semicolon separator`);
  }
});

test('policy: project passages are switched, marked as a legal draft, and the version is unchanged', () => {
  const src = readFileSync(new URL('../../src/screens/Policy.jsx', import.meta.url), 'utf8');
  // Every policy passage that names event projects or team members' access sits in a project-keyed guard or row.
  let unguarded = src
    .replace(/\{on\('event_project_hub'\) && \([\s\S]*?\n\s*\)\}/g, '')
    .replace(/\{ flag: '(event_project_hub|project_[a-z_]+)', cells: \[[^\]]*\] \}/g, '')
    .replace(/\/\/[^\n]*/g, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '');
  const hit = unguarded.match(/Event projects?|Dự án sự kiện|team members the host|thành viên đội/);
  assert.equal(hit, null, `unguarded project text near: ${hit ? unguarded.slice(Math.max(0, hit.index - 80), hit.index + 40) : ''}`);
  const rows = (k) => filterPolicyRows([{ flag: k, cells: ['x'] }], {}).length;
  for (const k of PROJECT_KEYS) assert.equal(rows(k), 0, `${k} row hidden while the switches are unset`);
  // QR invites add no data (the QR holds only the invite code), so they have no policy row.
  for (const k of PROJECT_KEYS.filter(k => k !== 'project_qr_invite')) assert.ok(src.includes(`flag: '${k}'`), `policy has a ${k} row`);
  assert.ok((src.match(/DRAFT FOR LEGAL REVIEW/g) || []).length >= 3, 'B3/B4/B7 additions are marked as a legal draft');
  assert.match(src, /guest\\?'s refund account \(bank, account number, account holder\) so they can send the refund/);
  assert.match(src, /including the transfer proof of the booking they are confirming/);
  const md = readFileSync(new URL('../../banbe_User_Policy.md', import.meta.url), 'utf8');
  for (const t of ['Read-only 30 days after the event day. Permanently deleted 90 days after the event day.',
    'so they can send the refund', 'The host and the team members the host added to that project.']) assert.ok(md.includes(t), `md mirror: ${t}`);
  const policyJs = readFileSync(new URL('../../src/lib/policy.js', import.meta.url), 'utf8');
  assert.match(policyJs, /POLICY_VERSION = '2026-10-06'/, 'not bumped before legal review');
});
