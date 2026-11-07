import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mirrorCreateDraft, releaseCreateDraft, holdLeftCreateDraft, beginCreateDraftRestore,
  peekCreateDraftRestore, clearCreateDraftRestore, discardLeftCreateDraft,
} from '../../src/lib/createDraftUndo.js';

// Undo after leaving a new-event draft: the module holds CreateEvent's photos/cover/step so Undo can hand
// them back, and frees photo object URLs only once nothing (live screen, held draft, restore) uses them.
// The module keeps state across calls, so these run in order.

const revoked = [];
URL.revokeObjectURL = (u) => { revoked.push(u); };
const draft = (urls, hasUnsavedInput = true) => ({
  items: urls.map(url => ({ kind: 'new', url })), coverKey: urls[0] ?? null, step: 2, hasUnsavedInput,
});

test('a draft with no input is not held', () => {
  mirrorCreateDraft(draft([], false));
  assert.equal(holdLeftCreateDraft(), false);
});

test('leave -> hold -> Undo restores photos, cover and step, without revoking them', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const d = draft(['blob:a', 'blob:b']);
  mirrorCreateDraft(d);
  releaseCreateDraft(d.items);           // the screen unmounts first...
  assert.equal(holdLeftCreateDraft(), true);  // ...then BanBeContext sees the screen left 'create'
  t.mock.timers.tick(2000);
  assert.deepEqual(revoked, [], 'held photos stay usable');
  beginCreateDraftRestore();
  const r = peekCreateDraftRestore();
  assert.equal(peekCreateDraftRestore(), r, 'peek is safe to call twice (StrictMode initialisers)');
  assert.deepEqual(r.items.map(i => i.url), ['blob:a', 'blob:b']);
  assert.equal(r.coverKey, 'blob:a');
  assert.equal(r.step, 2);
  clearCreateDraftRestore();
  assert.equal(peekCreateDraftRestore(), null);
});

test('the toast running out frees the held photos', () => {
  revoked.length = 0;
  const d = draft(['blob:c']);
  mirrorCreateDraft(d);
  assert.equal(holdLeftCreateDraft(), true);
  discardLeftCreateDraft();
  assert.deepEqual(revoked, ['blob:c']);
});

test('photos of a screen that is still mounted (StrictMode remount) are never revoked', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  revoked.length = 0;
  const d = draft(['blob:d']);
  mirrorCreateDraft(d);
  releaseCreateDraft(d.items);  // simulated unmount
  mirrorCreateDraft(d);         // remount mirrors the same draft again
  t.mock.timers.tick(2000);
  assert.deepEqual(revoked, []);
});
