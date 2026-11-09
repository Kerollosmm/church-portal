// Cloudflare Worker cron-only entrypoint for push sender (ADR-059).
// Triggered every 15 minutes by Cloudflare Workers cron trigger (*/15 * * * *).
// Exposes ZERO public HTTP endpoints (no fetch handler).

import { runPushSender } from './push_sender.js';

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      runPushSender(env, { trigger: 'cron' }).catch(async (err) => {
        console.error('Push sender scheduled execution error:', err);
        if (env?.SENTRY_DSN) {
          try {
            await fetch(env.SENTRY_DSN, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                message: err?.message || String(err),
                level: 'error',
                tags: { section: 'push_worker' },
              }),
            });
          } catch (_) {}
        }
      }),
    );
  },
};
