import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { shortlistEnd, heroSuggestions } from '../../src/lib/listEnd.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/list-end.json', import.meta.url), 'utf8'));

test('shortlistEnd: second action and body follow the open tab (shared fixture)', () => {
  for (const c of fx.shortlistEnd) {
    const r = shortlistEnd({ total: c.total, shown: c.shown, filtersOn: c.filtersOn, tab: c.tab });
    assert.equal(r.kind, c.kind);
    if (c.bodyEn) assert.equal(r.body.en, c.bodyEn);
    if (c.bodyVi) assert.equal(r.body.vi, c.bodyVi);
    assert.equal(r.actions.length, c.actions.length);
    c.actions.forEach((a, i) => {
      assert.equal(r.actions[i].act, a.act);
      assert.equal(!!r.actions[i].primary, a.primary);
      if (a.labelEn) assert.equal(r.actions[i].label.en, a.labelEn);
      if (a.labelVi) assert.equal(r.actions[i].label.vi, a.labelVi);
    });
    // No map action, no mention of the map.
    assert.ok(!r.actions.some(a => a.act === 'map'));
    if (r.body) assert.doesNotMatch(`${r.body.en} ${r.body.vi}`, /map|bản đồ/i);
  }
});

test('heroSuggestions: only a short, non-empty pager gets cards; only options with events (shared fixture)', () => {
  for (const c of fx.heroSuggestions) {
    const r = heroSuggestions({ tab: c.tab, shown: c.shown, counts: c.counts });
    assert.equal(r.length, c.expect.length, JSON.stringify(c));
    c.expect.forEach((e, i) => {
      assert.equal(r[i].kind, e.kind);
      if (e.tab) assert.equal(r[i].tab, e.tab);
      if (e.titleEn) assert.equal(r[i].title.en, e.titleEn);
      if (e.titleVi) assert.equal(r[i].title.vi, e.titleVi);
      if (e.detailEn) assert.equal(r[i].detail.en, e.detailEn);
      if (e.detailVi) assert.equal(r[i].detail.vi, e.detailVi);
    });
  }
});
