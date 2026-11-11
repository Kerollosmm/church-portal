// Pure Web-API Katameros & Synaxarium daily synchronizer (ADR-063).
// ESM, zero native Node.js dependencies (compatible with workerd and Node 22+).
// Dual-persists daily Katameros readings and Synaxarium commemorations to:
// 1. Firestore REST: readings/<YYYY-MM-DD>
// 2. Cloudflare KV: PUSH_KV under reading:<YYYY-MM-DD> (TTL 7 days)

import { getCachedAccessToken, setDocRest } from './firestore_rest.js';

export const BIBLE_BOOKS_EN = {
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

export const API_BASE = 'https://api.katameros.app/readings/gregorian';
const KV_TTL_SECONDS = 7 * 86400; // 7 days

const clean = (s) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim() : '');
const stripHtml = (s) => (typeof s === 'string' ? s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() : '');

/**
 * Calculates the active liturgical Coptic date in YYYY-MM-DD.
 * Liturgical day rollover happens at 6:00 PM Cairo wall-clock time (18:00 Cairo / 16:00 UTC in standard time).
 * At or after 18:00 Cairo time, the liturgical day rolls over to tomorrow's date.
 *
 * @param {Date} [now=new Date()]
 * @returns {string} Target liturgical date in 'YYYY-MM-DD'
 */
export function calculateLiturgicalRolloverDate(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(now);

  const m = {};
  for (const p of parts) m[p.type] = p.value;

  const year = parseInt(m.year, 10);
  const month = parseInt(m.month, 10);
  const day = parseInt(m.day, 10);
  const hour = parseInt(m.hour, 10);

  if (hour >= 18) {
    const d = new Date(Date.UTC(year, month - 1, day + 1));
    return d.toISOString().slice(0, 10);
  }
  const d = new Date(Date.UTC(year, month - 1, day));
  return d.toISOString().slice(0, 10);
}

/**
 * Converts a YYYY-MM-DD string into dd-MM-yyyy format expected by Katameros API.
 *
 * @param {string} dateIso e.g. "2026-11-12"
 * @returns {string} e.g. "12-11-2026"
 */
export function formatDdMmYyyy(dateIso) {
  const [y, m, d] = dateIso.split('-');
  return `${d}-${m}-${y}`;
}

/**
 * Local Julian Day Number calculation for Coptic calendar date (D/M/YYYY).
 * Fallback when Katameros API returns copticDate: null.
 *
 * @param {string} dateIso 'YYYY-MM-DD'
 * @returns {string} e.g. '2/3/1743'
 */
export function copticDateOfIso(dateIso) {
  const [ys, ms, ds] = dateIso.split('-');
  const y = parseInt(ys, 10);
  const m = parseInt(ms, 10);
  const d = parseInt(ds, 10);

  const a = Math.floor((14 - m) / 12);
  const yy = y + 4800 - a;
  const mm = m + 12 * a - 3;
  const jdn = d + Math.floor((153 * mm + 2) / 5) + 365 * yy + Math.floor(yy / 4) - Math.floor(yy / 100) +
    Math.floor(yy / 400) - 32045;
  const EPOCH = 1825030;
  const year = Math.floor((4 * (jdn - EPOCH) + 1463) / 1461);
  const start = EPOCH - 1 + 365 * (year - 1) + Math.floor(year / 4) + 1;
  const month = Math.floor((jdn - start) / 30) + 1;
  const day = jdn - start - 30 * (month - 1) + 1;
  return `${day}/${month}/${year}`;
}

/**
 * Normalizes raw Katameros Arabic API response into canonical DayReadings payload.
 *
 * @param {object} raw Raw API JSON from Katameros.
 * @param {string} dateIso 'YYYY-MM-DD'.
 * @returns {object} Canonical DayReadings JSON.
 */
export function parseKatamerosDay(raw, dateIso) {
  const sections = [];
  for (const s of raw.sections || []) {
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
    date: dateIso,
    coptic: clean(raw.copticDate) || copticDateOfIso(dateIso),
    titleAr: clean(raw.title),
    titleEn: '',
    sections,
    source: 'api.katameros.app',
    bibleAr: 'Van Dyck',
    bibleEn: 'refs-only',
  };
}

/**
 * Counts total readings and synaxarium items in normalized DayReadings payload.
 */
export function countReadingsAndSynaxarium(dayReadings) {
  let readingsCount = 0;
  let synaxariumCount = 0;
  for (const sec of dayReadings.sections || []) {
    for (const r of sec.readings || []) {
      readingsCount++;
      if (r.kind === 'synaxarium') {
        synaxariumCount++;
      }
    }
  }
  return { readingsCount, synaxariumCount };
}

/**
 * Fetches Katameros API for a specific date in ISO format.
 *
 * @param {string} dateIso 'YYYY-MM-DD'
 * @param {typeof fetch} [fetchImpl=fetch]
 * @returns {Promise<object>} Raw API JSON
 */
export async function fetchKatamerosRaw(dateIso, fetchImpl = fetch) {
  const ddmmyyyy = formatDdMmYyyy(dateIso);
  const url = `${API_BASE}/${ddmmyyyy}?languageId=3`;
  const res = await fetchImpl(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'church-portal (github.com/Kerollosmm/church-portal)',
    },
  });

  if (!res.ok) {
    throw new Error(`Katameros API failed (${res.status}) for ${dateIso}: ${url}`);
  }

  return await res.json();
}

/**
 * Main ingestion routine migrating Katameros and Synaxarium into Cloudflare Worker.
 *
 * @param {object} env Cloudflare Worker environment (contains PUSH_KV, FIREBASE_SERVICE_ACCOUNT, etc.)
 * @param {object} [options={}]
 * @param {string} [options.targetDate] Optional override date (YYYY-MM-DD). Default computed via rollover.
 * @param {boolean} [options.force=false] Force overwrite even if KV/Firestore already has fresh data.
 * @param {typeof fetch} [options.fetchImpl=fetch] Fetch implementation.
 * @param {number} [options.nowMs=Date.now()]
 * @returns {Promise<{ date: string, status: 'ok' | 'skipped' | 'error', readingsCount: number, synaxariumCount: number, error?: string }>}
 */
export async function syncDailyReadingsAndSynaxarium(env, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const nowMs = options.nowMs || Date.now();
  const dateIso = options.targetDate || calculateLiturgicalRolloverDate(new Date(nowMs));
  const force = Boolean(options.force);

  // 1. Idempotency check via KV
  const kvKey = `reading:${dateIso}`;
  if (!force && env?.PUSH_KV?.get) {
    try {
      const existing = await env.PUSH_KV.get(kvKey, { type: 'json' });
      if (existing && existing.sections && existing.sections.length > 0) {
        const { readingsCount, synaxariumCount } = countReadingsAndSynaxarium(existing);
        return {
          date: dateIso,
          status: 'skipped',
          readingsCount,
          synaxariumCount,
        };
      }
    } catch (e) {
      console.warn(`[readings_syncer] KV check error for ${kvKey}:`, e);
    }
  }

  // 2. Fetch from Katameros API
  let rawData;
  try {
    rawData = await fetchKatamerosRaw(dateIso, fetchImpl);
  } catch (err) {
    console.error(`[readings_syncer] Failed to fetch Katameros readings for ${dateIso}:`, err);
    return {
      date: dateIso,
      status: 'error',
      readingsCount: 0,
      synaxariumCount: 0,
      error: err?.message || String(err),
    };
  }

  // 3. Normalize DayReadings payload
  const dayReadings = parseKatamerosDay(rawData, dateIso);
  const { readingsCount, synaxariumCount } = countReadingsAndSynaxarium(dayReadings);

  // 4. Resolve Firebase Service Account & token
  let rawSa = env?.FIREBASE_SERVICE_ACCOUNT || options.serviceAccount;
  if (!rawSa && typeof process !== 'undefined' && process.env?.FIREBASE_SERVICE_ACCOUNT) {
    rawSa = process.env.FIREBASE_SERVICE_ACCOUNT;
  }

  if (rawSa) {
    const sa = typeof rawSa === 'string' ? JSON.parse(rawSa) : rawSa;
    const projectId = env?.FIREBASE_PROJECT_ID || sa.project_id || 'asafra-church-portal';
    try {
      const token = await getCachedAccessToken(sa, env, fetchImpl, nowMs);
      await setDocRest(projectId, token, `readings/${dateIso}`, dayReadings, fetchImpl);
    } catch (err) {
      console.error(`[readings_syncer] Firestore write failed for readings/${dateIso}:`, err);
      // We still attempt to cache in KV even if Firestore write had an issue
    }
  } else {
    console.warn(`[readings_syncer] No FIREBASE_SERVICE_ACCOUNT provided; skipping Firestore write.`);
  }

  // 5. Cache in PUSH_KV with 7-day TTL
  if (env?.PUSH_KV?.put) {
    try {
      await env.PUSH_KV.put(kvKey, JSON.stringify(dayReadings), {
        expirationTtl: KV_TTL_SECONDS,
      });
    } catch (e) {
      console.warn(`[readings_syncer] Failed to write KV for ${kvKey}:`, e);
    }
  }

  return {
    date: dateIso,
    status: 'ok',
    readingsCount,
    synaxariumCount,
  };
}
