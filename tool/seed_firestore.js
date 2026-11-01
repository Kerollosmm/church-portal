#!/usr/bin/env node
/**
 * Uploads assets/seed/seed.json to Cloud Firestore.
 *
 * Auth (either):
 *   - Service account:  GOOGLE_APPLICATION_CREDENTIALS=/path/key.json node tool/seed_firestore.js
 *   - ADC:              gcloud auth application-default login && node tool/seed_firestore.js
 *
 * Options:
 *   --project <id>   Firebase project id (default: asafra-church-portal or $GCLOUD_PROJECT)
 *   --only a,b       Only these collections (e.g. --only liturgies,clinics)
 *   --dry-run        Print what would be written
 *   --force          Overwrite existing documents (default: skip docs that already exist,
 *                    so edits made in /admin are never clobbered) and delete the
 *                    retired sample documents listed in tool/retired_seed_ids.json
 *   --fill-missing   For documents that already exist, add only the top-level fields they
 *                    lack (e.g. a field introduced by a newer seed). Existing values,
 *                    including edits made in /admin, are never changed.
 *   --admin <uid>[:email]  Also create admins/{uid} (role owner)
 *   --admin-email <email>  Find or create the Firebase Auth user with this email and make it owner
 *
 * Fields named startsAt / endsAt / date / createdAt are converted to Timestamps.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

const projectId = opt('--project') || process.env.GCLOUD_PROJECT || 'asafra-church-portal';
const only = opt('--only') ? opt('--only').split(',').map((s) => s.trim()) : null;
const dryRun = flag('--dry-run');
const force = flag('--force');
const fillMissing = flag('--fill-missing');
if (force && fillMissing) {
  // --force overwrites whole documents, which breaks --fill-missing's promise
  // to never change existing values: refuse before any write.
  console.error('--force and --fill-missing cannot be combined.');
  process.exit(2);
}
const adminArg = opt('--admin');
const adminEmail = opt('--admin-email');

const DATE_FIELDS = new Set(['startsAt', 'endsAt', 'date', 'createdAt']);

function convert(obj) {
  if (Array.isArray(obj)) return obj.map(convert);
  if (obj && typeof obj === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(obj)) {
      if (DATE_FIELDS.has(k) && typeof v === 'string' && v) {
        const d = new Date(v);
        if (isNaN(d.getTime())) throw new Error(`Invalid date in field ${k}: ${v}`);
        out[k] = admin.firestore.Timestamp.fromDate(d);
      } else {
        out[k] = convert(v);
      }
    }
    return out;
  }
  return obj;
}

async function main() {
  const seedPath = path.join(__dirname, '..', 'assets', 'seed', 'seed.json');
  const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
  const db = admin.firestore();

  // Validate and convert every document before the first write, so an
  // invalid date can never leave a partially written database.
  // `settings` goes last: settings/church marks the database as seeded (the
  // app then stops falling back to the bundled seed), so an interrupted
  // upload must not create it before the other collections exist.
  const plan = Object.entries(seed)
    .filter(([collection]) => !only || only.includes(collection))
    .sort(([a], [b]) => (a === 'settings') - (b === 'settings'))
    .map(([collection, docs]) => [collection, Object.entries(docs).map(([id, data]) => [id, convert(data)])]);

  const ALREADY_EXISTS = 6; // gRPC status code
  let written = 0, skipped = 0, filled = 0;

  // --fill-missing: add only absent top-level fields to an existing doc.
  // Runs in a transaction so a field an admin writes meanwhile is never replaced.
  async function fill(ref, data, label) {
    const keys = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return null;
      const current = snap.data() || {};
      const missing = Object.fromEntries(Object.entries(data).filter(([k]) => !(k in current)));
      if (Object.keys(missing).length && !dryRun) tx.update(ref, missing);
      return Object.keys(missing);
    });
    if (!keys || !keys.length) return;
    console.log(`${dryRun ? '[dry-run] ' : ''}${label}: ${dryRun ? 'would add' : 'added'} ${keys.join(', ')}`);
    filled++;
  }
  for (const [collection, entries] of plan) {
    if (force) {
      // --force: overwrite in batches.
      for (let i = 0; i < entries.length; i += 400) {
        const chunk = entries.slice(i, i + 400);
        if (dryRun) {
          for (const [id] of chunk) console.log(`[dry-run] ${collection}/${id} (overwrite)`);
        } else {
          const batch = db.batch();
          for (const [id, data] of chunk) batch.set(db.collection(collection).doc(id), data);
          await batch.commit();
        }
        written += chunk.length;
      }
    } else {
      // Default: create only, per document, so a document created (e.g. in
      // /admin) after we looked is never overwritten.
      for (const [id, data] of entries) {
        const ref = db.collection(collection).doc(id);
        if (dryRun) {
          if ((await ref.get()).exists) {
            skipped++;
            if (fillMissing) await fill(ref, data, `${collection}/${id}`);
            continue;
          }
          console.log(`[dry-run] ${collection}/${id}`);
          written++;
          continue;
        }
        try {
          await ref.create(data);
          written++;
        } catch (e) {
          if (e.code !== ALREADY_EXISTS) throw e;
          skipped++;
          if (fillMissing) await fill(ref, data, `${collection}/${id}`);
        }
      }
    }
    console.log(`${collection}: ${entries.length} docs processed`);
  }

  // --force also removes sample documents that earlier seeds created and the
  // current seed replaced (only the ids listed in retired_seed_ids.json, so
  // documents added in /admin are never touched).
  let deleted = 0;
  if (force) {
    const retiredPath = path.join(__dirname, 'retired_seed_ids.json');
    const retired = fs.existsSync(retiredPath) ? JSON.parse(fs.readFileSync(retiredPath, 'utf8')) : {};
    for (const [collection, ids] of Object.entries(retired)) {
      if (only && !only.includes(collection)) continue;
      for (const id of ids) {
        if (seed[collection] && seed[collection][id]) continue; // still part of the seed
        const ref = db.collection(collection).doc(id);
        const snap = await ref.get();
        if (!snap.exists) continue; // already gone (e.g. a repeated --force run)
        // Provenance: /admin stamps every save with updatedAt/updatedBy, so a
        // retired id that an admin has since edited (or re-created) is kept.
        const data = snap.data() || {};
        if ('updatedAt' in data || 'updatedBy' in data) {
          console.log(`kept ${collection}/${id} (edited in /admin)`);
          continue;
        }
        if (dryRun) {
          console.log(`[dry-run] would delete ${collection}/${id}`);
          continue;
        }
        await ref.delete();
        deleted++;
      }
    }
  }

  if (adminArg) {
    const [uid, email] = adminArg.split(':');
    if (!dryRun) await db.doc(`admins/${uid}`).set({ email: email || '', role: 'owner' }, { merge: true });
    console.log(`admins/${uid} ${dryRun ? '(dry-run)' : 'created'}`);
  }
  if (adminEmail) {
    let user;
    try {
      user = await admin.auth().getUserByEmail(adminEmail);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      if (!dryRun) user = await admin.auth().createUser({ email: adminEmail });
    }
    if (user && !dryRun) {
      await db.doc(`admins/${user.uid}`).set({ email: adminEmail, role: 'owner' }, { merge: true });
    }
    console.log(`admin owner ${adminEmail} -> uid ${user ? user.uid : '(dry-run)'}`);
  }
  console.log(`Done. project=${projectId} written=${written} skipped(existing)=${skipped} filled(missing fields)=${filled} deleted(retired)=${deleted}${dryRun ? ' (dry run)' : ''}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
