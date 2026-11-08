// Pure Web-API FCM push sender and scheduler for church-portal (ADR-059).
// Runs every 15 minutes on Cloudflare Workers cron (*/15 * * * *) and as a Node 22 CLI fallback.
// Zero native Node dependencies. Strictly capped at 16 FCM topic sends and <= 25 subrequests per run.

import { batchGetDocs, patchDoc } from './firestore_rest.js';
import { getCairoNow, runDailySeasons } from './push_daily.js';

export const MAX_FCM_SENDS_PER_RUN = 16;
export const MAX_SENT_LOG_SIZE = 30;
export const CLAIM_STALE_MS = 10 * 60 * 1000; // 10 minutes
export const EXPIRE_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours

/**
 * Checks in with Sentry Crons monitor if URL is configured (fail-open).
 */
export async function sentryCheckIn(cronsUrl, status, fetchImpl = fetch) {
  if (!cronsUrl || typeof cronsUrl !== 'string') return;
  try {
    const sep = cronsUrl.includes('?') ? '&' : '?';
    await fetchImpl(`${cronsUrl}${sep}status=${status}`, { method: 'POST' });
  } catch (err) {
    // Fail-open: monitoring errors must not abort push delivery
  }
}

/**
 * Parses a ScheduledNotification string row (9 \u001f-separated fields).
 */
export function parseScheduleRow(raw) {
  if (typeof raw !== 'string') return null;
  const parts = raw.split('\x1f');
  if (parts.length < 9) return null;
  const [id, atUtcIso, targets, titleAr, titleEn, bodyAr, bodyEn, link, eventKey] = parts;
  if (!id || !atUtcIso || !titleAr || !bodyAr || !link) return null;
  const atUtc = new Date(atUtcIso);
  if (isNaN(atUtc.getTime())) return null;

  return {
    id: id.trim(),
    atUtcIso: atUtcIso.trim(),
    atUtc,
    targets: targets.trim() || 'all',
    titleAr: titleAr.trim(),
    titleEn: titleEn.trim(),
    bodyAr: bodyAr.trim(),
    bodyEn: bodyEn.trim(),
    link: link.trim(),
    eventKey: eventKey.trim(),
  };
}

/**
 * Sends a data-only FCM message to a topic with automatic retry on transient errors.
 */
export async function sendFcmMessage(projectId, token, topic, data, fetchImpl = fetch) {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const body = {
    message: {
      topic,
      data: {
        nid: data.nid,
        type: data.type || 'announcements',
        lang: data.lang || 'ar',
        title: data.title,
        body: data.body,
        link: data.link,
        eventKey: data.eventKey || '',
        sentAt: data.sentAt,
        ttl: '86400s',
        urgency: 'high',
      },
      android: {
        priority: 'high',
      },
    },
  };

  let attempts = 0;
  const maxAttempts = 3;

  while (attempts < maxAttempts) {
    attempts++;
    try {
      const res = await fetchImpl(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      if (res.ok) {
        const json = await res.json().catch(() => ({}));
        if (json.name) {
          return { status: 'ok', name: json.name };
        }
        return { status: 'unconfirmed' };
      }

      const status = res.status;
      const isTransient = status === 429 || (status >= 500 && status < 600);
      if (isTransient && attempts < maxAttempts) {
        // Simple backoff
        await new Promise((resolve) => setTimeout(resolve, attempts * 300));
        continue;
      }

      const errText = await res.text().catch(() => '');
      let code = `http_${status}`;
      try {
        const errJson = JSON.parse(errText);
        code = errJson?.error?.status || errJson?.error?.message || code;
      } catch {}

      if (isTransient) {
        return { status: `retry:${attempts}:${code}` };
      }
      return { status: `error:${code}` };
    } catch (netErr) {
      if (attempts < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, attempts * 300));
        continue;
      }
      return { status: `error:network_${netErr?.message || 'unknown'}` };
    }
  }

  return { status: 'retry:3:exhausted' };
}

/**
 * Core push sender orchestrator.
 *
 * @param {object} env Environment variables / Cloudflare Worker bindings.
 * @param {object} [options={}] Optional overrides (for testing and CLI runs).
 * @param {typeof fetch} [options.fetchImpl] Custom fetch function.
 * @param {Date} [options.now] Custom current time.
 * @param {boolean} [options.dryRun=false] Run without sending or mutating Firestore.
 * @param {string} [options.topicOverride=''] Test topic override (must start with 'test_').
 * @param {Function} [options.mintToken] Custom token minter.
 * @returns {Promise<object>} Summary of the run.
 */
export async function runPushSender(env, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const now = options.now || new Date();
  const nowMs = now.getTime();
  const nowIso = now.toISOString();

  const sentryUrl = env.SENTRY_CRONS_URL || options.sentryCronsUrl;
  await sentryCheckIn(sentryUrl, 'in_progress', fetchImpl);

  let rawSa = env.FIREBASE_SERVICE_ACCOUNT || options.serviceAccount;
  if (!rawSa && typeof process !== 'undefined' && process.env) {
    rawSa = process.env.FIREBASE_SERVICE_ACCOUNT;
  }
  if (!rawSa) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is required');
  }

  const sa = typeof rawSa === 'string' ? JSON.parse(rawSa) : rawSa;
  const projectId = env.FIREBASE_PROJECT_ID || sa.project_id || 'asafra-church-portal';

  // Guard: topicOverride must start with 'test_'
  const topicOverride = (options.topicOverride || '').trim();
  if (topicOverride && !topicOverride.startsWith('test_')) {
    throw new Error(`topic_override must start with 'test_': got '${topicOverride}'`);
  }

  // Force dry-run on schedule mutations when testing with topicOverride
  const dryRun = options.dryRun || (topicOverride.length > 0);

  // Mint access token
  let token = 'test-token';
  if (options.mintToken) {
    token = await options.mintToken(sa, fetchImpl, nowMs);
  } else {
    const { mintAccessToken } = await import('./firestore_rest.js');
    token = await mintAccessToken(sa, fetchImpl, nowMs);
  }

  // 1 HTTP subrequest reads both settings docs (2 document reads consumed)
  const docs = await batchGetDocs(
    projectId,
    token,
    ['settings/features', 'settings/notifications'],
    fetchImpl,
  );

  const features = docs.get('settings/features')?.data || {};
  const notifications = docs.get('settings/notifications')?.data || {};
  let notifUpdateTime = docs.get('settings/notifications')?.updateTime || null;

  // Master switch check
  if (features.push !== true) {
    // Stamp lastRunAt if health exists
    const health = notifications.health || {};
    if (!dryRun) {
      await patchDoc(
        projectId,
        token,
        'settings/notifications',
        { health: { ...health, lastRunAt: nowIso } },
        ['health.lastRunAt'],
        null,
        fetchImpl,
      ).catch(() => {});
    }
    await sentryCheckIn(sentryUrl, 'ok', fetchImpl);
    return { status: 'skipped', reason: 'push_disabled' };
  }

  const rawSchedule = Array.isArray(notifications.schedule) ? notifications.schedule : [];
  const scheduleRows = rawSchedule.map(parseScheduleRow).filter(Boolean);
  const statusMap = { ...(notifications.status || {}) };
  let sentLog = Array.isArray(notifications.sentLog) ? [...notifications.sentLog] : [];
  const health = { ...(notifications.health || {}) };

  // Prune orphaned status keys
  const validIds = new Set(scheduleRows.map((r) => r.id));
  for (const k of Object.keys(statusMap)) {
    if (!validIds.has(k)) {
      delete statusMap[k];
    }
  }

  // Find due rows
  let fcmSendsCount = 0;
  const dueRows = [];

  for (const row of scheduleRows) {
    const rowStatus = statusMap[row.id] || {};
    const currentState = rowStatus.state || 'scheduled';

    if (currentState === 'ok') continue;

    // Check expiry (> 24 hours past atUtc)
    const isExpired = nowMs - row.atUtc.getTime() > EXPIRE_WINDOW_MS;
    if (isExpired) {
      if (currentState !== 'expired') {
        statusMap[row.id] = {
          ...rowStatus,
          state: 'expired',
          result: 'expired',
        };
      }
      continue;
    }

    // Check if due now
    if (row.atUtc.getTime() <= nowMs) {
      // If currently claiming/sending, check stale timeout
      if (currentState === 'sending') {
        const claimedAt = rowStatus.claimedAt ? new Date(rowStatus.claimedAt).getTime() : 0;
        if (nowMs - claimedAt <= CLAIM_STALE_MS) {
          // Fresh claim in progress, skip
          continue;
        }
      }

      // Calculate required topics
      const neededTopics = [];
      const isAll = row.targets === 'all';
      const isWeb = isAll || row.targets === 'web';
      const isApp = isAll || row.targets === 'app';

      const candidateTopics = [];
      if (isApp) candidateTopics.push('app_announcements_ar', 'app_announcements_en');
      if (isWeb) candidateTopics.push('web_announcements_ar', 'web_announcements_en');

      const currentTopics = rowStatus.topics || {};
      for (const t of candidateTopics) {
        if (currentTopics[t] !== 'ok') {
          neededTopics.push(t);
        }
      }

      if (neededTopics.length > 0) {
        if (fcmSendsCount + neededTopics.length <= MAX_FCM_SENDS_PER_RUN) {
          dueRows.push({ row, neededTopics });
          fcmSendsCount += neededTopics.length;
        }
      }
    }
  }

  let claimConflict = false;

  // Claim due rows atomically
  if (dueRows.length > 0 && !dryRun) {
    for (const { row } of dueRows) {
      statusMap[row.id] = {
        ...(statusMap[row.id] || {}),
        state: 'sending',
        claimedAt: nowIso,
      };
    }

    try {
      const patchRes = await patchDoc(
        projectId,
        token,
        'settings/notifications',
        { status: statusMap },
        ['status'],
        notifUpdateTime,
        fetchImpl,
      );
      notifUpdateTime = patchRes.updateTime;
    } catch (err) {
      if (err.isConflict) {
        claimConflict = true;
      } else {
        throw err;
      }
    }
  }

  const resultsSummary = {
    sentRows: 0,
    fcmSends: 0,
    dailySeasonsSent: 0,
    claimConflict,
  };

  if (!claimConflict) {
    // Send due event pushes
    for (const { row, neededTopics } of dueRows) {
      const rowStatus = statusMap[row.id] || {};
      const topicsState = { ...(rowStatus.topics || {}) };

      for (const t of neededTopics) {
        const lang = t.endsWith('_en') ? 'en' : 'ar';
        const title = lang === 'en' && row.titleEn ? row.titleEn : row.titleAr;
        const body = lang === 'en' && row.bodyEn ? row.bodyEn : row.bodyAr;

        const effectiveTopic = topicOverride || t;

        let res = { status: 'dry_run' };
        if (!dryRun) {
          res = await sendFcmMessage(
            projectId,
            token,
            effectiveTopic,
            {
              nid: row.id,
              type: 'announcements',
              lang,
              title,
              body,
              link: row.link,
              eventKey: row.eventKey,
              sentAt: nowIso,
            },
            fetchImpl,
          );
        }

        topicsState[t] = res.status;
        resultsSummary.fcmSends++;
      }

      // Evaluate new state of this row
      const allCandidate = [];
      const isAll = row.targets === 'all';
      if (isAll || row.targets === 'app') allCandidate.push('app_announcements_ar', 'app_announcements_en');
      if (isAll || row.targets === 'web') allCandidate.push('web_announcements_ar', 'web_announcements_en');

      const allOk = allCandidate.every((t) => topicsState[t] === 'ok');
      const anyOk = allCandidate.some((t) => topicsState[t] === 'ok');
      const anyUnconfirmed = allCandidate.some((t) => topicsState[t] === 'unconfirmed');

      let newState = 'ok';
      if (allOk) {
        newState = 'ok';
      } else if (anyOk) {
        newState = 'partial';
      } else if (anyUnconfirmed) {
        newState = 'unconfirmed';
      } else {
        newState = 'error';
      }

      statusMap[row.id] = {
        state: newState,
        result: newState,
        claimedAt: nowIso,
        topics: topicsState,
      };

      // Record in sentLog
      const logEntry = `${row.id}\x1f${nowIso}\x1f${newState}\x1f${row.titleAr}\x1f${options.trigger || 'cron'}`;
      sentLog.unshift(logEntry);
      resultsSummary.sentRows++;
    }

    // Evaluate once-daily seasons alerts
    const seasonsRes = await runDailySeasons(
      projectId,
      token,
      features,
      health,
      sentLog,
      fetchImpl,
      now,
    );

    if (seasonsRes.lastSeasonDate) {
      health.lastSeasonDate = seasonsRes.lastSeasonDate;
    }

    for (const alert of seasonsRes.alerts) {
      // 4 topics per season alert
      const seasonTopics = ['app_seasons_ar', 'app_seasons_en', 'web_seasons_ar', 'web_seasons_en'];
      let anyFailed = false;

      for (const st of seasonTopics) {
        if (resultsSummary.fcmSends >= MAX_FCM_SENDS_PER_RUN) break;

        const lang = st.endsWith('_en') ? 'en' : 'ar';
        const title = lang === 'en' ? alert.titleEn : alert.titleAr;
        const body = lang === 'en' ? alert.bodyEn : alert.bodyAr;
        const effectiveTopic = topicOverride || st;

        if (!dryRun) {
          const res = await sendFcmMessage(
            projectId,
            token,
            effectiveTopic,
            {
              nid: alert.nid,
              type: 'seasons',
              lang,
              title,
              body,
              link: alert.link,
              eventKey: alert.eventKey,
              sentAt: nowIso,
            },
            fetchImpl,
          );
          if (res.status !== 'ok') anyFailed = true;
        }
        resultsSummary.fcmSends++;
      }

      const alertResult = anyFailed ? 'partial' : 'ok';
      const logEntry = `${alert.logKey}\x1f${nowIso}\x1f${alertResult}\x1f${alert.titleAr}\x1f${options.trigger || 'cron'}`;
      sentLog.unshift(logEntry);
      resultsSummary.dailySeasonsSent++;
    }

    // Cap sentLog at MAX_SENT_LOG_SIZE (30 items)
    if (sentLog.length > MAX_SENT_LOG_SIZE) {
      sentLog = sentLog.slice(0, MAX_SENT_LOG_SIZE);
    }

    health.lastRunAt = nowIso;
    health.lastError = null;

    // Final state write
    if (!dryRun) {
      await patchDoc(
        projectId,
        token,
        'settings/notifications',
        {
          status: statusMap,
          sentLog,
          health,
        },
        ['status', 'sentLog', 'health'],
        null, // unconditional final write of status/sentLog/health
        fetchImpl,
      );
    }
  }

  await sentryCheckIn(sentryUrl, 'ok', fetchImpl);
  return { status: 'success', summary: resultsSummary };
}

// CLI execution (Node.js 22+)
if (
  typeof process !== 'undefined' &&
  process.argv &&
  process.argv[1] &&
  process.argv[1].endsWith('push_sender.js')
) {
  const isDryRun = process.argv.includes('--dry-run');
  const trigger = process.argv.includes('--manual') ? 'manual' : 'cron';
  const topicIdx = process.argv.indexOf('--topic-override');
  const topicOverride = topicIdx !== -1 && process.argv[topicIdx + 1] ? process.argv[topicIdx + 1] : '';

  runPushSender(process.env, { dryRun: isDryRun, trigger, topicOverride })
    .then((res) => {
      console.log('Push sender finished successfully:', JSON.stringify(res, null, 2));
      process.exit(0);
    })
    .catch((err) => {
      console.error('Push sender failed:', err);
      process.exit(1);
    });
}
