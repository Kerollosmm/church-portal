// Daily Coptic seasons alert evaluator (runs once per Cairo calendar day).
// Standard Web APIs only (compatible with Cloudflare Workers and Node.js 22+).

import { listCollection } from './firestore_rest.js';

/**
 * Default season template configuration.
 */
export const DEFAULT_SEASONS_SPEC = {
  id: 'seasons',
  time: '09:00',
  daysBefore: 3,
  titleAr: 'موسم كنسي: {season}',
  titleEn: 'Church Season: {season}',
  bodyAr: 'يبدأ {season} بعد {days} أيام — بركة الموسم تشملنا جميعًا',
  bodyEn: 'Season of {season} begins in {days} days',
  defaultLink: '/seasons',
};

/**
 * Returns the current date (YYYY-MM-DD) and time (HH:mm) in Africa/Cairo.
 */
export function getCairoNow(now = new Date()) {
  const dateStr = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Cairo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);

  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Cairo',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(now);

  const hh = (parts.find((p) => p.type === 'hour')?.value || '00').padStart(2, '0');
  const mm = (parts.find((p) => p.type === 'minute')?.value || '00').padStart(2, '0');
  return { dateIso: dateStr, hhmm: `${hh}:${mm}` };
}

/**
 * Parses the 'seasons' row from features.notifyTypes (if configured) or returns defaults.
 */
export function getSeasonsSpec(features) {
  const rows = Array.isArray(features?.notifyTypes) ? features.notifyTypes : [];
  for (const r of rows) {
    if (typeof r === 'string' && r.startsWith('seasons\x1f')) {
      const parts = r.split('\x1f');
      return {
        id: 'seasons',
        time: parts[1]?.trim() || DEFAULT_SEASONS_SPEC.time,
        daysBefore: parts[2] !== undefined && parts[2] !== '' ? parseInt(parts[2], 10) : DEFAULT_SEASONS_SPEC.daysBefore,
        titleAr: parts[3]?.trim() || DEFAULT_SEASONS_SPEC.titleAr,
        titleEn: parts[4]?.trim() || DEFAULT_SEASONS_SPEC.titleEn,
        bodyAr: parts[5]?.trim() || DEFAULT_SEASONS_SPEC.bodyAr,
        bodyEn: parts[6]?.trim() || DEFAULT_SEASONS_SPEC.bodyEn,
        defaultLink: DEFAULT_SEASONS_SPEC.defaultLink,
      };
    }
  }
  return DEFAULT_SEASONS_SPEC;
}

/**
 * Renders placeholders ({season}, {days}, {date}) in a template.
 */
export function renderTemplate(template, vars) {
  let res = template;
  for (const [k, v] of Object.entries(vars)) {
    res = res.replaceAll(`{${k}}`, v ?? '');
  }
  return res;
}

/**
 * Evaluates and sends once-daily season alerts if due.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {object} features Doc settings/features.
 * @param {object} health Doc settings/notifications.health.
 * @param {Array<string>} sentLog Array of sentLog entries from settings/notifications.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @param {Date} [now=new Date()] Current instant.
 * @returns {Promise<{ alerts: Array<object>, lastSeasonDate: string|null, skippedReason?: string }>}
 */
export async function runDailySeasons(
  projectId,
  token,
  features,
  health,
  sentLog = [],
  fetchImpl = fetch,
  now = new Date(),
) {
  const cairoNow = getCairoNow(now);
  const seasonsSpec = getSeasonsSpec(features);

  if (features?.push !== true) {
    return { alerts: [], lastSeasonDate: health?.lastSeasonDate || null, skippedReason: 'push_disabled' };
  }
  const pushTypes = Array.isArray(features?.pushTypes) ? features.pushTypes : [];
  if (!pushTypes.includes('seasons')) {
    return { alerts: [], lastSeasonDate: health?.lastSeasonDate || null, skippedReason: 'seasons_type_disabled' };
  }
  if (cairoNow.hhmm < seasonsSpec.time) {
    return { alerts: [], lastSeasonDate: health?.lastSeasonDate || null, skippedReason: 'before_scheduled_time' };
  }
  if (cairoNow.hhmm >= '22:00' || cairoNow.hhmm < '06:00') {
    return { alerts: [], lastSeasonDate: health?.lastSeasonDate || null, skippedReason: 'quiet_hours' };
  }
  if (health?.lastSeasonDate === cairoNow.dateIso) {
    return { alerts: [], lastSeasonDate: health.lastSeasonDate, skippedReason: 'already_run_today' };
  }

  // Read seasons collection (~5 documents, performed ONLY once per calendar day)
  const seasons = await listCollection(projectId, token, 'seasons', fetchImpl);

  // Extract sent keys from sentLog (format: key␟sentAtIso␟result␟title␟trigger)
  const sentKeys = new Set();
  for (const entry of sentLog) {
    if (typeof entry === 'string') {
      const k = entry.split('\x1f')[0];
      if (k) sentKeys.add(k);
    }
  }

  // Calculate target date for daysBefore
  const cairoDate = new Date(`${cairoNow.dateIso}T00:00:00Z`);
  const targetDateObj = new Date(cairoDate.getTime() + seasonsSpec.daysBefore * 86400000);
  const targetDateIso = targetDateObj.toISOString().slice(0, 10);

  const alerts = [];

  for (const s of seasons) {
    const data = s.data || {};
    if (data.active === false) continue;

    // Get start date ISO
    let startDateIso = '';
    if (typeof data.startsAt === 'string') {
      startDateIso = data.startsAt.slice(0, 10);
    } else if (data.startsAt?.timestampValue) {
      startDateIso = data.startsAt.timestampValue.slice(0, 10);
    }
    if (!startDateIso) continue;

    let daysRemaining = null;
    if (startDateIso === cairoNow.dateIso) {
      daysRemaining = 0;
    } else if (seasonsSpec.daysBefore > 0 && startDateIso === targetDateIso) {
      daysRemaining = seasonsSpec.daysBefore;
    }

    if (daysRemaining === null) continue;

    const logKey = `season:${s.id}:${startDateIso}:${daysRemaining}`;
    if (sentKeys.has(logKey)) continue;

    const nameAr = data.nameAr?.trim() || 'الموسم الكنسي';
    const nameEn = data.nameEn?.trim() || nameAr;

    const varsAr = {
      season: nameAr,
      days: String(daysRemaining),
      date: startDateIso,
    };
    const varsEn = {
      season: nameEn,
      days: String(daysRemaining),
      date: startDateIso,
    };

    let titleAr = renderTemplate(seasonsSpec.titleAr, varsAr);
    let titleEn = renderTemplate(seasonsSpec.titleEn, varsEn);
    let bodyAr = renderTemplate(seasonsSpec.bodyAr, varsAr);
    let bodyEn = renderTemplate(seasonsSpec.bodyEn, varsEn);

    if (daysRemaining === 0) {
      // Starting today override
      bodyAr = `يبدأ اليوم ${nameAr} — بركة الموسم تشملنا جميعًا`;
      bodyEn = `${nameEn} begins today — blessed season to all`;
    }

    const nid = `season:${s.id}:${startDateIso}`;
    const link = seasonsSpec.defaultLink || '/seasons';
    const eventKey = `season-${s.id}`;

    alerts.push({
      logKey,
      nid,
      seasonId: s.id,
      daysRemaining,
      titleAr,
      titleEn,
      bodyAr,
      bodyEn,
      link,
      eventKey,
    });
  }

  return {
    alerts,
    lastSeasonDate: cairoNow.dateIso,
  };
}
