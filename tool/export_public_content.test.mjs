import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { COLLECTIONS, plain } = require('./export_public_content.js');

test('COLLECTIONS includes entries alongside categories and pages for non-empty sitemap filtering', () => {
  assert.ok(COLLECTIONS.includes('categories'));
  assert.ok(COLLECTIONS.includes('entries'));
  assert.ok(COLLECTIONS.includes('pages'));
  assert.deepEqual(COLLECTIONS, [
    'meetings',
    'activities',
    'facilities',
    'priests',
    'saints',
    'milestones',
    'categories',
    'entries',
    'pages',
  ]);
});

test('plain normalizes Firestore-like objects recursively without requiring firebase-admin', () => {
  const ts = { toDate: () => new Date('2026-11-04T10:00:00.000Z') };
  const input = {
    createdAt: ts,
    nested: [{ updatedAt: ts }],
    title: 'Test',
  };
  assert.deepEqual(plain(input), {
    createdAt: '2026-11-04T10:00:00.000Z',
    nested: [{ updatedAt: '2026-11-04T10:00:00.000Z' }],
    title: 'Test',
  });
});
