// Cloudflare Worker cron-only entrypoint for push sender (ADR-059).
// Triggered every 15 minutes by Cloudflare Workers cron trigger (*/15 * * * *).
// Exposes ZERO public HTTP endpoints (no fetch handler).

import { runPushSender } from './push_sender.js';

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      runPushSender(env, { trigger: 'cron' }).catch((err) => {
        console.error('Push sender scheduled execution error:', err);
      }),
    );
  },
};
