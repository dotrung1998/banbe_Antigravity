import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CANCELLATION_TEMPLATES, joinNames, fillCancellationTemplate, buildCancellationDraft, buildMailtoUrl,
} from '../../src/lib/eventCancellationTemplates.js';

const ctx = { guestNames: ['An', 'Bình', 'Chi'], eventName: 'Nói Chuyện', eventDate: '30/10', eventPlace: 'Quận 1', organizerName: 'Test' };

test('every template fills every placeholder in both languages, for one guest and for the group', () => {
  for (const t of CANCELLATION_TEMPLATES) {
    for (const lang of ['vi', 'en']) {
      const one = buildCancellationDraft(t, lang, { ...ctx, guestName: 'Bảo Châu' });
      assert.ok(!/\{\{\w+\}\}/.test(one.subject + one.body), `${t.key}/${lang} left a placeholder`);
      assert.ok(one.body.includes('Bảo Châu'), `${t.key}/${lang} does not greet the guest by name`);
      assert.ok(!one.body.includes('Bình'), `${t.key}/${lang} leaked another guest's name`);
      const group = buildCancellationDraft(t, lang, ctx);
      assert.ok(group.body.includes('An, Bình'), `${t.key}/${lang} group draft has no names`);
      assert.ok(one.reason.length > 0);
    }
  }
});

test('a guest with no name still gets a greeting', () => {
  const d = buildCancellationDraft(CANCELLATION_TEMPLATES[0], 'en', { ...ctx, guestName: '  ' });
  assert.ok(d.body.startsWith('Dear there,'));
});

test('joinNames shortens long lists and handles empty', () => {
  assert.equal(joinNames(['An'], 'en'), 'An');
  assert.equal(joinNames(['An', 'Bình'], 'en'), 'An and Bình');
  assert.match(joinNames(Array.from({ length: 9 }, (_, i) => `N${i}`), 'en'), /and 3 others$/);
  assert.equal(joinNames([], 'en'), 'everyone');
});

test('an unknown placeholder stays visible', () => {
  assert.equal(fillCancellationTemplate('Hi {{nope}}', {}), 'Hi {{nope}}');
});

test('an individual mailto addresses exactly one person', () => {
  const url = buildMailtoUrl({ to: ['a@x.com'] }, 'S', 'B');
  assert.ok(url.startsWith('mailto:a%40x.com?subject=S'));
  assert.ok(!url.includes('bcc='));
});

test('the group mailto puts holders in BCC, never in the visible To', () => {
  const url = buildMailtoUrl({ bcc: ['a@x.com', 'b@y.com'] }, 'S', 'B');
  assert.ok(url.startsWith('mailto:?bcc=a%40x.com,b%40y.com'));
});
