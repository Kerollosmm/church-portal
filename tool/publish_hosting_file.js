#!/usr/bin/env node
/**
 * Publishes ONE file into the live Firebase Hosting site without rebuilding
 * the app (ADR-040): clones the current live version (same files, same
 * headers / rewrites), replaces only <hostingPath> in the clone, finalizes it
 * and releases it. Used by .github/workflows/synaxarium.yml for
 * /data/today.json. The Spark plan has no Cloud Functions; this is Hosting's
 * own REST API (firebasehosting.googleapis.com v1beta1).
 *
 *   node tool/publish_hosting_file.js <localFile> <hostingPath> [--site maximos-domadios-church]
 *
 * Auth: GOOGLE_APPLICATION_CREDENTIALS (the deploy service account).
 * Nothing is released unless every step succeeded; a failure leaves the live
 * site untouched (an unfinished cloned version is simply never released).
 */
const fs = require('fs');
const zlib = require('zlib');
const crypto = require('crypto');
const { GoogleAuth } = require('google-auth-library');

const args = process.argv.slice(2);
const [local, hostingPath] = args.filter((a) => !a.startsWith('--'));
const si = args.indexOf('--site');
const site = (si >= 0 && args[si + 1]) || 'maximos-domadios-church';
if (!local || !hostingPath || !hostingPath.startsWith('/')) {
  console.error('usage: node tool/publish_hosting_file.js <localFile> </hosting/path> [--site <id>]');
  process.exit(2);
}

const API = 'https://firebasehosting.googleapis.com/v1beta1';
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

(async () => {
  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/firebase.hosting', 'https://www.googleapis.com/auth/cloud-platform'] });
  const client = await auth.getClient();
  const call = async (method, url, data, extra = {}) => {
    const res = await client.request({ method, url, data, timeout: 60000, ...extra });
    return res.data;
  };

  // 1. The live release's version.
  const rel = await call('GET', `${API}/sites/${site}/channels/live/releases?pageSize=1`);
  const live = rel.releases && rel.releases[0] && rel.releases[0].version;
  if (!live || live.status !== 'FINALIZED') throw new Error('no finalized live version');
  console.log(`live version: ${live.name}`);

  // 2. Clone it without the file we replace.
  let op = await call('POST', `${API}/sites/${site}/versions:clone`, {
    sourceVersion: live.name,
    finalize: false,
    exclude: { regexes: [`^${escapeRe(hostingPath)}$`] },
  });
  for (let i = 0; i < 60 && !op.done; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    op = await call('GET', `${API}/${op.name}`);
  }
  if (!op.done || op.error) throw new Error(`clone failed: ${JSON.stringify(op.error || 'timeout')}`);
  const version = op.response.name;
  console.log(`cloned: ${version}`);

  // 3. Add the file (gzip, sha256 of the gzipped bytes).
  const gz = zlib.gzipSync(fs.readFileSync(local), { level: 9 });
  const hash = crypto.createHash('sha256').update(gz).digest('hex');
  const pop = await call('POST', `${API}/${version}:populateFiles`, { files: { [hostingPath]: hash } });
  if ((pop.uploadRequiredHashes || []).includes(hash)) {
    await call('POST', `${pop.uploadUrl}/${hash}`, gz, { headers: { 'Content-Type': 'application/octet-stream' } });
  }

  // 4. Finalize and release.
  await call('PATCH', `${API}/${version}?update_mask=status`, { status: 'FINALIZED' });
  const r = await call('POST', `${API}/sites/${site}/releases?versionName=${encodeURIComponent(version)}`, {
    message: `data: ${hostingPath}`,
  });
  console.log(`released ${r.name}`);
})().catch((e) => {
  console.error(e.response ? JSON.stringify(e.response.data) : e);
  process.exit(1);
});
