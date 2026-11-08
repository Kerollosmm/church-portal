// Pure helpers of hw.mjs (no I/O), shared with scripts/validate.mjs so they can be unit-tested without the network.

/** Newest rate-limit message of a review bot and when it is safe to ask again. Pure: tested by scripts/validate.mjs. */
export function botWait({ comments, reviews = [], bot = 'coderabbitai', now = Date.now() }) {
  const isBot = (u) => String(u?.login || '').toLowerCase().startsWith(bot);
  const text = (b) => String(b || '').replace(/<!--[\s\S]*?-->/g, ' ').replace(/<[^>]+>/g, ' ').replace(/[*_`]/g, '').replace(/\s+/g, ' ');
  // Strict: the bot's own limit notices only ("Rate Limit Exceeded", "Review rate limited"), not review text that
  // happens to contain the words "rate limit".
  const limited = (b) => /(rate limit exceeded|review rate.?limited|rate.?limited\b|exceeded the limit for the number of)/i.test(text(b).slice(0, 600));
  const mine = comments.filter((x) => isBot(x.user));
  const rl = mine.filter((x) => limited(x.body)).sort((a, b) => Date.parse(a.updated_at || a.created_at) - Date.parse(b.updated_at || b.created_at));
  if (!rl.length) return { state: 'none', reason: `no rate-limit message from ${bot}` };
  const last = rl[rl.length - 1];
  const at = Date.parse(last.updated_at || last.created_at);
  const later = [...mine.filter((x) => !limited(x.body)).map((x) => x.created_at), ...reviews.filter((x) => isBot(x.user)).map((x) => x.submitted_at)]
    .some((t) => t && Date.parse(t) > at);
  if (later) return { state: 'none', reason: `${bot} reviewed or commented after its last rate-limit message` };
  const body = text(last.body);
  const snippet = ((body.match(/wait[^.!?]*/i) || [])[0] || '').trim().slice(0, 160);
  let ms = 0;
  for (const [re, f] of [[/(\d+)\s*hours?/i, 3600e3], [/(\d+)\s*minutes?/i, 60e3], [/(\d+)\s*seconds?/i, 1e3]]) { const m = snippet.match(re); if (m) ms += Number(m[1]) * f; }
  const assumed = ms === 0; if (assumed) ms = 3600e3;
  const ready = at + ms + 60e3;
  const kind = /chat messages/i.test(body) ? 'chat' : 'review';
  return { state: now >= ready ? 'ready' : 'wait', at, ready, snippet, assumed, kind, count: rl.length, url: last.html_url };
}
/** First Firebase channel URL (site--channel-hash.web.app) in a text; prefers lines that mention "channel". */
export function pickChannelUrl(text, channel) {
  const all = /https?:\/\/[A-Za-z0-9-]+--[A-Za-z0-9-]+\.web\.app\/?/g;
  const lines = String(text || '').split(/\r?\n/).filter((l) => /--[A-Za-z0-9-]+\.web\.app/.test(l));
  const ok = (u) => !channel || u.includes(`--${channel}-`);
  for (const l of [...lines.filter((x) => /channel/i.test(x)), ...lines]) {
    for (const u of l.match(all) || []) {
      if (ok(u)) return { url: u.replace(/\/$/, ''), expires: (l.match(/expires?\s*:?\s*([0-9][0-9T:.\-]+Z?)/i) || [])[1] || '' };
    }
  }
  return { url: '', expires: '' };
}
