import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { COLLECTIONS, VISIBLE_COLLECTIONS, missingPatch, planBackfill, chunk } = require('./backfill_visibility.js');

test('covers the 10 visible collections, seasons and pages', () => {
  assert.equal(VISIBLE_COLLECTIONS.length, 10);
  assert.equal(COLLECTIONS.length, 12);
  assert.ok(COLLECTIONS.includes('seasons'));
  assert.ok(COLLECTIONS.includes('pages'));
  assert.ok(!COLLECTIONS.includes('clinics'));
});

test('adds only the absent keys', () => {
  assert.deepEqual(missingPatch('liturgies', { nameAr: 'x' }), { deletedAt: null, visible: true });
  assert.deepEqual(missingPatch('pages', { visible: true }), { deletedAt: null });
  assert.deepEqual(missingPatch('seasons', { key: 'fast' }), { deletedAt: null, active: true });
  assert.equal(missingPatch('seasons', { active: true, deletedAt: null }), null);
  // seasons use `active`, never `visible`
  assert.equal('visible' in missingPatch('seasons', {}), false);
});

test('never overwrites visible:false, active:false or an existing deletedAt', () => {
  const ts = { seconds: 1 };
  assert.equal(missingPatch('priests', { visible: false, deletedAt: null }), null);
  assert.equal(missingPatch('meetings', { visible: true, deletedAt: ts }), null);
  assert.deepEqual(missingPatch('meetings', { visible: false }), { deletedAt: null });
  assert.deepEqual(missingPatch('alerts', { deletedAt: ts }), { visible: true });
  assert.equal(missingPatch('seasons', { active: false, deletedAt: ts }), null);
});

test('plan counts per collection and is idempotent once applied', () => {
  const docs = {
    liturgies: [{ id: 'a', data: {} }, { id: 'b', data: { visible: false, deletedAt: null } }],
    seasons: [{ id: 's', data: { active: false } }],
  };
  const first = planBackfill(docs);
  assert.deepEqual(first.counts.liturgies, { total: 2, missing: 1 });
  assert.deepEqual(first.counts.seasons, { total: 1, missing: 1 });
  assert.deepEqual(first.counts.pages, { total: 0, missing: 0 });
  assert.equal(first.writes.length, 2);
  // apply the patches, then plan again: nothing left
  for (const { col, id, patch } of first.writes) {
    const doc = docs[col].find((d) => d.id === id);
    Object.assign(doc.data, patch);
  }
  assert.equal(docs.seasons[0].data.active, false, 'existing active:false kept');
  assert.equal(docs.liturgies[1].data.visible, false, 'existing visible:false kept');
  assert.equal(planBackfill(docs).writes.length, 0);
});

test('chunks writes under the 500-op batch limit', () => {
  const writes = Array.from({ length: 901 }, (_, i) => ({ col: 'liturgies', id: `${i}`, patch: {} }));
  assert.deepEqual(chunk(writes).map((c) => c.length), [400, 400, 101]);
});
