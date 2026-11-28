#!/usr/bin/env node
/**
 * Adds the always-present keys (#143, ADR-094) to existing content documents
 * so the public filtered queries
 *   where('visible', '==', true).where('deletedAt', '==', null)   (content + pages)
 *   where('active',  '==', true).where('deletedAt', '==', null)   (seasons)
 * can see them. Firestore equality filters never match a document that lacks
 * the field, so a legacy document without `visible` / `deletedAt` would vanish.
 *
 * Only ABSENT keys are written; an existing value (visible: false, a soft
 * delete's deletedAt timestamp, active: false) is never changed. updatedAt /
 * updatedBy are not touched. Safe to re-run (idempotent).
 *
 * Auth (either):
 *   - Service account:  GOOGLE_APPLICATION_CREDENTIALS=/path/key.json node tool/backfill_visibility.js
 *   - ADC:              gcloud auth application-default login && node tool/backfill_visibility.js
 *
 * Options:
 *   --dry-run        (default) print per-collection counts, write nothing
 *   --apply          write the missing keys (WriteBatch, 400 per batch)
 *   --project <id>   Firebase project id (default: asafra-church-portal or $GCLOUD_PROJECT)
 *
 * Production runs need the owner's explicit OK.
 */

/** The 10 collections the public reads with the visible filter. */
const VISIBLE_COLLECTIONS = [
  'alerts', 'liturgies', 'meetings', 'activities', 'facilities',
  'priests', 'milestones', 'saints', 'categories', 'entries',
];
/** Every collection the backfill visits: content + seasons + pages. */
const COLLECTIONS = [...VISIBLE_COLLECTIONS, 'seasons', 'pages'];
const BATCH_SIZE = 400;

/**
 * The fields [data] (a document of [col]) lacks, or null when it has them all.
 * Never returns a key the document already has, whatever its value.
 */
function missingPatch(col, data) {
  const d = data || {};
  const patch = {};
  if (!Object.prototype.hasOwnProperty.call(d, 'deletedAt')) patch.deletedAt = null;
  if (col === 'seasons') {
    if (!Object.prototype.hasOwnProperty.call(d, 'active')) patch.active = true;
  } else if (!Object.prototype.hasOwnProperty.call(d, 'visible')) {
    patch.visible = true;
  }
  return Object.keys(patch).length ? patch : null;
}

/**
 * Plans the writes for [docsByCol] (collection -> [{id, data}]).
 * Returns { counts: {col: {total, missing}}, writes: [{col, id, patch}] }.
 */
function planBackfill(docsByCol) {
  const counts = {};
  const writes = [];
  for (const col of COLLECTIONS) {
    const docs = docsByCol[col] || [];
    let missing = 0;
    for (const { id, data } of docs) {
      const patch = missingPatch(col, data);
      if (patch) {
        missing++;
        writes.push({ col, id, patch });
      }
    }
    counts[col] = { total: docs.length, missing };
  }
  return { counts, writes };
}

/** Splits [writes] into chunks of at most [size]. */
function chunk(writes, size = BATCH_SIZE) {
  const out = [];
  for (let i = 0; i < writes.length; i += size) out.push(writes.slice(i, i + size));
  return out;
}

async function main() {
  const args = process.argv.slice(2);
  const opt = (n) => {
    const i = args.indexOf(n);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const apply = args.includes('--apply');
  if (apply && args.includes('--dry-run')) {
    console.error('--apply and --dry-run cannot be combined.');
    process.exit(2);
  }
  const projectId = opt('--project') || process.env.GCLOUD_PROJECT || 'asafra-church-portal';
  // Required lazily so the unit tests run without firebase-admin installed.
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId });
  const db = admin.firestore();

  const docsByCol = {};
  for (const col of COLLECTIONS) {
    const snap = await db.collection(col).get();
    docsByCol[col] = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  }
  const { counts, writes } = planBackfill(docsByCol);
  console.log(`project ${projectId} — ${apply ? 'APPLY' : 'dry run'}`);
  for (const col of COLLECTIONS) {
    console.log(`  ${col.padEnd(12)} ${String(counts[col].total).padStart(4)} docs, ${counts[col].missing} need backfill`);
  }
  if (!writes.length) {
    console.log('0 docs need backfill');
    return;
  }
  console.log(`${writes.length} docs need backfill`);
  if (!apply) {
    console.log('Dry run: nothing written. Re-run with --apply to write the missing keys.');
    return;
  }
  for (const part of chunk(writes)) {
    const batch = db.batch();
    for (const { col, id, patch } of part) batch.update(db.collection(col).doc(id), patch);
    await batch.commit();
  }
  console.log(`Backfilled ${writes.length} docs. Run again with --dry-run: it must report 0 docs need backfill.`);
}

module.exports = { VISIBLE_COLLECTIONS, COLLECTIONS, BATCH_SIZE, missingPatch, planBackfill, chunk };

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
