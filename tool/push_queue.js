// Cloudflare Worker cron-only Queue Drain (ADR-060).
// Triggered every 15 minutes at minutes 7, 22, 37, 52 (7,22,37,52 * * * *).
// Drains push_queue, calls Google IID REST for topic subscriptions,
// and acts as the SOLE WRITER of meta/push_topics.

import {
  batchGetDocs,
  commitWrites,
  getCachedAccessToken,
  queryCollection,
  setDocRest,
} from './firestore_rest.js';

export const QUEUE_QUERY_LIMIT = 60;
export const MAX_IID_CALLS_PER_RUN = 20;
export const MAX_RETRY_COUNT = 30;
export const POISON_AGE_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

export const FIXED_TOPICS = [
  'web_announcements_ar',
  'web_announcements_en',
  'web_seasons_ar',
  'web_seasons_en',
];

export function getUtcDayInt(d = new Date()) {
  return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
}

/**
 * Executes Google IID batch topic subscription / unsubscription.
 *
 * @param {string} op 'batchAdd' or 'batchRemove'
 * @param {string} topic Topic name without '/topics/' prefix
 * @param {string[]} tokens Registration tokens
 * @param {string} accessToken Bearer access token
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation
 * @returns {Promise<Array<{ error?: string }>>} Array of per-token results
 */
export async function callIidTopic(op, topic, tokens, accessToken, fetchImpl = fetch) {
  if (!tokens || tokens.length === 0) return [];
  const url = `https://iid.googleapis.com/iid/v1:${op}`;

  const res = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      access_token_auth: 'true',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: `/topics/${topic}`,
      registration_tokens: tokens,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    const isTransient = res.status >= 500 || res.status === 429;
    const err = new Error(`IID ${op} failed on ${topic} (${res.status}): ${text}`);
    err.status = res.status;
    err.isTransient = isTransient;
    throw err;
  }

  const json = await res.json().catch(() => ({}));
  return json.results || tokens.map(() => ({}));
}

/**
 * Checks if an IID error string represents a permanent token error.
 */
export function isPermanentIidError(errStr) {
  if (!errStr || typeof errStr !== 'string') return false;
  const s = errStr.toUpperCase();
  return (
    s.includes('INVALID_ARGUMENT') ||
    s.includes('INVALID_REGISTRATION_TOKEN') ||
    s.includes('NOT_REGISTERED') ||
    s.includes('BAD_REQUEST')
  );
}

/**
 * Runs the push queue drain job.
 *
 * @param {object} env Cloudflare Worker environment.
 * @param {object} [options={}] Optional test parameters.
 * @returns {Promise<object>} Summary of the drain run.
 */
export async function runPushQueueDrain(env, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const now = options.now || new Date();
  const nowMs = now.getTime();
  const nowIso = now.toISOString();
  const todayUtcInt = getUtcDayInt(now);

  let rawSa = env.FIREBASE_SERVICE_ACCOUNT || options.serviceAccount;
  if (!rawSa && typeof process !== 'undefined' && process.env) {
    rawSa = process.env.FIREBASE_SERVICE_ACCOUNT;
  }
  if (!rawSa) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is required');
  }

  const sa = typeof rawSa === 'string' ? JSON.parse(rawSa) : rawSa;
  const projectId = env.FIREBASE_PROJECT_ID || sa.project_id || 'asafra-church-portal';

  // Mint / retrieve cached access token
  let token = 'test-token';
  if (options.mintToken) {
    token = await options.mintToken(sa, fetchImpl, nowMs);
  } else {
    token = await getCachedAccessToken(sa, env, fetchImpl, nowMs);
  }

  // 1. Query push_queue docs ordered by createdAt ASC, limit 60
  const query = {
    from: [{ collectionId: 'push_queue' }],
    orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'ASCENDING' }],
    limit: QUEUE_QUERY_LIMIT,
  };

  const queueDocs = await queryCollection(projectId, token, query, fetchImpl);

  // If queue is empty, exit immediately with 0 batchGet calls on meta/*
  if (!queueDocs || queueDocs.length === 0) {
    return {
      status: 'idle',
      processed: 0,
      failed: 0,
      deleted: 0,
    };
  }

  // 2. Fetch metadata docs (meta/push_topics and meta/push_rate) in one batchGet
  const metaDocs = await batchGetDocs(
    projectId,
    token,
    ['meta/push_topics', 'meta/push_rate'],
    fetchImpl,
  );

  const topicsDoc = metaDocs.get('meta/push_topics')?.data || {};
  const rateDoc = metaDocs.get('meta/push_rate')?.data || {};

  const existingTopics = { ...(topicsDoc.topics || {}) };
  const retryCounts = { ...(topicsDoc.retryCounts || {}) };
  const cronQueue = { ...(topicsDoc.cronQueue || {}) };

  // Pre-roll meta/push_rate after 00:00 UTC if rateDoc.day is older than today
  const rateDay = typeof rateDoc.day === 'number' ? rateDoc.day : todayUtcInt;
  const rateCount = typeof rateDoc.count === 'number' ? rateDoc.count : 0;
  if (rateDoc.day && rateDoc.day < todayUtcInt) {
    await setDocRest(
      projectId,
      token,
      'meta/push_rate',
      {
        day: todayUtcInt,
        count: 0,
        lastAt: nowIso,
        lastId: `preroll${todayUtcInt}`,
      },
      fetchImpl,
    ).catch(() => {});
  }

  cronQueue.rateDay = rateDay;
  cronQueue.rateCount = rateCount;
  cronQueue.capReached = rateCount >= 1000;

  const docsToDelete = new Set();
  let queueProcessedCount = cronQueue.queueProcessedCount || 0;
  let queueFailedCount = cronQueue.queueFailedCount || 0;
  let lastIidError = null;

  // 3. Inspect queue docs for poison / age eviction
  const validDocs = [];
  for (const qd of queueDocs) {
    const data = qd.data || {};
    const createdDate = data.createdAt ? new Date(data.createdAt).getTime() : nowMs;
    const isTooOld = nowMs - createdDate > POISON_AGE_MS;
    const currentRetries = retryCounts[qd.id] || 0;

    if (isTooOld || currentRetries >= MAX_RETRY_COUNT) {
      docsToDelete.add(qd.id);
      delete retryCounts[qd.id];
      queueFailedCount++;
      continue;
    }
    validDocs.push(qd);
  }

  // 4. Group valid docs by token
  const tokenGroups = new Map();
  for (const qd of validDocs) {
    const data = qd.data || {};
    const tok = (data.token || '').trim();
    if (!tok) {
      docsToDelete.add(qd.id);
      continue;
    }

    if (!tokenGroups.has(tok)) {
      tokenGroups.set(tok, []);
    }
    tokenGroups.get(tok).push(qd);
  }

  // 5. Build topic diffs per token and aggregate into batch IID calls
  // Map of topic -> Set of tokens to add
  const addMap = new Map();
  // Map of topic -> Set of tokens to remove
  const removeMap = new Map();
  // Map of docId -> Array of topic check keys to mark doc success
  const tokenDocsMap = new Map();

  for (const [tok, docs] of tokenGroups.entries()) {
    // Sort docs by createdAt ASC so newest is last
    docs.sort((a, b) => {
      const ta = a.data?.createdAt ? new Date(a.data.createdAt).getTime() : 0;
      const tb = b.data?.createdAt ? new Date(b.data.createdAt).getTime() : 0;
      return ta - tb;
    });

    const newestDoc = docs[docs.length - 1];
    const wantSet = new Set(Array.isArray(newestDoc.data?.want) ? newestDoc.data.want : []);

    // Union rem and drop across all docs for this token
    const remTopics = new Set();
    const dropTopics = new Set();
    const prevTokens = new Set();

    for (const d of docs) {
      const data = d.data || {};
      if (typeof data.rem === 'string' && data.rem.trim()) {
        for (const t of data.rem.split(',')) {
          const s = t.trim();
          if (s) remTopics.add(s);
        }
      }
      if (typeof data.drop === 'string' && data.drop.trim()) {
        for (const t of data.drop.split(',')) {
          const s = t.trim();
          if (s) dropTopics.add(s);
        }
      }
      if (typeof data.prevToken === 'string' && data.prevToken.trim()) {
        prevTokens.add(data.prevToken.trim());
      }
    }

    // Subscribe to want fixed topics
    for (const t of FIXED_TOPICS) {
      if (wantSet.has(t)) {
        if (!addMap.has(t)) addMap.set(t, new Set());
        addMap.get(t).add(tok);
      } else {
        if (!removeMap.has(t)) removeMap.set(t, new Set());
        removeMap.get(t).add(tok);
      }
    }

    // Subscribe to rem topics
    for (const t of remTopics) {
      if (!addMap.has(t)) addMap.set(t, new Set());
      addMap.get(t).add(tok);
    }

    // Unsubscribe from drop topics
    for (const t of dropTopics) {
      if (!removeMap.has(t)) removeMap.set(t, new Set());
      removeMap.get(t).add(tok);
    }

    // Unsubscribe prevToken from fixed topics and all rem topics
    for (const pt of prevTokens) {
      for (const t of FIXED_TOPICS) {
        if (!removeMap.has(t)) removeMap.set(t, new Set());
        removeMap.get(t).add(pt);
      }
      for (const t of remTopics) {
        if (!removeMap.has(t)) removeMap.set(t, new Set());
        removeMap.get(t).add(pt);
      }
    }

    tokenDocsMap.set(tok, docs);
  }

  // 6. Execute IID calls, capped at MAX_IID_CALLS_PER_RUN (20)
  let iidCallCount = 0;
  const tokenFailedTransient = new Set();
  const tokenPermanentFailed = new Set();

  const addEntries = Array.from(addMap.entries());
  const removeEntries = Array.from(removeMap.entries());
  const allOps = [
    ...addEntries.map(([topic, tokens]) => ({ op: 'batchAdd', topic, tokens: Array.from(tokens) })),
    ...removeEntries.map(([topic, tokens]) => ({ op: 'batchRemove', topic, tokens: Array.from(tokens) })),
  ];

  for (const { op, topic, tokens } of allOps) {
    if (iidCallCount >= MAX_IID_CALLS_PER_RUN) {
      // Remaining topic operations roll over to next run
      for (const t of tokens) {
        tokenFailedTransient.add(t);
      }
      continue;
    }

    iidCallCount++;
    try {
      const results = await callIidTopic(op, topic, tokens, token, fetchImpl);
      for (let i = 0; i < tokens.length; i++) {
        const tok = tokens[i];
        const res = results[i] || {};
        if (res.error) {
          lastIidError = `${op}:${topic}:${res.error}`;
          if (isPermanentIidError(res.error)) {
            tokenPermanentFailed.add(tok);
          } else {
            tokenFailedTransient.add(tok);
          }
        } else {
          // Success: update active topics presence map
          if (op === 'batchAdd') {
            existingTopics[topic] = true;
          }
        }
      }
    } catch (err) {
      lastIidError = `${op}:${topic}:${err.message || String(err)}`;
      for (const t of tokens) {
        if (err.isTransient) {
          tokenFailedTransient.add(t);
        } else {
          tokenPermanentFailed.add(t);
        }
      }
    }
  }

  // 7. Decide doc deletion vs retry for each token group
  for (const [tok, docs] of tokenGroups.entries()) {
    if (tokenPermanentFailed.has(tok)) {
      // Permanent error -> token invalid/unregistered, evict all its docs
      for (const d of docs) {
        docsToDelete.add(d.id);
        delete retryCounts[d.id];
      }
      queueFailedCount += docs.length;
    } else if (tokenFailedTransient.has(tok)) {
      // Transient error -> increment retry count, keep doc for next run
      for (const d of docs) {
        const c = (retryCounts[d.id] || 0) + 1;
        retryCounts[d.id] = c;
        if (c >= MAX_RETRY_COUNT) {
          docsToDelete.add(d.id);
          delete retryCounts[d.id];
          queueFailedCount++;
        }
      }
    } else {
      // Complete success -> delete docs
      for (const d of docs) {
        docsToDelete.add(d.id);
        delete retryCounts[d.id];
        queueProcessedCount++;
      }
    }
  }

  // 8. Update meta/push_topics as sole writer
  cronQueue.lastDrainAt = nowIso;
  cronQueue.queueProcessedCount = queueProcessedCount;
  cronQueue.queueFailedCount = queueFailedCount;
  cronQueue.lastIidError = lastIidError;

  await setDocRest(
    projectId,
    token,
    'meta/push_topics',
    {
      topics: existingTopics,
      retryCounts,
      cronQueue,
    },
    fetchImpl,
  ).catch((err) => {
    console.error('Failed to update meta/push_topics:', err);
  });

  // 9. Batch delete completed/evicted queue docs in 1 commitWrites subrequest
  const deleteList = Array.from(docsToDelete);
  if (deleteList.length > 0) {
    const writes = deleteList.map((id) => ({
      delete: `projects/${projectId}/databases/(default)/documents/push_queue/${id}`,
    }));
    await commitWrites(projectId, token, writes, fetchImpl).catch((err) => {
      console.error('Failed to batch-delete push_queue docs:', err);
    });
  }

  return {
    status: 'ok',
    processed: queueProcessedCount,
    failed: queueFailedCount,
    deleted: deleteList.length,
    iidCalls: iidCallCount,
  };
}
