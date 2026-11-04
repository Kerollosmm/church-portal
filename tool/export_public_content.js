#!/usr/bin/env node
/**
 * READ-ONLY export of the public content the sitemap needs (ADR-038).
 *
 * Auth: GOOGLE_APPLICATION_CREDENTIALS (the Deploy workflow's service-account
 * action) or ADC. Only `get()` calls are made — this script never writes to
 * Firestore.
 *
 *   node tool/export_public_content.js <out.json> [--project <id>]
 *
 * Output: {"exportedAt": ISO, "features": {...} | null,
 *          "<collection>": [{"id": "...", "data": {...}}, ...], ...}
 * Timestamps become ISO-8601 strings (models.dart `parseDate` reads them).
 * Exits non-zero on any failure, so the workflow keeps the static sitemap.
 */
const fs = require('fs');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const out = args.find((a) => !a.startsWith('--'));
const pi = args.indexOf('--project');
const projectId = (pi >= 0 && args[pi + 1]) || process.env.GCLOUD_PROJECT || 'asafra-church-portal';
if (!out) {
  console.error('usage: node tool/export_public_content.js <out.json> [--project <id>]');
  process.exit(2);
}

// Collections with public pages (lib/domain/item_detail.dart DetailKind +
// ADR-027 categories / pages). `entries` has no page of its own.
const COLLECTIONS = ['meetings', 'activities', 'clinics', 'facilities', 'priests', 'saints', 'milestones', 'categories', 'pages'];

function plain(v) {
  if (v instanceof admin.firestore.Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === 'object') {
    if (typeof v.toDate === 'function') return v.toDate().toISOString();
    if (v.constructor && v.constructor.name === 'GeoPoint') return { latitude: v.latitude, longitude: v.longitude };
    if (v.constructor && v.constructor.name === 'DocumentReference') return v.path;
    const o = {};
    for (const [k, val] of Object.entries(v)) o[k] = plain(val);
    return o;
  }
  return v;
}

function withTimeout(p, ms, what) {
  let t;
  return Promise.race([
    p,
    new Promise((_, rej) => {
      t = setTimeout(() => rej(new Error(`${what}: timed out after ${ms} ms`)), ms);
    }),
  ]).finally(() => clearTimeout(t));
}

(async () => {
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
  const db = admin.firestore();
  const result = { exportedAt: new Date().toISOString() };
  const features = await withTimeout(db.doc('settings/features').get(), 30000, 'settings/features');
  result.features = features.exists ? plain(features.data()) : null;
  for (const name of COLLECTIONS) {
    const snap = await withTimeout(db.collection(name).get(), 30000, name);
    result[name] = snap.docs.map((d) => ({ id: d.id, data: plain(d.data()) }));
  }
  fs.writeFileSync(out, JSON.stringify(result));
  const counts = COLLECTIONS.map((n) => `${n}=${result[n].length}`).join(' ');
  console.log(`Exported (read-only) features=${result.features ? 'stored' : 'missing'} ${counts}`);
  process.exit(0);
})().catch((e) => {
  console.error(`Export failed: ${e && e.message ? e.message : e}`);
  process.exit(1);
});
