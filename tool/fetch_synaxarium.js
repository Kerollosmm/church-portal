#!/usr/bin/env node
/**
 * Builds /data/today.json (ADR-040): the day's Coptic commemoration
 * (Synaxarium) and feast title for the Cairo days yesterday … +7, from the
 * open-source Katameros API (https://github.com/pierresaid/katameros-api,
 * MIT; https://api.katameros.app, no key, no documented rate limit).
 *
 *   node tool/fetch_synaxarium.js <out.json> [--days 8]
 *
 * 2 requests per day (Arabic + English), sequential with a short pause, so a
 * run makes ~18 small GETs twice a day; a failed request is retried once.
 * A day is written only when BOTH languages were fetched (the app treats a
 * stored day as complete and would not re-fetch a missing English part).
 * A day that still fails keeps its entry from the previously published file
 * (the live /data/today.json, or $PREVIOUS_URL), so a transient failure never
 * removes a commemoration visitors already had; with no previous entry it is
 * left out (the app then shows its computed feast list for that day). Exits
 * non-zero only when no day at all is available, so the workflow keeps the
 * last file.
 *
 * Output (≈ 3–5 KB):
 * {"source": "api.katameros.app", "fetchedAt": ISO,
 *  "days": {"YYYY-MM-DD": {"coptic": "25/2/1743", "feastAr": "", "feastEn": "",
 *                          "ar": ["…"], "en": ["…"]}}}
 */
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const out = args.find((a) => !a.startsWith('--'));
const di = args.indexOf('--days');
const AHEAD = Math.min(Math.max(parseInt((di >= 0 && args[di + 1]) || '8', 10) || 8, 1), 14);
if (!out && require.main === module) {
  console.error('usage: node tool/fetch_synaxarium.js <out.json> [--days 8]');
  process.exit(2);
}

const API = 'https://api.katameros.app/readings/gregorian';
const LANG = { ar: 3, en: 2 };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PREVIOUS_URL = process.env.PREVIOUS_URL || 'https://maximos-domadios-church.web.app/data/today.json';

/** Today's calendar date in Cairo as a UTC-midnight Date. */
function cairoToday() {
  const s = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date());
  return new Date(`${s}T00:00:00Z`);
}

const iso = (d) => d.toISOString().slice(0, 10);
const ddmmyyyy = (d) => `${iso(d).slice(8, 10)}-${iso(d).slice(5, 7)}-${iso(d).slice(0, 4)}`;
const clean = (s) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim().slice(0, 300) : '');

/**
 * The Coptic date of a Gregorian calendar date as Katameros writes it
 * ("D/M/YYYY", e.g. 8 Nov 2026 -> "29/2/1743"), computed locally through the
 * Julian Day Number: the same algorithm as CopticDate.fromGregorian in
 * lib/domain/coptic_calendar.dart (1 Tout 1 AM = JDN 1825030). Used when the
 * API answers `copticDate: null` (ADR-046; seen for 2026-11-08).
 */
function copticDateOf(date) {
  const y = date.getUTCFullYear();
  const m = date.getUTCMonth() + 1;
  const d = date.getUTCDate();
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

async function fetchDay(date, lang) {
  const url = `${API}/${ddmmyyyy(date)}?languageId=${LANG[lang]}`;
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 20000);
  try {
    const res = await fetch(url, {
      signal: ctl.signal,
      headers: { Accept: 'application/json', 'User-Agent': 'church-portal (github.com/Kerollosmm/church-portal)' },
    });
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    const d = await res.json();
    const synaxarium = [];
    for (const s of d.sections || []) {
      for (const sub of s.subSections || []) {
        if (/سنكسار|synaxar/i.test(sub.title || '')) {
          for (const r of sub.readings || []) {
            const t2 = clean(r.title);
            if (t2) synaxarium.push(t2);
          }
        }
      }
    }
    return { feast: clean(d.title), coptic: clean(d.copticDate) || copticDateOf(date), synaxarium: synaxarium.slice(0, 6) };
  } finally {
    clearTimeout(t);
  }
}

/** One retry after a short pause (transient network / 5xx). */
async function fetchDayRetry(date, lang) {
  try {
    return await fetchDay(date, lang);
  } catch (e) {
    console.warn(`retry ${lang} ${iso(date)}: ${e.message}`);
    await sleep(1500);
    return fetchDay(date, lang);
  }
}

/** Days of the previously published file ({} when unavailable). */
async function previousDays() {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 20000);
  try {
    const res = await fetch(PREVIOUS_URL, { signal: ctl.signal, headers: { Accept: 'application/json' } });
    if (!res.ok) return {};
    const j = await res.json();
    return j && typeof j.days === 'object' && j.days ? j.days : {};
  } catch (e) {
    console.warn(`previous file unavailable: ${e.message}`);
    return {};
  } finally {
    clearTimeout(t);
  }
}

async function main() {
  const start = cairoToday();
  start.setUTCDate(start.getUTCDate() - 1);
  const days = {};
  let previous = null;
  for (let i = 0; i <= AHEAD; i++) {
    const d = new Date(start);
    d.setUTCDate(start.getUTCDate() + i);
    try {
      const ar = await fetchDayRetry(d, 'ar');
      await sleep(300);
      const en = await fetchDayRetry(d, 'en');
      await sleep(300);
      days[iso(d)] = { coptic: ar.coptic, feastAr: ar.feast, feastEn: en.feast, ar: ar.synaxarium, en: en.synaxarium };
    } catch (e) {
      if (previous === null) previous = await previousDays();
      const old = previous[iso(d)];
      if (old && typeof old === 'object') {
        days[iso(d)] = old;
        console.warn(`kept the published ${iso(d)}: ${e.message}`);
      } else {
        console.warn(`skip ${iso(d)}: ${e.message}`);
      }
    }
  }
  if (Object.keys(days).length === 0) {
    console.error('no day could be fetched');
    process.exit(1);
  }
  const json = JSON.stringify({ source: 'api.katameros.app', fetchedAt: new Date().toISOString(), days });
  fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  fs.writeFileSync(out, json);
  console.log(`wrote ${out}: ${Object.keys(days).length} days, ${json.length} bytes`);
}

module.exports = { copticDateOf };

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
