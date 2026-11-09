// Cloudflare Worker cron-only entrypoint for push sender (ADR-059, ADR-060).
// 3 dedicated cron triggers (zero public HTTP endpoints):
// 1. Delivery Cron: */15 * * * * (runs push_sender.js)
// 2. Queue Drain Cron: 7,22,37,52 * * * * (runs push_queue.js)
// 3. Reminder Planner Cron: 3 2,8,14,20 * * * (runs push_reminders.js)

import { runPushSender } from './push_sender.js';
import { runPushQueueDrain } from './push_queue.js';
import { runPushReminderPlanner } from './push_reminders.js';

export default {
  async scheduled(event, env, ctx) {
    const cron = event.cron;
    let runner;
    let section = 'push_worker';

    if (cron === '7,22,37,52 * * * *') {
      runner = runPushQueueDrain(env, ctx);
      section = 'push_queue_drain';
    } else if (cron === '3 2,8,14,20 * * *') {
      runner = runPushReminderPlanner(env, ctx);
      section = 'push_reminder_planner';
    } else {
      // Default to delivery sender: */15 * * * *
      runner = runPushSender(env, { trigger: 'cron' });
      section = 'push_sender';
    }

    ctx.waitUntil(
      runner.catch(async (err) => {
        console.error(`${section} scheduled execution error:`, err);
        if (env?.SENTRY_DSN) {
          try {
            await fetch(env.SENTRY_DSN, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                message: err?.message || String(err),
                level: 'error',
                tags: { section },
              }),
            });
          } catch (_) {}
        }
      }),
    );
  },
};

