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

  let written = 0, skipped = 0;
  for (const [collection, docs] of Object.entries(seed)) {
    if (only && !only.includes(collection)) continue;
    const entries = Object.entries(docs);
    for (let i = 0; i < entries.length; i += 400) {
      const batch = db.batch();
      let n = 0;
      for (const [id, data] of entries.slice(i, i + 400)) {
        const ref = db.collection(collection).doc(id);
        if (!force && !dryRun) {
          const snap = await ref.get();
          if (snap.exists) { skipped++; continue; }
        }
        if (dryRun) console.log(`[dry-run] ${collection}/${id}`);
        else batch.set(ref, convert(data));
        n++;
      }
      if (!dryRun && n) await batch.commit();
      written += n;
    }
    console.log(`${collection}: ${entries.length} docs processed`);
  }

  if (adminArg) {
    const [uid, email] = adminArg.split(':');
    if (!dryRun) await db.doc(`admins/${uid}`).set({ email: email || '', role: 'owner' }, { merge: true });
    console.log(`admins/${uid} ${dryRun ? '(dry-run)' : 'created'}`);
  }
  console.log(`Done. project=${projectId} written=${written} skipped(existing)=${skipped}${dryRun ? ' (dry run)' : ''}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
