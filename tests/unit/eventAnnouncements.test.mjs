import test from 'node:test';
import assert from 'node:assert/strict';
import { ANNOUNCEMENT_TEMPLATES, ANNOUNCEMENT_CATEGORIES, ANNOUNCEMENT_MAX, filterAnnouncementTemplates } from '../../src/lib/eventAnnouncements.js';

test('every template has a known category, unique id, both languages, and fits the limit', () => {
  const cats = new Set(ANNOUNCEMENT_CATEGORIES.map(c => c.id));
  const ids = new Set();
  for (const t of ANNOUNCEMENT_TEMPLATES) {
    assert.ok(cats.has(t.category), t.id);
    assert.ok(!ids.has(t.id), `dup ${t.id}`); ids.add(t.id);
    assert.ok(t.vi && t.en);
    assert.ok(t.vi.length <= ANNOUNCEMENT_MAX && t.en.length <= ANNOUNCEMENT_MAX, t.id);
  }
});
test('search is accent-insensitive and bilingual', () => {
  assert.ok(filterAnnouncementTemplates('tre', 'timing').some(t => t.id === 'delay-15'));
  assert.ok(filterAnnouncementTemplates('PARKING').some(t => t.id === 'parking'));
  assert.ok(filterAnnouncementTemplates('gui xe').some(t => t.id === 'parking'));
  assert.equal(filterAnnouncementTemplates('parking', 'timing').length, 0);
  assert.equal(filterAnnouncementTemplates('', 'all').length, ANNOUNCEMENT_TEMPLATES.length);
});
