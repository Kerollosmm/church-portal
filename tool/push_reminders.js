// Cloudflare Worker cron-only Occurrence Planner (ADR-060).
// Triggered 4x daily at minute 3 of hours 2, 8, 14, 20 UTC (3 2,8,14,20 * * *).
// Computes upcoming occurrences for liturgies, meetings, day events and seasons
// in Africa/Cairo time, and acts as the SOLE WRITER of meta/push_plan.

import {
  batchGetDocs,
  getCachedAccessToken,
  listCollection,
  setDocRest,
} from './firestore_rest.js';

/**
 * Normalizes a raw event key to its canonical topic key.
 * - Lowercases and replaces any char outside [a-z0-9-] with '-'
 * - Validates prefix: (lit|meeting|day|season)-
 * - Truncates ID part after prefix to at most 40 chars
 * Returns empty string if invalid.
 *
 * @param {string} rawEventKey
 * @returns {string} Canonical topic key or ''
 */
export function topicKey(rawEventKey) {
  if (!rawEventKey || typeof rawEventKey !== 'string') return '';
  const s = rawEventKey.trim().toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const m = s.match(/^(lit|meeting|day|season)-([a-z0-9-]{1,40})/);
  if (!m) return '';
  return `${m[1]}-${m[2]}`;
}

/**
 * Maps a canonical eventKey or rawEventKey to its reminderSource ('lit', 'mtg', 'day').
 */
export function reminderSourceOf(rawEventKey) {
  if (rawEventKey.startsWith('lit-') || rawEventKey.startsWith('season-')) {
    return 'lit';
  }
  if (rawEventKey.startsWith('meeting-')) {
    return 'mtg';
  }
  if (rawEventKey.startsWith('day-')) {
    return 'day';
  }
  return '';
}

/**
 * Gets date/time parts in Africa/Cairo timezone.
 */
export function getCairoParts(d) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
    second: 'numeric',
    hour12: false,
  }).formatToParts(d);
  const map = {};
  for (const p of parts) {
    if (p.type !== 'literal') map[p.type] = parseInt(p.value, 10);
  }
  if (map.hour === 24) map.hour = 0;
  return map;
}

/**
 * Converts Cairo wall time to a UTC Date object, handling Cairo DST transitions accurately.
 */
export function cairoToUtc(year, month, day, hour = 0, minute = 0) {
  // Approximate candidate at UTC+2
  const candidateUtc = new Date(Date.UTC(year, month - 1, day, hour - 2, minute));
  const c = getCairoParts(candidateUtc);
  const diffMinutes = hour * 60 + minute - (c.hour * 60 + c.minute);
  return new Date(candidateUtc.getTime() + diffMinutes * 60000);
}

/**
 * Computes 10-hex SHA-1 hash for a DayEvent fallback id.
 */
export async function computeDayEventHashId(date, start, titleAr) {
  const raw = `${date.trim()}\u001f${start.trim()}\u001f${titleAr.trim().normalize('NFC')}`;
  const data = new TextEncoder().encode(raw);
  const hashBuffer = await crypto.subtle.digest('SHA-1', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 10);
}

/**
 * Decodes 17-field dayEvent strings from settings/features.
 */
export async function decodeDayEvents(dayEventStrings = []) {
  const events = [];
  for (const s of dayEventStrings) {
    if (!s || typeof s !== 'string') continue;
    const parts = s.split('\u001f');
    if (parts.length < 13) continue;

    const date = (parts[0] || '').trim();
    let endDate = (parts[1] || '').trim() || date;
    if (endDate < date) endDate = date;
    const start = (parts[2] || '').trim();
    const end = (parts[3] || '').trim();
    const titleAr = (parts[4] || '').trim();
    const titleEn = (parts[5] || '').trim();
    const link = (parts[12] || '').trim();

    // 17th field is persistent ID (ADR-059)
    let id = (parts[16] || '').trim();
    if (!id) {
      id = await computeDayEventHashId(date, start, titleAr);
    }

    events.push({
      id,
      date,
      endDate,
      start,
      end,
      titleAr,
      titleEn,
      link,
    });
  }
  return events;
}

/**
 * Runs the occurrence planner cron job (Cron 3).
 *
 * @param {object} env Cloudflare Worker environment.
 * @param {object} [options={}] Optional test overrides.
 * @returns {Promise<object>} Summary of the planner run.
 */
export async function runPushReminderPlanner(env, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const now = options.now || new Date();
  const nowMs = now.getTime();
  const nowIso = now.toISOString();

  let rawSa = env.FIREBASE_SERVICE_ACCOUNT || options.serviceAccount;
  if (!rawSa && typeof process !== 'undefined' && process.env) {
    rawSa = process.env.FIREBASE_SERVICE_ACCOUNT;
  }
  if (!rawSa) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is required');
  }

  const sa = typeof rawSa === 'string' ? JSON.parse(rawSa) : rawSa;
  const projectId = env.FIREBASE_PROJECT_ID || sa.project_id || 'asafra-church-portal';

  let token = 'test-token';
  if (options.mintToken) {
    token = await options.mintToken(sa, fetchImpl, nowMs);
  } else {
    token = await getCachedAccessToken(sa, env, fetchImpl, nowMs);
  }

  // Read settings/features, liturgies, meetings, and seasons
  const [settingsDocs, liturgies, meetings, seasons] = await Promise.all([
    batchGetDocs(projectId, token, ['settings/features'], fetchImpl),
    listCollection(projectId, token, 'liturgies', fetchImpl),
    listCollection(projectId, token, 'meetings', fetchImpl),
    listCollection(projectId, token, 'seasons', fetchImpl),
  ]);

  const features = settingsDocs.get('settings/features')?.data || {};
  const dayEvents = await decodeDayEvents(features.dayEvents || []);

  const isVisible = (d) => d && d.hidden !== true && d.visible !== false;

  const isSeasonActiveAtMs = (seasonData, instantMs) => {
    if (!seasonData || seasonData.active !== true || !isVisible(seasonData)) return false;
    if (seasonData.startsAt) {
      const sMs = Date.parse(seasonData.startsAt);
      if (!Number.isNaN(sMs) && instantMs < sMs) return false;
    }
    if (seasonData.endsAt) {
      const eMs = Date.parse(seasonData.endsAt);
      if (!Number.isNaN(eMs) && instantMs > eMs) return false;
    }
    return true;
  };

  const isSeasonActiveOnCairoDay = (seasonData, year, month, day) => {
    if (!seasonData || seasonData.active !== true || !isVisible(seasonData)) return false;
    const dayStartMs = cairoToUtc(year, month, day, 0, 0).getTime();
    const nextDay = new Date(Date.UTC(year, month - 1, day + 1));
    const dayEndMs = cairoToUtc(
      nextDay.getUTCFullYear(),
      nextDay.getUTCMonth() + 1,
      nextDay.getUTCDate(),
      0,
      0,
    ).getTime();
    if (seasonData.startsAt) {
      const sMs = Date.parse(seasonData.startsAt);
      if (!Number.isNaN(sMs) && sMs >= dayEndMs) return false;
    }
    if (seasonData.endsAt) {
      const eMs = Date.parse(seasonData.endsAt);
      if (!Number.isNaN(eMs) && eMs < dayStartMs) return false;
    }
    return true;
  };

  const doesSeasonReplaceOnDay = (seasonData, isoDateStr) => {
    if (seasonData?.replacesRegular !== false) return true;
    return Array.isArray(seasonData?.replaceDates) && seasonData.replaceDates.includes(isoDateStr);
  };

  const activeEventKeysSet = new Set();
  const reminderPlan = [];

  // Register all known active event keys (skip hidden docs)
  for (const l of liturgies) {
    if (!isVisible(l.data || {})) continue;
    const rawKey = l.data?.seasonKey ? `season-${l.id}` : `lit-${l.id}`;
    const t = topicKey(rawKey);
    if (t) activeEventKeysSet.add(t);
  }
  for (const m of meetings) {
    if (!isVisible(m.data || {})) continue;
    const t = topicKey(`meeting-${m.id}`);
    if (t) activeEventKeysSet.add(t);
  }
  for (const de of dayEvents) {
    const t = topicKey(`day-${de.id}`);
    if (t) activeEventKeysSet.add(t);
  }

  // Plan upcoming occurrences across the next 3 days (today, tomorrow, day after)
  for (let offset = 0; offset <= 2; offset++) {
    // Current target day in Cairo
    const targetDate = new Date(now.getTime() + offset * 86400 * 1000);
    const cp = getCairoParts(targetDate);
    const year = cp.year;
    const month = cp.month;
    const day = cp.day;
    const yyyymmdd = `${year}${String(month).padStart(2, '0')}${String(day).padStart(2, '0')}`;
    const isoDateStr = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay() || 7; // ISO 1-7 (Mon-Sun)

    const activeSeasonsOnDay = seasons.filter((s) => isSeasonActiveOnCairoDay(s.data, year, month, day));
    const replacingSeasons = new Set(
      activeSeasonsOnDay.filter((s) => s.data?.replacesRegular !== false && s.data?.startsAt && s.data?.endsAt),
    );
    const additiveSeasonalCandidates = [];

    // 1. Seasonal liturgies active on this day & matching an active season
    for (const lit of liturgies) {
      const data = lit.data || {};
      if (!isVisible(data)) continue;
      if (!data.seasonKey) continue;
      const litDateIso = typeof data.date === 'string' ? data.date.slice(0, 10) : '';
      if (litDateIso) {
        if (litDateIso !== isoDateStr) continue;
      } else if (data.weekday !== weekday) {
        continue;
      }

      const startStr = (data.start || '').trim();
      if (!startStr) continue;

      const [sh, sm] = startStr.split(':').map((x) => parseInt(x, 10));
      const serviceStart = cairoToUtc(year, month, day, sh, sm);
      const serviceStartMs = serviceStart.getTime();
      const [eh, em] = (data.end || '').trim()
        ? data.end.trim().split(':').map((x) => parseInt(x, 10))
        : [Number.NaN, Number.NaN];
      const endMinRaw = !Number.isNaN(eh) && !Number.isNaN(em) ? eh * 60 + em : sh * 60 + sm + 120;
      const startMin = sh * 60 + sm;
      const serviceEndMs = serviceStartMs + ((endMinRaw <= startMin ? endMinRaw + 1440 : endMinRaw) - startMin) * 60000;

      const matchingSeasons = activeSeasonsOnDay.filter(
        (s) => (s.data?.key || s.id) === data.seasonKey && isSeasonActiveAtMs(s.data, serviceStartMs),
      );
      if (matchingSeasons.length === 0) continue;

      for (const s of matchingSeasons) {
        if (doesSeasonReplaceOnDay(s.data, isoDateStr)) {
          replacingSeasons.add(s);
        } else {
          additiveSeasonalCandidates.push({
            season: s,
            lit: data,
            startMs: serviceStartMs,
            endMs: serviceEndMs,
          });
        }
      }

      if (serviceStartMs < nowMs - 60000) continue;

      const rawKey = `season-${lit.id}`;
      const tKey = topicKey(rawKey);
      if (!tKey) continue;

      reminderPlan.push({
        tKey,
        startsAtUtc: serviceStart.toISOString(),
        serviceStartMs,
        leads: [0, 5, 10, 15, 30, 60, 120, 180, 1440],
        languages: ['ar', 'en'],
        titleAr: data.nameAr || 'خدمة موسمية',
        titleEn: data.nameEn || 'Seasonal Service',
        bodyAr: `تبدأ ${data.nameAr || 'الخدمة'} الساعة ${startStr}`,
        bodyEn: `${data.nameEn || 'Service'} starts at ${startStr}`,
        link: '/mass-schedule',
        isRecurring: false,
        yyyymmdd,
      });
    }

    // 2. Regular liturgies matching this date or weekday (unless replaced by active season)
    for (const lit of liturgies) {
      const data = lit.data || {};
      if (!isVisible(data)) continue;
      if (data.seasonKey) continue; // Seasonal liturgies handled above
      const litDateIso = typeof data.date === 'string' ? data.date.slice(0, 10) : '';
      if (litDateIso) {
        if (litDateIso !== isoDateStr) continue;
      } else {
        if (data.weekday !== weekday) continue;
      }
      const startStr = (data.start || '').trim();
      if (!startStr) continue;

      const [sh, sm] = startStr.split(':').map((x) => parseInt(x, 10));
      const serviceStart = cairoToUtc(year, month, day, sh, sm);
      const serviceStartMs = serviceStart.getTime();

      // Skip services in the past
      if (serviceStartMs < nowMs - 60000) continue;

      // Skip regular services superseded by an active overriding season or overlapping additive mass/service
      let superseded = false;
      for (const s of replacingSeasons) {
        if (isSeasonActiveAtMs(s.data, serviceStartMs)) {
          superseded = true;
          break;
        }
      }
      if (!superseded && additiveSeasonalCandidates.length > 0) {
        const [eh, em] = (data.end || '').trim()
          ? data.end.trim().split(':').map((x) => parseInt(x, 10))
          : [Number.NaN, Number.NaN];
        const endMinRaw = !Number.isNaN(eh) && !Number.isNaN(em) ? eh * 60 + em : sh * 60 + sm + 120;
        const startMin = sh * 60 + sm;
        const serviceEndMs = serviceStartMs + ((endMinRaw <= startMin ? endMinRaw + 1440 : endMinRaw) - startMin) * 60000;
        const litType = data.type || 'mass';
        for (const cand of additiveSeasonalCandidates) {
          if (cand.lit.sample === true && data.sample !== true) continue;
          const overlaps = serviceStartMs < cand.endMs && cand.startMs < serviceEndMs;
          if (litType === 'mass' && isSeasonActiveAtMs(cand.season.data, serviceStartMs)) {
            if (cand.lit.replacesDay === true || ((cand.lit.type || 'mass') === 'mass' && overlaps)) {
              superseded = true;
              break;
            }
          } else if ((litType === 'vespers' || litType === 'praise') && overlaps) {
            superseded = true;
            break;
          }
        }
      }
      if (superseded) continue;

      const rawKey = `lit-${lit.id}`;
      const tKey = topicKey(rawKey);
      if (!tKey) continue;

      reminderPlan.push({
        tKey,
        startsAtUtc: serviceStart.toISOString(),
        serviceStartMs,
        leads: [0, 5, 10, 15, 30, 60, 120, 180, 1440],
        languages: ['ar', 'en'],
        titleAr: data.nameAr || 'القداس الإلهي',
        titleEn: data.nameEn || 'Divine Liturgy',
        bodyAr: `يبدأ ${data.nameAr || 'القداس'} الساعة ${startStr} بكنيسة القديسين`,
        bodyEn: `${data.nameEn || 'Liturgy'} starts at ${startStr} at Saints Church`,
        link: '/mass-schedule',
        isRecurring: !litDateIso,
        yyyymmdd,
      });
    }

    // 3. Weekly meetings matching this weekday
    for (const mtg of meetings) {
      const data = mtg.data || {};
      if (!isVisible(data)) continue;
      if (data.weekday !== weekday) continue;
      const startStr = (data.start || '').trim();
      if (!startStr) continue;

      const [sh, sm] = startStr.split(':').map((x) => parseInt(x, 10));
      const serviceStart = cairoToUtc(year, month, day, sh, sm);
      const serviceStartMs = serviceStart.getTime();

      if (serviceStartMs < nowMs - 60000) continue;

      const rawKey = `meeting-${mtg.id}`;
      const tKey = topicKey(rawKey);
      if (!tKey) continue;

      reminderPlan.push({
        tKey,
        startsAtUtc: serviceStart.toISOString(),
        serviceStartMs,
        leads: [0, 5, 10, 15, 30, 60, 120, 180, 1440],
        languages: ['ar', 'en'],
        titleAr: data.nameAr || 'اجتماع الكنيسة',
        titleEn: data.nameEn || 'Church Meeting',
        bodyAr: `يبدأ ${data.nameAr || 'الاجتماع'} الساعة ${startStr}`,
        bodyEn: `${data.nameEn || 'Meeting'} starts at ${startStr}`,
        link: `/church-education/${encodeURIComponent(mtg.id)}`,
        isRecurring: true,
        yyyymmdd,
      });
    }

    // 4. Day events on this date
    for (const de of dayEvents) {
      if (isoDateStr < de.date || isoDateStr > de.endDate) continue;
      const startStr = (de.start || '').trim() || '18:00';
      const [sh, sm] = startStr.split(':').map((x) => parseInt(x, 10));
      const serviceStart = cairoToUtc(year, month, day, sh, sm);
      const serviceStartMs = serviceStart.getTime();

      if (serviceStartMs < nowMs - 60000) continue;

      const rawKey = `day-${de.id}`;
      const tKey = topicKey(rawKey);
      if (!tKey) continue;

      reminderPlan.push({
        tKey,
        startsAtUtc: serviceStart.toISOString(),
        serviceStartMs,
        leads: [0, 5, 10, 15, 30, 60, 120, 180, 1440],
        languages: ['ar', 'en'],
        titleAr: de.titleAr || 'مناسبة كنسية',
        titleEn: de.titleEn || de.titleAr || 'Church Event',
        bodyAr: `تبدأ «${de.titleAr}» الساعة ${startStr}`,
        bodyEn: `"${de.titleEn || de.titleAr}" starts at ${startStr}`,
        link: de.link || '/',
        isRecurring: false,
        yyyymmdd,
      });
    }
  }

  // Sort reminder plan by serviceStartMs ASC
  reminderPlan.sort((a, b) => a.serviceStartMs - b.serviceStartMs);

  const activeEventKeys = Array.from(activeEventKeysSet);

  // Write meta/push_plan as sole writer
  await setDocRest(
    projectId,
    token,
    'meta/push_plan',
    {
      reminderPlan,
      activeEventKeys,
      lastPlanAt: nowIso,
    },
    fetchImpl,
  ).catch((err) => {
    console.error('Failed to write meta/push_plan:', err);
  });

  return {
    status: 'ok',
    plannedCount: reminderPlan.length,
    activeEventKeysCount: activeEventKeys.length,
    lastPlanAt: nowIso,
  };
}
