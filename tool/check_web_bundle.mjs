#!/usr/bin/env node
/**
 * Verifies release web bundle size ceilings, deferred chunk isolation,
 * sourcemap mapping purity, and bundled OpenType font integrity (ADR-061).
 *
 * Usage:
 *   node tool/check_web_bundle.mjs [build/web]
 */

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const DEFAULT_MAX_GZIP_BYTES = 1399000; // 1,399,000 bytes (~1.33 MB)
export const DEFAULT_MIN_PART_COUNT = 6;
export const DEFAULT_MIN_FONT_BYTES = 20 * 1024; // 20 KB

export const DEFAULT_DEFERRED_MODULES = [
  'ui/admin/admin_page.dart',
  'data/admin_repository.dart',
  'ui/admin/admin_strings.dart',
  'ui/pages/assistant_page.dart',
  'data/app_check_providers.dart',
  'ui/pages/notifications_page.dart',
  'ui/pages/readings_page.dart',
  'ui/pages/notification_health_page.dart',
  'ui/widgets/apk_install_guide.dart',
  'data/web_push_repository.dart',
  'ui/widgets/reminder_sheet.dart',
];

export const DEFAULT_FORBIDDEN_MAIN_SOURCES = [
  'data/latest_10y.dart',
  'ui/widgets/update_banner_io.dart',
  'data/url_image_cache_io.dart',
  'firebase_auth-',
  'firebase_app_check-',
];

export const DEFAULT_REQUIRED_FONTS = [
  'IBMPlexSansArabic-Regular.ttf',
  'IBMPlexSansArabic-Bold.ttf',
  'Lalezar-Regular.ttf',
  'ArefRuqaa-Bold.ttf',
];

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) {
    return `${bytes.toLocaleString()} B (${(bytes / 1024 / 1024).toFixed(2)} MB)`;
  }
  return `${bytes.toLocaleString()} B (${(bytes / 1024).toFixed(2)} KB)`;
}

function findFontDir(buildDir) {
  const candidate1 = path.join(buildDir, 'assets', 'assets', 'fonts');
  if (fs.existsSync(candidate1)) return candidate1;
  const candidate2 = path.join(buildDir, 'assets', 'fonts');
  if (fs.existsSync(candidate2)) return candidate2;
  return candidate1;
}

/**
 * Pure verification function.
 * @param {string} buildDir Path to web build directory (e.g. 'build/web')
 * @param {object} [options]
 * @returns {object} verification result
 */
export function checkWebBundle(buildDir, options = {}) {
  const maxGzipBytes = Number(options.maxGzipBytes ?? process.env.MAIN_JS_GZ_MAX ?? DEFAULT_MAX_GZIP_BYTES);
  const minPartCount = Number(options.minPartCount ?? DEFAULT_MIN_PART_COUNT);
  const minFontBytes = Number(options.minFontBytes ?? DEFAULT_MIN_FONT_BYTES);
  const deferredModules = options.deferredModules ?? DEFAULT_DEFERRED_MODULES;
  const forbiddenMainSources = options.forbiddenMainSources ?? DEFAULT_FORBIDDEN_MAIN_SOURCES;
  const requiredFonts = options.requiredFonts ?? DEFAULT_REQUIRED_FONTS;

  const errors = [];
  const lines = [];

  lines.push('================================================================================');
  lines.push('                    WEB BUNDLE & DEFERRED ISOLATION REPORT');
  lines.push('================================================================================');

  if (!fs.existsSync(buildDir)) {
    const msg = `Build directory does not exist: ${buildDir}`;
    errors.push(msg);
    return {
      success: false,
      errors,
      report: `${msg}\n`,
    };
  }

  // 1. Verify main.dart.js (or main.<12-hex>.dart.js) exists & inspect size
  const entries = fs.readdirSync(buildDir);
  const mainFiles = entries
    .filter((f) => /^main(?:\.[0-9a-f]{12})?\.dart\.js$/.test(f))
    .sort();
  const mainFileName = mainFiles.length === 1 ? mainFiles[0] : 'main.dart.js';
  const mainJsPath = path.join(buildDir, mainFileName);
  let mainBundle = null;
  if (mainFiles.length === 0) {
    errors.push(`main.dart.js (or main.<hash>.dart.js) not found in ${buildDir}`);
  } else if (mainFiles.length > 1) {
    errors.push(`Multiple main bundle files found in ${buildDir}: ${mainFiles.join(', ')}`);
  } else {
    const mainBuf = fs.readFileSync(mainJsPath);
    const rawBytes = mainBuf.length;
    const gzipBytes = zlib.gzipSync(mainBuf, { level: 9 }).length;
    const headroomBytes = maxGzipBytes - gzipBytes;
    const passed = gzipBytes <= maxGzipBytes;

    if (!passed) {
      errors.push(
        `${mainFileName} gzip -9 size ${gzipBytes.toLocaleString()} B exceeds ceiling of ${maxGzipBytes.toLocaleString()} B by ${(gzipBytes - maxGzipBytes).toLocaleString()} B`
      );
    }

    mainBundle = {
      name: mainFileName,
      path: mainJsPath,
      rawBytes,
      gzipBytes,
      maxGzipBytes,
      headroomBytes,
      passed,
    };

    lines.push('Main Bundle:');
    lines.push(`  Path:           ${mainJsPath}`);
    lines.push(`  Raw Size:       ${formatBytes(rawBytes)}`);
    lines.push(`  Gzip (-9) Size: ${formatBytes(gzipBytes)}`);
    lines.push(`  Ceiling Budget: ${formatBytes(maxGzipBytes)}`);
    lines.push(
      `  Headroom:       ${headroomBytes >= 0 ? '+' : ''}${formatBytes(headroomBytes)} [${passed ? 'PASS' : 'FAIL'}]`
    );
    lines.push('');
  }

  // 2. Verify deferred part chunks
  const partFileNames = entries
    .filter((f) => /^main\.dart\.js_\d+\.part\.js$/.test(f))
    .sort((a, b) => {
      const na = parseInt(a.match(/main\.dart\.js_(\d+)\.part\.js/)?.[1] || '0', 10);
      const nb = parseInt(b.match(/main\.dart\.js_(\d+)\.part\.js/)?.[1] || '0', 10);
      return na - nb;
    });

  const partFiles = [];
  for (const pf of partFileNames) {
    const pBuf = fs.readFileSync(path.join(buildDir, pf));
    const pGz = zlib.gzipSync(pBuf, { level: 9 });
    const hasMap = fs.existsSync(path.join(buildDir, `${pf}.map`));
    partFiles.push({
      name: pf,
      rawBytes: pBuf.length,
      gzipBytes: pGz.length,
      hasMap,
    });
  }

  const partCountPassed = partFiles.length >= minPartCount;
  if (!partCountPassed) {
    errors.push(`Found ${partFiles.length} deferred part chunks, expected at least ${minPartCount}`);
  }

  lines.push(`Deferred Part Chunks (${partFiles.length} found, minimum ${minPartCount} required): [${partCountPassed ? 'PASS' : 'FAIL'}]`);
  for (const pf of partFiles) {
    lines.push(
      `  - ${pf.name.padEnd(24)} raw: ${formatBytes(pf.rawBytes).padEnd(20)} gzip: ${formatBytes(pf.gzipBytes).padEnd(20)} map: ${pf.hasMap ? 'YES' : 'NO'}`
    );
  }
  lines.push('');

  // 3. Verify sourcemap deferred isolation
  const mainMapName = `${mainFileName}.map`;
  const mainMapPath = path.join(buildDir, mainMapName);
  const deferredIsolation = {
    passed: true,
    modules: [],
    leaks: [],
    missingInParts: [],
    forbiddenLeaks: [],
  };

  if (!fs.existsSync(mainMapPath)) {
    const msg = `${mainMapName} not found in ${buildDir}`;
    errors.push(msg);
    deferredIsolation.passed = false;
  } else {
    let mainMap;
    try {
      mainMap = JSON.parse(fs.readFileSync(mainMapPath, 'utf8'));
    } catch (e) {
      const msg = `Failed to parse ${mainMapName}: ${e.message}`;
      errors.push(msg);
      deferredIsolation.passed = false;
    }

    if (mainMap) {
      const mainSources = Array.isArray(mainMap.sources) ? mainMap.sources : [];

      // Read all part map sources
      const partMaps = {};
      for (const pf of partFiles) {
        const pMapPath = path.join(buildDir, `${pf.name}.map`);
        if (fs.existsSync(pMapPath)) {
          try {
            const pMap = JSON.parse(fs.readFileSync(pMapPath, 'utf8'));
            partMaps[`${pf.name}.map`] = Array.isArray(pMap.sources) ? pMap.sources : [];
          } catch {
            partMaps[`${pf.name}.map`] = [];
          }
        }
      }

      for (const mod of deferredModules) {
        const normMod = mod.replace(/\\/g, '/');
        const matchesInMain = mainSources.filter((s) => typeof s === 'string' && s.replace(/\\/g, '/').includes(normMod));
        const leakedInMain = matchesInMain.length > 0;

        const partChunks = [];
        for (const [pMapFile, sources] of Object.entries(partMaps)) {
          if (sources.some((s) => typeof s === 'string' && s.replace(/\\/g, '/').includes(normMod))) {
            partChunks.push(pMapFile);
          }
        }

        if (leakedInMain) {
          deferredIsolation.leaks.push({
            module: mod,
            matches: matchesInMain,
          });
          errors.push(`Deferred module LEAKED into ${mainMapName}: ${mod} (${matchesInMain.join(', ')})`);
        }

        if (partChunks.length === 0) {
          deferredIsolation.missingInParts.push(mod);
          errors.push(`Deferred module NOT FOUND in any part chunk sourcemap: ${mod}`);
        }

        deferredIsolation.modules.push({
          module: mod,
          leakedInMain,
          matchesInMain,
          partChunks,
          passed: !leakedInMain && partChunks.length > 0,
        });
      }

      for (const forbidden of forbiddenMainSources) {
        const normForbidden = forbidden.replace(/\\/g, '/');
        const matches = mainSources.filter(
          (s) => typeof s === 'string' && s.replace(/\\/g, '/').includes(normForbidden)
        );
        if (matches.length > 0) {
          deferredIsolation.forbiddenLeaks.push({ source: forbidden, matches });
          errors.push(`Forbidden source LEAKED into ${mainMapName}: ${forbidden} (${matches.join(', ')})`);
        }
      }

      deferredIsolation.passed =
        deferredIsolation.leaks.length === 0 &&
        deferredIsolation.missingInParts.length === 0 &&
        deferredIsolation.forbiddenLeaks.length === 0;
    }
  }

  lines.push(`Deferred Module Isolation (${deferredModules.length} modules tracked): [${deferredIsolation.passed ? 'PASS' : 'FAIL'}]`);
  for (const m of deferredIsolation.modules) {
    if (m.passed) {
      lines.push(`  [OK]   ${m.module.padEnd(38)} -> chunk(s): [${m.partChunks.join(', ')}]`);
    } else {
      if (m.leakedInMain) {
        lines.push(`  [LEAK] ${m.module.padEnd(38)} -> FOUND IN ${mainMapName}: ${m.matchesInMain.join(', ')}`);
      }
      if (m.partChunks.length === 0) {
        lines.push(`  [MISS] ${m.module.padEnd(38)} -> NOT FOUND IN ANY PART MAP`);
      }
    }
  }
  lines.push(`Forbidden Main-Bundle Sources (${forbiddenMainSources.length} guarded): [${deferredIsolation.forbiddenLeaks.length === 0 ? 'PASS' : 'FAIL'}]`);
  for (const f of deferredIsolation.forbiddenLeaks) {
    lines.push(`  [LEAK] ${f.source.padEnd(38)} -> FOUND IN ${mainMapName}: ${f.matches.join(', ')}`);
  }
  lines.push('');

  // 4. Verify OpenType font integrity
  const fontDir = findFontDir(buildDir);
  const fontIntegrity = {
    fontDir,
    passed: true,
    fonts: [],
  };

  if (!fs.existsSync(fontDir)) {
    const msg = `Font directory not found: ${fontDir}`;
    errors.push(msg);
    fontIntegrity.passed = false;
  } else {
    for (const fontName of requiredFonts) {
      const fontPath = path.join(fontDir, fontName);
      if (!fs.existsSync(fontPath)) {
        errors.push(`Required font missing: ${fontName} (searched at ${fontPath})`);
        fontIntegrity.fonts.push({
          name: fontName,
          path: fontPath,
          size: 0,
          passed: false,
          error: 'missing',
        });
        fontIntegrity.passed = false;
      } else {
        const stat = fs.statSync(fontPath);
        const fontPassed = stat.size >= minFontBytes;
        if (!fontPassed) {
          errors.push(`Font file truncated: ${fontName} has size ${stat.size} B (< ${minFontBytes} B min)`);
          fontIntegrity.passed = false;
        }
        fontIntegrity.fonts.push({
          name: fontName,
          path: fontPath,
          size: stat.size,
          passed: fontPassed,
        });
      }
    }
  }

  lines.push(
    `OpenType Font Integrity (${requiredFonts.length} fonts checked, minimum ${formatBytes(minFontBytes)}): [${fontIntegrity.passed ? 'PASS' : 'FAIL'}]`
  );
  lines.push(`  Font Directory: ${fontDir}`);
  for (const f of fontIntegrity.fonts) {
    lines.push(`  - ${f.name.padEnd(32)} ${formatBytes(f.size).padEnd(20)} [${f.passed ? 'PASS' : 'FAIL'}]`);
  }
  lines.push('');

  const success = errors.length === 0;
  lines.push('================================================================================');
  lines.push(`OVERALL RESULT: ${success ? 'PASS (All bundle checks passed)' : 'FAIL (Issues detected)'}`);
  lines.push('================================================================================');

  if (errors.length > 0) {
    lines.push('Failures:');
    for (const err of errors) {
      lines.push(`  - ❌ ${err}`);
    }
  }

  return {
    success,
    mainBundle,
    partFiles,
    partCountPassed,
    minPartCount,
    deferredIsolation,
    fontIntegrity,
    errors,
    report: lines.join('\n'),
  };
}

// CLI execution
const currentFile = fileURLToPath(import.meta.url);
const invokedFile = process.argv[1] ? path.resolve(process.argv[1]) : '';

if (invokedFile === currentFile) {
  const targetDir = process.argv[2] || path.join('build', 'web');
  const result = checkWebBundle(targetDir);
  console.log(result.report);
  if (!result.success) {
    process.exitCode = 1;
  }
}
