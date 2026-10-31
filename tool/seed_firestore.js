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
 *                    so edits made in /admin are never clobbered)
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
  let written = 0, skipped = 0;
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
          if ((await ref.get()).exists) { skipped++; continue; }
          console.log(`[dry-run] ${collection}/${id}`);
          written++;
          continue;
        }
        try {
          await ref.create(data);
          written++;
        } catch (e) {
          if (e.code === ALREADY_EXISTS) { skipped++; continue; }
          throw e;
        }
      }
    }
    console.log(`${collection}: ${entries.length} docs processed`);
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
  console.log(`Done. project=${projectId} written=${written} skipped(existing)=${skipped}${dryRun ? ' (dry run)' : ''}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
