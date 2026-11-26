// Cloudflare Worker entrypoint for push sender & readings syncer (ADR-059, ADR-060, ADR-063)
// plus POST /assistant (Workers Free). Cron triggers:
// 1. Delivery Cron: */15 * * * * (runs push_sender.js)
// 2. Queue Drain Cron: 7,22,37,52 * * * * (runs push_queue.js)
// 3. Reminder Planner Cron: 3 2,8,14,20 * * * (runs push_reminders.js)
// 4. Daily Readings Sync Cron: 0 16 * * * (runs readings_syncer.js at 6:00 PM Cairo rollover)

import { runPushSender } from './push_sender.js';
import { runPushQueueDrain } from './push_queue.js';
import { runPushReminderPlanner } from './push_reminders.js';
import { syncDailyReadingsAndSynaxarium } from './readings_syncer.js';
import { handleAssistantRequest } from './assistant_worker.js';

function scrubSentryText(raw) {
  return String(raw || 'Unknown error')
    .replace(/-----BEGIN[ A-Z0-9_-]+PRIVATE KEY-----[\s\S]*?-----END[ A-Z0-9_-]+PRIVATE KEY-----/g, '[REDACTED_PRIVATE_KEY]')
    .replace(/Bearer\s+\S+/gi, 'Bearer [REDACTED]')
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[REDACTED_JWT]')
    .replace(/(https?:\/\/)[^:\s/@]+(?::[^@\s/]+)?@/gi, '$1[REDACTED]@')
    .slice(0, 1000);
}

/**
 * Parses a Sentry DSN into a legacy `/api/<projectId>/store/` POST request.
 * Returns `null` when DSN is empty or malformed.
 */
export function buildSentryStoreRequest(dsn, err, section = 'push_worker') {
  if (!dsn || typeof dsn !== 'string' || !dsn.trim()) return null;
  let u;
  try {
    u = new URL(dsn.trim());
  } catch (_) {
    return null;
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;

  const publicKey = (u.username || '').trim();
  const segments = u.pathname.replace(/^\/+|\/+$/g, '').split('/').filter(Boolean);
  const projectId = segments.pop() || '';
  if (!publicKey || !projectId) return null;

  const basePath = segments.length > 0 ? `/${segments.join('/')}` : '';
  const url = `${u.protocol}//${u.host}${basePath}/api/${projectId}/store/`;
  const message = scrubSentryText(err?.message || err);

  return {
    url,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Sentry-Auth': `Sentry sentry_version=7, sentry_client=cf-push-worker/1.0, sentry_key=${publicKey}`,
    },
    body: JSON.stringify({
      message,
      level: 'error',
      platform: 'javascript',
      tags: { section: section || 'push_worker' },
    }),
  };
}

export default {
  async fetch(request, env) {
    return handleAssistantRequest(request, env);
  },

  async scheduled(event, env, ctx) {
    const cron = event.cron;
    let runner;
    let section = 'push_worker';

    if (cron === '7,22,37,52 * * * *') {
      runner = runPushQueueDrain(env, {});
      section = 'push_queue_drain';
    } else if (cron === '3 2,8,14,20 * * *') {
      runner = runPushReminderPlanner(env, {});
      section = 'push_reminder_planner';
    } else if (cron === '0 16 * * *') {
      runner = syncDailyReadingsAndSynaxarium(env);
      section = 'readings_syncer';
    } else {
      // Default to delivery sender: */15 * * * *
      runner = runPushSender(env, { trigger: 'cron' });
      section = 'push_sender';
    }

    ctx.waitUntil(
      runner.catch(async (err) => {
        console.error(`${section} scheduled execution error:`, err);
        const req = buildSentryStoreRequest(env?.SENTRY_DSN, err, section);
        if (req) {
          try {
            await fetch(req.url, {
              method: req.method,
              headers: req.headers,
              body: req.body,
            });
          } catch (_) {}
        }
      }),
    );
  },
};
