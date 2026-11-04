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
 * run makes ~18 small GETs twice a day. A day that fails is left out (the
 * app then shows its computed feast list for that day). Exits non-zero only
 * when no day at all could be fetched, so the workflow keeps the last file.
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
if (!out) {
  console.error('usage: node tool/fetch_synaxarium.js <out.json> [--days 8]');
  process.exit(2);
}

const API = 'https://api.katameros.app/readings/gregorian';
const LANG = { ar: 3, en: 2 };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Today's calendar date in Cairo as a UTC-midnight Date. */
function cairoToday() {
  const s = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date());
  return new Date(`${s}T00:00:00Z`);
}

const iso = (d) => d.toISOString().slice(0, 10);
const ddmmyyyy = (d) => `${iso(d).slice(8, 10)}-${iso(d).slice(5, 7)}-${iso(d).slice(0, 4)}`;
const clean = (s) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim().slice(0, 300) : '');

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
    return { feast: clean(d.title), coptic: clean(d.copticDate), synaxarium: synaxarium.slice(0, 6) };
  } finally {
    clearTimeout(t);
  }
}

(async () => {
  const start = cairoToday();
  start.setUTCDate(start.getUTCDate() - 1);
  const days = {};
  for (let i = 0; i <= AHEAD; i++) {
    const d = new Date(start);
    d.setUTCDate(start.getUTCDate() + i);
    try {
      const ar = await fetchDay(d, 'ar');
      await sleep(300);
      let en = { feast: '', synaxarium: [] };
      try {
        en = await fetchDay(d, 'en');
      } catch (e) {
        console.warn(`english ${iso(d)}: ${e.message}`);
      }
      await sleep(300);
      days[iso(d)] = { coptic: ar.coptic, feastAr: ar.feast, feastEn: en.feast, ar: ar.synaxarium, en: en.synaxarium };
    } catch (e) {
      console.warn(`skip ${iso(d)}: ${e.message}`);
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
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
