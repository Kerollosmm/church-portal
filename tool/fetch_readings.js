#!/usr/bin/env node
/**
 * Builds /data/readings/<YYYY-MM-DD>.json (ADR-058 / PR B §3.5):
 * Full Katameros readings per Cairo day (yesterday … +9 days, 11 days total)
 * from the Katameros API (https://api.katameros.app/readings/gregorian/<dd-mm-yyyy>?languageId=3).
 *
 * Text policy (README §8 #17, decided 6 Nov 2026):
 * Arabic full text (Van Dyck, public domain) + English references only
 * ("refs-only", no NKJV text fetched or stored). refEn is built from bookId + ref
 * using the bundled 66-book English table. Target <= 25 KB uncompressed / ~8 KB gzip.
 *
 * Usage:
 *   node tool/fetch_readings.js <outDir> [--days 9] [--previous-dir <dir>]
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { copticDateOf } = require('./fetch_synaxarium');

const BIBLE_BOOKS_EN = {
  1: 'Genesis', 2: 'Exodus', 3: 'Leviticus', 4: 'Numbers', 5: 'Deuteronomy',
  6: 'Joshua', 7: 'Judges', 8: 'Ruth', 9: '1 Samuel', 10: '2 Samuel',
  11: '1 Kings', 12: '2 Kings', 13: '1 Chronicles', 14: '2 Chronicles', 15: 'Ezra',
  16: 'Nehemiah', 17: 'Esther', 18: 'Job', 19: 'Psalms', 20: 'Proverbs',
  21: 'Ecclesiastes', 22: 'Song of Solomon', 23: 'Isaiah', 24: 'Jeremiah', 25: 'Lamentations',
  26: 'Ezekiel', 27: 'Daniel', 28: 'Hosea', 29: 'Joel', 30: 'Amos',
  31: 'Obadiah', 32: 'Jonah', 33: 'Micah', 34: 'Nahum', 35: 'Habakkuk',
  36: 'Zephaniah', 37: 'Haggai', 38: 'Zechariah', 39: 'Malachi',
  40: 'Matthew', 41: 'Mark', 42: 'Luke', 43: 'John', 44: 'Acts',
  45: 'Romans', 46: '1 Corinthians', 47: '2 Corinthians', 48: 'Galatians', 49: 'Ephesians',
  50: 'Philippians', 51: 'Colossians', 52: '1 Thessalonians', 53: '2 Thessalonians', 54: '1 Timothy',
  55: '2 Timothy', 56: 'Titus', 57: 'Philemon', 58: 'Hebrews', 59: 'James',
  60: '1 Peter', 61: '2 Peter', 62: '1 John', 63: '2 John', 64: '3 John',
  65: 'Jude', 66: 'Revelation'
};

const API = 'https://api.katameros.app/readings/gregorian';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const iso = (d) => d.toISOString().slice(0, 10);
const ddmmyyyy = (d) => `${iso(d).slice(8, 10)}-${iso(d).slice(5, 7)}-${iso(d).slice(0, 4)}`;
const clean = (s) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim() : '');
const stripHtml = (s) => (typeof s === 'string' ? s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() : '');

/** Today's calendar date in Cairo as UTC midnight. */
function cairoToday() {
  const s = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date());
  return new Date(`${s}T00:00:00Z`);
}

/** Parses Katameros Arabic API JSON into our normalized DayReadings payload */
function parseKatamerosDay(d, date) {
  const sections = [];
  for (const s of d.sections || []) {
    let key = 'other';
    let titleAr = clean(s.title);
    let titleEn = 'Other';
    if (s.id === 1 || /عشية|vespers/i.test(titleAr)) {
      key = 'vespers';
      titleEn = 'Vespers';
    } else if (s.id === 2 || /باكر|matins/i.test(titleAr)) {
      key = 'matins';
      titleEn = 'Matins';
    } else if (s.id === 3 || /قداس|liturgy/i.test(titleAr)) {
      key = 'liturgy';
      titleEn = 'Liturgy';
    }

    const readings = [];
    for (const sub of s.subSections || []) {
      const subTitle = clean(sub.title);
      for (const r of sub.readings || []) {
        let kind = 'other';
        let rTitleAr = clean(r.title);
        let rTitleEn = 'Reading';

        if (sub.id === 1 || /مزمور.*إنجيل|psalm.*gospel/i.test(subTitle)) {
          const hasPsalm = readings.some((x) => x.kind === 'psalm');
          if (!hasPsalm) {
            kind = 'psalm';
            rTitleAr = 'المزمور';
            rTitleEn = 'Psalm';
          } else {
            kind = 'gospel';
            rTitleAr = 'الإنجيل';
            rTitleEn = 'Gospel';
          }
        } else if (sub.id === 3 || /بولس|pauline/i.test(subTitle)) {
          kind = 'pauline';
          rTitleAr = 'البولس';
          rTitleEn = 'Pauline Epistle';
        } else if (sub.id === 4 || /كاثوليكون|catholic/i.test(subTitle)) {
          kind = 'catholic';
          rTitleAr = 'الكاثوليكون';
          rTitleEn = 'Catholic Epistle';
        } else if (sub.id === 5 || /ابرك|إبرك|acts/i.test(subTitle)) {
          kind = 'acts';
          rTitleAr = 'الإبركسيس';
          rTitleEn = 'Acts of the Apostles';
        } else if (sub.id === 10 || /سنكسار|synaxar/i.test(subTitle)) {
          kind = 'synaxarium';
          rTitleAr = clean(r.title) || 'السنكسار';
          rTitleEn = 'Synaxarium';
        }

        const passages = r.passages || [];
        const refArParts = [];
        const refEnParts = [];
        const verseTexts = [];

        for (const p of passages) {
          const bookAr = clean(p.bookTranslation);
          const bookEn = BIBLE_BOOKS_EN[p.bookId] || (p.bookId === 19 ? 'Psalms' : bookAr);
          const ref = clean(p.ref);
          if (bookAr || ref) refArParts.push(`${bookAr} ${ref}`.trim());
          if (bookEn || ref) refEnParts.push(`${bookEn} ${ref}`.trim());
          for (const v of p.verses || []) {
            const vt = clean(v.text);
            if (vt) verseTexts.push(vt);
          }
        }

        let textAr = verseTexts.join(' ');
        if (!textAr && r.html) {
          textAr = stripHtml(r.html);
        }

        readings.push({
          kind,
          titleAr: rTitleAr || rTitleEn,
          titleEn: rTitleEn,
          refAr: refArParts.join('; '),
          refEn: refEnParts.join('; '),
          introAr: clean(r.introduction),
          introEn: '',
          textAr,
          textEn: '',
          conclusionAr: clean(r.conclusion),
          conclusionEn: '',
        });
      }
    }
    sections.push({ key, titleAr, titleEn, readings });
  }

  return {
    date: iso(date),
    coptic: clean(d.copticDate) || copticDateOf(date),
    titleAr: clean(d.title),
    titleEn: '',
    sections,
    source: 'api.katameros.app',
    bibleAr: 'Van Dyck',
    bibleEn: 'refs-only',
  };
}

async function fetchDayRaw(date) {
  const url = `${API}/${ddmmyyyy(date)}?languageId=3`;
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 25000);
  try {
    const res = await fetch(url, {
      signal: ctl.signal,
      headers: {
        Accept: 'application/json',
        'User-Agent': 'church-portal (github.com/Kerollosmm/church-portal)',
      },
    });
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(t);
  }
}

async function fetchDayWithRetry(date) {
  try {
    return await fetchDayRaw(date);
  } catch (e) {
    console.warn(`retry Katameros ${iso(date)}: ${e.message}`);
    await sleep(1500);
    return fetchDayRaw(date);
  }
}

function argValue(args, name) {
  const eq = args.find((a) => a.startsWith(`${name}=`));
  if (eq) return eq.slice(name.length + 1);
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : null;
}

/** Days ahead of today (`--days 9` or `--days=9`), clamped to 1…14; default 9 (PR B §3.5). */
function parseDaysArg(args) {
  const n = parseInt(argValue(args, '--days') || '9', 10);
  return Math.min(Math.max(Number.isFinite(n) ? n : 9, 1), 14);
}

/** The currently published file for [dateStr], validated as JSON; null when there is none. */
async function fetchPrevious(baseUrl, dateStr) {
  const url = `${baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`}${dateStr}.json`;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15000);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) return null;
    const text = await res.text();
    const json = JSON.parse(text);
    return json && json.date === dateStr ? text : null;
  } finally {
    clearTimeout(t);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const outDir = args.find((a) => !a.startsWith('--'));
  const AHEAD = parseDaysArg(args);
  const prevDir = argValue(args, '--previous-dir');
  // Live copy of the window (e.g. https://…/data/readings/): a date whose Katameros call fails keeps
  // the file already published, so a multi-file publish never drops a day that was online.
  const prevUrl = argValue(args, '--previous-url');

  if (!outDir && require.main === module) {
    console.error('usage: node tool/fetch_readings.js <outDir> [--days 9] [--previous-dir <dir>] [--previous-url <base>]');
    process.exit(2);
  }

  const start = cairoToday();
  start.setUTCDate(start.getUTCDate() - 1); // Yesterday in Cairo
  const totalDays = AHEAD + 1; // yesterday ... +AHEAD days
  let writtenCount = 0;

  fs.mkdirSync(outDir, { recursive: true });

  for (let i = 0; i <= totalDays; i++) {
    const d = new Date(start);
    d.setUTCDate(start.getUTCDate() + i);
    const dateStr = iso(d);
    const targetFile = path.join(outDir, `${dateStr}.json`);

    try {
      const raw = await fetchDayWithRetry(d);
      const parsed = parseKatamerosDay(raw, d);
      const jsonStr = JSON.stringify(parsed);
      const bytes = Buffer.byteLength(jsonStr, 'utf8'); // Arabic text: UTF-8 bytes, not UTF-16 units
      const gzSize = zlib.gzipSync(jsonStr).length;

      fs.writeFileSync(targetFile, jsonStr);
      writtenCount++;
      console.log(`wrote ${dateStr}.json: ${bytes} B (gzip: ${gzSize} B)`);
      if (gzSize > 25600) {
        console.warn(`WARNING: ${dateStr}.json gzip size (${gzSize} B) exceeds 25 KB target`);
      }
      await sleep(300);
    } catch (e) {
      console.warn(`failed to fetch ${dateStr}: ${e.message}`);
      // Fallback: check previous directory or existing target file
      let fallbackFound = false;
      const candidates = [
        prevDir ? path.join(prevDir, `${dateStr}.json`) : null,
        targetFile,
      ].filter(Boolean);

      for (const cand of candidates) {
        if (fs.existsSync(cand)) {
          try {
            const existing = fs.readFileSync(cand, 'utf8');
            JSON.parse(existing); // validate JSON
            if (cand !== targetFile) {
              fs.writeFileSync(targetFile, existing);
            }
            console.log(`kept previous file for ${dateStr}`);
            writtenCount++;
            fallbackFound = true;
            break;
          } catch (_) {}
        }
      }

      if (!fallbackFound && prevUrl) {
        try {
          const live = await fetchPrevious(prevUrl, dateStr);
          if (live) {
            fs.writeFileSync(targetFile, live);
            console.log(`kept live file for ${dateStr}`);
            writtenCount++;
            fallbackFound = true;
          }
        } catch (err) {
          console.warn(`no live copy for ${dateStr}: ${err.message}`);
        }
      }

      if (!fallbackFound) {
        console.warn(`no fallback available for ${dateStr}`);
      }
    }
  }

  if (writtenCount === 0) {
    console.error('ERROR: No readings could be fetched or preserved');
    process.exit(1);
  }
  console.log(`Successfully completed fetch_readings: ${writtenCount} days written`);
}

module.exports = {
  BIBLE_BOOKS_EN,
  parseKatamerosDay,
  cairoToday,
  parseDaysArg,
  argValue,
};

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
