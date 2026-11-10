#!/usr/bin/env node
/**
 * Publishes ONE or MULTIPLE files into the live Firebase Hosting site without
 * rebuilding the app (ADR-040, ADR-058): clones the current live version (same files,
 * same headers / rewrites), excludes old files matching specified regexes,
 * populates the new files in the clone, finalizes it and releases it ONCE.
 *
 * Single-file usage (existing):
 *   node tool/publish_hosting_file.js <localFile> <hostingPath> [--site maximos-domadios-church]
 *
 * Multi-file usage (new):
 *   node tool/publish_hosting_file.js --dir <localDir> --prefix /data/readings/ [--file <localFile> <hostingPath>...] [--site maximos-domadios-church]
 *
 * Auth: GOOGLE_APPLICATION_CREDENTIALS (the deploy service account).
 * Nothing is released unless every step succeeded; a failure leaves the live
 * site untouched (an unfinished cloned version is simply never released).
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');

const API = 'https://firebasehosting.googleapis.com/v1beta1';
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Builds the map of { hostingPath: localFilePath }
 */
function buildFileMap({ localFile, hostingPath, dir, prefix, extraFiles = [] }) {
  const map = {};
  if (localFile && hostingPath) {
    map[hostingPath] = localFile;
  }
  if (dir) {
    if (!fs.existsSync(dir)) {
      throw new Error(`Directory not found: ${dir}`);
    }
    const files = fs.readdirSync(dir);
    const pfx = prefix ? (prefix.endsWith('/') ? prefix : `${prefix}/`) : '/';
    for (const file of files) {
      const full = path.join(dir, file);
      if (fs.statSync(full).isFile()) {
        map[`${pfx}${file}`] = full;
      }
    }
  }
  for (const { local, remote } of extraFiles) {
    map[remote] = local;
  }
  return map;
}

/**
 * Builds exclude regexes for the version clone operation
 */
function buildExcludeRegexes({ hostingPath, dir, customExcludes = [] }) {
  if (customExcludes && customExcludes.length > 0) {
    return customExcludes;
  }
  if (dir) {
    // Default multi-file mode: purge old readings window and today.json atomically
    return ['^/data/readings/.*[.]json$', '^/data/today[.]json$'];
  }
  if (hostingPath) {
    return [`^${escapeRe(hostingPath)}$`];
  }
  return [];
}

async function run(args = process.argv.slice(2)) {
  const si = args.indexOf('--site');
  const site = (si >= 0 && args[si + 1]) || 'maximos-domadios-church';

  const dirIdx = args.indexOf('--dir');
  const dir = dirIdx >= 0 ? args[dirIdx + 1] : null;

  const pfxIdx = args.indexOf('--prefix');
  const prefix = pfxIdx >= 0 ? args[pfxIdx + 1] : null;

  const extraFiles = [];
  let fIdx = args.indexOf('--file');
  while (fIdx >= 0) {
    const loc = args[fIdx + 1];
    const rem = args[fIdx + 2];
    if (loc && rem) extraFiles.push({ local: loc, remote: rem });
    fIdx = args.indexOf('--file', fIdx + 1);
  }

  const customExcludes = [];
  let eIdx = args.indexOf('--exclude');
  while (eIdx >= 0) {
    const re = args[eIdx + 1];
    if (re) customExcludes.push(re);
    eIdx = args.indexOf('--exclude', eIdx + 1);
  }

  // Positional arguments for single-file mode
  const positionals = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a.startsWith('--')) {
      if (['--site', '--dir', '--prefix', '--exclude'].includes(a)) {
        i++;
      } else if (a === '--file') {
        i += 2;
      }
    } else {
      positionals.push(a);
    }
  }

  const localFile = !dir && positionals.length >= 1 ? positionals[0] : null;
  const hostingPath = !dir && positionals.length >= 2 ? positionals[1] : null;

  if (!dir && (!localFile || !hostingPath || !hostingPath.startsWith('/'))) {
    console.error('usage: node tool/publish_hosting_file.js <localFile> </hosting/path> [--site <id>]');
    console.error('   or: node tool/publish_hosting_file.js --dir <localDir> --prefix </prefix/> [--file <loc> <rem>] [--site <id>]');
    process.exit(2);
  }

  const fileMap = buildFileMap({ localFile, hostingPath, dir, prefix, extraFiles });
  const excludeRegexes = buildExcludeRegexes({ hostingPath, dir, customExcludes });

  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/firebase.hosting', 'https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const call = async (method, url, data, extra = {}) => {
    const res = await client.request({ method, url, data, timeout: 60000, ...extra });
    return res.data;
  };

  // 1. Get the live release's version
  const rel = await call('GET', `${API}/sites/${site}/channels/live/releases?pageSize=1`);
  const live = rel.releases && rel.releases[0] && rel.releases[0].version;
  if (!live || live.status !== 'FINALIZED') throw new Error('no finalized live version');
  console.log(`live version: ${live.name}`);

  // 2. Clone it with the exclude regexes
  console.log(`cloning version with excludes: ${JSON.stringify(excludeRegexes)}`);
  let op = await call('POST', `${API}/sites/${site}/versions:clone`, {
    sourceVersion: live.name,
    finalize: false,
    exclude: { regexes: excludeRegexes },
  });
  for (let i = 0; i < 60 && !op.done; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    op = await call('GET', `${API}/${op.name}`);
  }
  if (!op.done || op.error) throw new Error(`clone failed: ${JSON.stringify(op.error || 'timeout')}`);
  const version = op.response.name;
  console.log(`cloned: ${version}`);

  // 3. Compress files and compute SHA256 hashes
  const filesPayload = {};
  const gzBuffers = {};
  for (const [remotePath, localPath] of Object.entries(fileMap)) {
    const raw = fs.readFileSync(localPath);
    const gz = zlib.gzipSync(raw, { level: 9 });
    const hash = crypto.createHash('sha256').update(gz).digest('hex');
    filesPayload[remotePath] = hash;
    gzBuffers[hash] = gz;
  }

  // 4. Populate files
  console.log(`populating ${Object.keys(filesPayload).length} files into ${version}...`);
  const pop = await call('POST', `${API}/${version}:populateFiles`, { files: filesPayload });
  const required = pop.uploadRequiredHashes || [];
  console.log(`upload required for ${required.length} hashes`);
  for (const hash of required) {
    const gz = gzBuffers[hash];
    await call('POST', `${pop.uploadUrl}/${hash}`, gz, {
      headers: { 'Content-Type': 'application/octet-stream' },
    });
  }

  // 5. Finalize and release
  await call('PATCH', `${API}/${version}?update_mask=status`, { status: 'FINALIZED' });
  const r = await call('POST', `${API}/sites/${site}/releases?versionName=${encodeURIComponent(version)}`, {
    message: `data update: ${Object.keys(filesPayload).length} files`,
  });
  console.log(`released ${r.name}`);
}

module.exports = {
  buildFileMap,
  buildExcludeRegexes,
};

if (require.main === module) {
  run().catch((e) => {
    console.error(e.response ? JSON.stringify(e.response.data) : e);
    process.exit(1);
  });
}
