/**
 * POST /assistant for the sideloaded Android app (Workers Free plan).
 * Web keeps Firebase AI Logic. The device daily limit stays in the app
 * (ADR-031); this only stops a modified client from draining the free
 * Gemini quota. One KV read and one KV write per accepted question, on the
 * existing PUSH_KV namespace. No Durable Objects (those need Workers Paid).
 */
export const ASSISTANT_APP_ID = 'church-portal-android';

export const ASSISTANT_LIMITS = {
  // Decoded request text. The bundled seed instruction is already ~29k chars
  // (47 liturgies, no custom pages). Live pages add up to 20 × 2,500 chars.
  // 150k covers that with margin. 512 KiB fits that instruction plus 20 turns
  // of 8,000 chars (the reply slice below). Workers Free allows ~100 MB bodies.
  maxBodyBytes: 512 * 1024,
  maxInstruction: 150000,
  maxPrompt: 1200,
  maxHistoryTurns: 20,
  /** Same as the reply slice returned below, so the next turn is accepted. */
  maxTurnChars: 8000,
  /** Shared with the push worker's KV writes (free plan: 1,000 writes/day). */
  globalPerDay: 400,
  /** Admin maximum (`perDay` max). The app still enforces the real per-day number first. */
  devicePerDay: 100,
  ipPerDay: 40,
  ipPerMinute: 20,
};

const MODEL_NAME = /^gemini-[a-z0-9][a-z0-9.-]{0,58}$/;

/** Africa/Cairo wall date `yyyymmdd`. UTC+3 from the last Friday of April through the last Thursday of October, else UTC+2. */
export function cairoDayKey(now) {
  const utc = now.getTime();
  const y = now.getUTCFullYear();
  const start = lastWeekdayUtc(y, 3, 5);
  const end = lastWeekdayUtc(y, 9, 4);
  const offsetHours = utc >= start.getTime() && utc < end.getTime() + 24 * 3600 * 1000 ? 3 : 2;
  const c = new Date(utc + offsetHours * 3600 * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${c.getUTCFullYear()}${p(c.getUTCMonth() + 1)}${p(c.getUTCDate())}`;
}

function lastWeekdayUtc(year, monthIndex, weekday) {
  const d = new Date(Date.UTC(year, monthIndex + 1, 0));
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() - weekday + 7) % 7));
  return d;
}

async function sha12(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].slice(0, 6).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

function validTurn(turn) {
  return turn && typeof turn.text === 'string' && turn.text.length <= ASSISTANT_LIMITS.maxTurnChars && typeof turn.user === 'boolean';
}

/**
 * @param {Request} request
 * @param {{ GEMINI_API_KEY?: string, PUSH_KV?: { get: Function, put: Function } }} env
 * @param {{ now?: Date, fetchImpl?: typeof fetch, ip?: string }} [opts]
 */
export async function handleAssistantRequest(request, env, opts = {}) {
  const path = new URL(request.url).pathname.replace(/\/$/, '') || '/';
  if (request.method !== 'POST' || path !== '/assistant') return json(404, { error: 'not_found' });
  if (request.headers.get('x-church-app') !== ASSISTANT_APP_ID) return json(403, { error: 'forbidden' });
  const device = request.headers.get('x-church-device') || '';
  if (!/^[0-9a-f]{32}$/.test(device)) return json(400, { error: 'bad_device' });

  const raw = await request.text();
  if (raw.length > ASSISTANT_LIMITS.maxBodyBytes) return json(413, { error: 'too_large' });
  let body;
  try {
    body = JSON.parse(raw);
  } catch (_) {
    return json(400, { error: 'bad_json' });
  }
  const model = typeof body.model === 'string' ? body.model : '';
  const instruction = typeof body.instruction === 'string' ? body.instruction : '';
  const prompt = typeof body.prompt === 'string' ? body.prompt : '';
  const history = Array.isArray(body.history) ? body.history : null;
  if (!MODEL_NAME.test(model) || !instruction || instruction.length > ASSISTANT_LIMITS.maxInstruction) {
    return json(400, { error: 'bad_request' });
  }
  if (!prompt || prompt.length > ASSISTANT_LIMITS.maxPrompt || !history || history.length > ASSISTANT_LIMITS.maxHistoryTurns || !history.every(validTurn)) {
    return json(400, { error: 'bad_request' });
  }
  if (!env.GEMINI_API_KEY) return json(503, { error: 'unconfigured' });
  if (!env.PUSH_KV) return json(503, { error: 'unconfigured' });

  const now = opts.now || new Date();
  const day = cairoDayKey(now);
  const ip = opts.ip || request.headers.get('cf-connecting-ip') || '0';
  const ipKey = await sha12(`${day}:${ip}`);
  const minute = Math.floor(now.getTime() / 60000);
  const key = `asst:${day}`;
  const stored = await env.PUSH_KV.get(key);
  let bucket = { n: 0, d: {}, i: {}, m: {} };
  if (stored) {
    try {
      bucket = JSON.parse(stored);
    } catch (_) {
      bucket = { n: 0, d: {}, i: {}, m: {} };
    }
  }
  bucket.d ||= {};
  bucket.i ||= {};
  bucket.m ||= {};
  const deviceCount = bucket.d[device] || 0;
  const ipCount = bucket.i[ipKey] || 0;
  const minuteBucket = bucket.m[ipKey];
  const minuteCount = minuteBucket && minuteBucket.t === minute ? minuteBucket.n : 0;
  if (bucket.n >= ASSISTANT_LIMITS.globalPerDay) return json(429, { error: 'global_cap' });
  if (deviceCount >= ASSISTANT_LIMITS.devicePerDay) return json(429, { error: 'device_cap' });
  if (ipCount >= ASSISTANT_LIMITS.ipPerDay || minuteCount >= ASSISTANT_LIMITS.ipPerMinute) {
    return json(429, { error: 'ip_cap' });
  }
  bucket.n += 1;
  bucket.d[device] = deviceCount + 1;
  bucket.i[ipKey] = ipCount + 1;
  bucket.m = { [ipKey]: { t: minute, n: minuteCount + 1 } };
  await env.PUSH_KV.put(key, JSON.stringify(bucket), { expirationTtl: 60 * 60 * 48 });

  const contents = [
    ...history.map((t) => ({ role: t.user ? 'user' : 'model', parts: [{ text: t.text }] })),
    { role: 'user', parts: [{ text: prompt }] },
  ];
  const fetchImpl = opts.fetchImpl || fetch;
  let gemini;
  try {
    gemini = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: instruction }] },
        contents,
        generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
      }),
    },
    );
  } catch (_) {
    return json(502, { error: 'model' });
  }
  if (!gemini.ok) return json(gemini.status === 429 ? 429 : 502, { error: 'model' });
  let data;
  try {
    data = await gemini.json();
  } catch (_) {
    return json(502, { error: 'model' });
  }
  const text = (data.candidates?.[0]?.content?.parts || []).map((p) => p.text || '').join('').trim().slice(0, 8000);
  if (!text) return json(502, { error: 'empty' });
  return json(200, { text });
}
