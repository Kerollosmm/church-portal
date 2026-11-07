#!/usr/bin/env node
/**
 * Generates version.json manifest for Android APK releases (ADR-058 / PR B §12).
 *
 * Reads APK files, computes SHA-256 and size, rewrites GitHub release URLs
 * to immutable tag paths, and outputs the manifest to stdout.
 *
 * Usage:
 *   node tool/make_apk_manifest.mjs --base-url <url> --tag <tag> [--notes-file <file>]
 *     [--version <x.y.z>] [--build <n>] [--min-supported-build <n>] [--pubspec <path>] <apk1> [<apk2>...]
 *
 * Version / build default to the repo's pubspec.yaml, resolved next to this script (the release
 * workflow runs it from the APK output directory). The build must equal the `installApkBuild` the
 * admin saves, so a missing build is an error rather than a silent `1`.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

/** Reads `version: x.y.z+n` from a pubspec; null when absent / unreadable. */
export function readPubspecVersion(pubspecPath) {
  try {
    const m = fs.readFileSync(pubspecPath, 'utf8').match(/^version:\s*([0-9.]+)\+([0-9]+)/m);
    return m ? { version: m[1], build: parseInt(m[2], 10) } : null;
  } catch (_) {
    return null;
  }
}

export const defaultPubspecPath = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'pubspec.yaml');

/**
 * Resolves the download URL for an APK asset given a base URL, tag, and file name.
 */
export function resolveDownloadUrl(baseUrl, tag, fileName) {
  if (!baseUrl) {
    throw new Error('Base URL is required');
  }

  const isGitHub = /github\.com\/[^/]+\/[^/]+\/releases/i.test(baseUrl);

  if (isGitHub) {
    if (!tag) {
      throw new Error('--tag is required when using a GitHub releases base URL');
    }
    // Rewrite /releases/latest/download/ to /releases/download/<tag>/
    let rewritten = baseUrl;
    if (rewritten.includes('/releases/latest/download/')) {
      rewritten = rewritten.replace('/releases/latest/download/', `/releases/download/${tag}/`);
    } else if (rewritten.includes('/releases/latest/download')) {
      rewritten = rewritten.replace('/releases/latest/download', `/releases/download/${tag}`);
    }
    if (!rewritten.endsWith('/')) rewritten += '/';
    return `${rewritten}${fileName}`;
  }

  // Firebase or other direct hosting: keep base URL untouched
  let pfx = baseUrl;
  if (!pfx.endsWith('/')) pfx += '/';
  return `${pfx}${fileName}`;
}

export function detectApkAbi(fileName) {
  const f = fileName.toLowerCase();
  if (f.includes('arm64') || f.includes('v8a')) return 'arm64-v8a';
  if (f.includes('arm32') || f.includes('v7a') || f.includes('armeabi')) return 'armeabi-v7a';
  if (f.includes('x86_64')) return 'x86_64';
  if (f.includes('x86')) return 'x86';
  return 'arm64-v8a'; // default
}

export function buildManifest({
  version = '1.0.0',
  build = 1,
  minSupportedBuild = 1,
  publishedAt,
  notesAr = '',
  notesEn = '',
  certSha256 = '',
  baseUrl,
  tag,
  apkFiles = [],
}) {
  const apks = {};
  for (const apkPath of apkFiles) {
    const fileName = path.basename(apkPath);
    const abi = detectApkAbi(fileName);
    const stat = fs.statSync(apkPath);
    const bytes = fs.readFileSync(apkPath);
    const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
    const url = resolveDownloadUrl(baseUrl, tag, fileName);

    apks[abi] = {
      url,
      sha256,
      size: stat.size,
    };
  }

  return {
    schema: 1,
    version,
    build,
    minSupportedBuild,
    publishedAt: publishedAt || new Date().toISOString(),
    notesAr,
    notesEn,
    certSha256,
    apks,
  };
}

async function main() {
  const args = process.argv.slice(2);
  let baseUrl = '';
  let tag = '';
  let notesFile = '';
  let version = '';
  let buildNumber = 0;
  let minSupportedBuild = 1;
  let pubspecPath = defaultPubspecPath;
  const apkFiles = [];

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--base-url') {
      baseUrl = args[++i];
    } else if (a === '--tag') {
      tag = args[++i];
    } else if (a === '--notes-file') {
      notesFile = args[++i];
    } else if (a === '--version') {
      version = args[++i];
    } else if (a === '--build') {
      buildNumber = parseInt(args[++i], 10);
    } else if (a === '--min-supported-build') {
      minSupportedBuild = parseInt(args[++i], 10);
    } else if (a === '--pubspec') {
      pubspecPath = args[++i];
    } else if (!a.startsWith('--')) {
      apkFiles.push(a);
    }
  }

  if (!baseUrl || apkFiles.length === 0) {
    console.error('Usage: node tool/make_apk_manifest.mjs --base-url <url> [--tag <tag>] <apk1> [<apk2>...]');
    process.exit(2);
  }

  // Version and build from the repo's pubspec.yaml when not passed (independent of the cwd).
  if (!version || !buildNumber) {
    const pv = readPubspecVersion(pubspecPath);
    if (pv) {
      if (!version) version = pv.version;
      if (!buildNumber) buildNumber = pv.build;
    }
  }
  if (!Number.isInteger(buildNumber) || buildNumber < 1) {
    throw new Error(`no build number: pass --build or keep "version: x.y.z+n" in ${pubspecPath}`);
  }
  if (!Number.isInteger(minSupportedBuild) || minSupportedBuild < 1 || minSupportedBuild > buildNumber) {
    throw new Error(`--min-supported-build must be between 1 and the build (${buildNumber})`);
  }

  let notesAr = '';
  if (notesFile && fs.existsSync(notesFile)) {
    notesAr = fs.readFileSync(notesFile, 'utf8').trim();
  }

  const manifest = buildManifest({
    version: version || '1.0.0',
    build: buildNumber,
    minSupportedBuild,
    publishedAt: new Date().toISOString(),
    notesAr,
    notesEn: '',
    certSha256: process.env.CERT_SHA256 || '',
    baseUrl,
    tag,
    apkFiles,
  });

  console.log(JSON.stringify(manifest, null, 2));
}

if (process.argv[1] && process.argv[1].endsWith('make_apk_manifest.mjs')) {
  main().catch((e) => {
    console.error(`ERROR: ${e.message}`);
    process.exit(1);
  });
}
