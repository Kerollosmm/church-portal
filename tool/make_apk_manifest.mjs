#!/usr/bin/env node
/**
 * Generates version.json manifest for Android APK releases (ADR-058 / PR B §12).
 *
 * Reads APK files, computes SHA-256 and size, rewrites GitHub release URLs
 * to immutable tag paths, and outputs the manifest to stdout.
 *
 * Usage:
 *   node tool/make_apk_manifest.mjs --base-url <url> --tag <tag> [--notes-file <file>] <apk1> [<apk2>...]
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

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
    } else if (!a.startsWith('--')) {
      apkFiles.push(a);
    }
  }

  if (!baseUrl || apkFiles.length === 0) {
    console.error('Usage: node tool/make_apk_manifest.mjs --base-url <url> [--tag <tag>] <apk1> [<apk2>...]');
    process.exit(2);
  }

  // Try extracting version and build from pubspec.yaml if not passed
  if (!version || !buildNumber) {
    try {
      const pubspec = fs.readFileSync('pubspec.yaml', 'utf8');
      const m = pubspec.match(/^version:\s*([0-9.]+)\+([0-9]+)/m);
      if (m) {
        if (!version) version = m[1];
        if (!buildNumber) buildNumber = parseInt(m[2], 10);
      }
    } catch (_) {}
  }

  let notesAr = '';
  if (notesFile && fs.existsSync(notesFile)) {
    notesAr = fs.readFileSync(notesFile, 'utf8').trim();
  }

  const manifest = buildManifest({
    version: version || '1.0.0',
    build: buildNumber || 1,
    minSupportedBuild: 1,
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
