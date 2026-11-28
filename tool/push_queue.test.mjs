// Unit tests for push_queue.js (Node 22+).
// Runs via: node --test tool/push_queue.test.mjs

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  FIXED_TOPICS,
  MAX_IID_CALLS_PER_RUN,
  MAX_RETRY_COUNT,
  POISON_AGE_MS,
  QUEUE_QUERY_LIMIT,
  getUtcDayInt,
  isPermanentIidError,
  runPushQueueDrain,
} from './push_queue.js';

describe('push_queue constants and helpers', () => {
  test('constants match ADR-060 architecture lock', () => {
    assert.equal(QUEUE_QUERY_LIMIT, 60);
    assert.equal(MAX_IID_CALLS_PER_RUN, 20);
    assert.equal(MAX_RETRY_COUNT, 30);
    assert.equal(POISON_AGE_MS, 7 * 86400 * 1000);
    assert.equal(FIXED_TOPICS.length, 4);
  });

  test('getUtcDayInt returns integer YYYYMMDD', () => {
    const d = new Date('2026-11-15T10:00:00Z');
    assert.equal(getUtcDayInt(d), 20261115);
  });

  test('isPermanentIidError distinguishes permanent vs transient errors', () => {
    assert.ok(isPermanentIidError('INVALID_ARGUMENT'));
    assert.ok(isPermanentIidError('INVALID_REGISTRATION_TOKEN'));
    assert.ok(isPermanentIidError('NOT_REGISTERED'));
    assert.ok(isPermanentIidError('BAD_REQUEST'));
    assert.equal(isPermanentIidError('INTERNAL_ERROR'), false);
    assert.equal(isPermanentIidError('SERVER_UNAVAILABLE'), false);
    assert.equal(isPermanentIidError(null), false);
  });
});

describe('runPushQueueDrain workflow', () => {
  const mockSa = {
    client_email: 'test@serviceaccount.com',
    project_id: 'test-project',
    private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC3\n-----END PRIVATE KEY-----',
  };

  test('exits early with status idle when queue is empty (zero meta reads)', async () => {
    let queryCalled = false;
    let batchGetCalled = false;

    const fakeFetch = async (url, options) => {
      if (url.includes(':runQuery')) {
        queryCalled = true;
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes(':batchGet')) {
        batchGetCalled = true;
        return new Response(JSON.stringify([]), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushQueueDrain(
      {},
      {
        serviceAccount: mockSa,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'idle');
    assert.ok(queryCalled, 'should have queried the queue');
    assert.equal(batchGetCalled, false, 'must not call batchGet on meta/* when queue is empty');
  });

  test('patches cronQueue.lastDrainAt and cronQueue.lastIdleAt via updateMask on idle with zero batchGet calls', async () => {
    const now = new Date('2026-11-15T12:15:00Z');
    let batchGetCalled = false;
    const patchCalls = [];

    const fakeFetch = async (url, options = {}) => {
      if (url.includes(':runQuery')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes(':batchGet')) {
        batchGetCalled = true;
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('meta/push_topics')) {
        patchCalls.push({
          url,
          method: options.method,
          body: JSON.parse(options.body),
        });
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushQueueDrain(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.deepEqual(res, { status: 'idle', processed: 0, failed: 0, deleted: 0 });
    assert.equal(batchGetCalled, false);
    assert.equal(patchCalls.length, 1);
    assert.equal(patchCalls[0].method, 'PATCH');
    const parsedUrl = new URL(patchCalls[0].url);
    assert.deepEqual(parsedUrl.searchParams.getAll('updateMask.fieldPaths'), [
      'cronQueue.lastDrainAt',
      'cronQueue.lastIdleAt',
    ]);
    const cronQueueFields = patchCalls[0].body.fields.cronQueue.mapValue.fields;
    assert.equal(cronQueueFields.lastDrainAt.stringValue, now.toISOString());
    assert.equal(cronQueueFields.lastIdleAt.stringValue, now.toISOString());
  });

  test('rethrows write failure when patching meta/push_topics on idle returns HTTP 500', async () => {
    const now = new Date('2026-11-15T12:15:00Z');
    const fakeFetch = async (url) => {
      if (url.includes(':runQuery')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('meta/push_topics')) {
        return new Response('Internal Error', { status: 500 });
      }
      return new Response('{}', { status: 200 });
    };

    await assert.rejects(
      () =>
        runPushQueueDrain(
          {},
          {
            serviceAccount: mockSa,
            now,
            mintToken: async () => 'test-token',
            fetchImpl: fakeFetch,
          },
        ),
      /500/,
    );
  });

  test('deletes processed/evicted queue docs before rethrowing setDocRest HTTP 500 on meta/push_topics', async () => {
    const now = new Date('2026-11-15T12:00:00Z');
    const oldCreated = new Date('2026-11-01T12:00:00Z').toISOString();
    let committedWrites = [];

    const fakeFetch = async (url, options = {}) => {
      if (url.includes(':runQuery')) {
        return new Response(
          JSON.stringify([
            {
              document: {
                name: 'projects/test-project/databases/(default)/documents/push_queue/docOld',
                fields: {
                  token: { stringValue: 'tokenA'.repeat(20) },
                  createdAt: { stringValue: oldCreated },
                },
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes(':batchGet')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('meta/push_topics')) {
        return new Response('Internal Error', { status: 500 });
      }
      if (url.includes(':commit')) {
        committedWrites = JSON.parse(options.body).writes;
        return new Response(JSON.stringify({ writeResults: [{}] }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    await assert.rejects(
      () =>
        runPushQueueDrain(
          {},
          {
            serviceAccount: mockSa,
            now,
            mintToken: async () => 'test-token',
            fetchImpl: fakeFetch,
          },
        ),
      /500/,
    );
    assert.equal(committedWrites.length, 1);
    assert.ok(committedWrites[0].delete.endsWith('/docOld'));
  });

  test('evicts poison docs older than 7 days and retried >= 30 times', async () => {
    const now = new Date('2026-11-15T12:00:00Z');
    const oldCreated = new Date('2026-11-01T12:00:00Z').toISOString();
    let committedWrites = [];

    const queueDocsResponse = [
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docOld',
          fields: {
            token: { stringValue: 'tokenA'.repeat(20) },
            createdAt: { stringValue: oldCreated },
          },
        },
      },
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docRetried',
          fields: {
            token: { stringValue: 'tokenB'.repeat(20) },
            createdAt: { stringValue: now.toISOString() },
          },
        },
      },
    ];

    const fakeFetch = async (url, options) => {
      if (url.includes(':runQuery')) {
        return new Response(JSON.stringify(queueDocsResponse), { status: 200 });
      }
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/meta/push_topics',
                fields: {
                  retryCounts: {
                    mapValue: {
                      fields: {
                        docRetried: { integerValue: '30' },
                      },
                    },
                  },
                },
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes(':commit')) {
        const body = JSON.parse(options.body);
        committedWrites = body.writes;
        return new Response(JSON.stringify({ writeResults: [{}, {}] }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushQueueDrain(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    assert.equal(res.failed, 2);
    assert.equal(committedWrites.length, 2);
    assert.ok(committedWrites.some((w) => w.delete.endsWith('/docOld')));
    assert.ok(committedWrites.some((w) => w.delete.endsWith('/docRetried')));
  });

  test('successfully drains valid queue doc via Google IID and batch-deletes', async () => {
    const now = new Date('2026-11-15T12:00:00Z');
    let iidCalls = [];
    let committedWrites = [];
    let savedTopics = null;

    const queueDocsResponse = [
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docValid1',
          fields: {
            token: { stringValue: 'testToken12345'.repeat(8) },
            want: { arrayValue: { values: [{ stringValue: 'web_announcements_ar' }] } },
            rem: { stringValue: 'web_rem_lit-sun1_60_ar' },
            drop: { stringValue: 'web_rem_meeting-youth_30_ar' },
            createdAt: { stringValue: now.toISOString() },
          },
        },
      },
    ];

    const fakeFetch = async (url, options) => {
      if (url.includes(':runQuery')) {
        return new Response(JSON.stringify(queueDocsResponse), { status: 200 });
      }
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/meta/push_topics',
                fields: { topics: { mapValue: { fields: {} } } },
              },
            },
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/meta/push_rate',
                fields: { day: { integerValue: '20261115' }, count: { integerValue: '10' } },
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes('iid.googleapis.com')) {
        const op = url.split(':').pop();
        const body = JSON.parse(options.body);
        iidCalls.push({ op, ...body });
        return new Response(JSON.stringify({ results: [{}] }), { status: 200 });
      }
      if (url.includes('meta/push_topics')) {
        const body = JSON.parse(options.body);
        savedTopics = body;
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      if (url.includes(':commit')) {
        const body = JSON.parse(options.body);
        committedWrites = body.writes;
        return new Response(JSON.stringify({ writeResults: [{}] }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushQueueDrain(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    assert.equal(res.processed, 1);
    assert.equal(committedWrites.length, 1);
    assert.ok(committedWrites[0].delete.endsWith('/docValid1'));

    // Check IID calls: added to web_announcements_ar, added to web_rem_lit-sun1_60_ar,
    // removed from unselected fixed topics, removed from drop
    assert.ok(iidCalls.some((c) => c.op === 'batchAdd' && c.to === '/topics/web_announcements_ar'));
    assert.ok(iidCalls.some((c) => c.op === 'batchAdd' && c.to === '/topics/web_rem_lit-sun1_60_ar'));
    assert.ok(iidCalls.some((c) => c.op === 'batchRemove' && c.to === '/topics/web_rem_meeting-youth_30_ar'));

    // Check meta/push_topics was updated with active topic
    assert.ok(savedTopics?.fields?.topics?.mapValue?.fields?.['web_rem_lit-sun1_60_ar']);
  });

  test('subscribes valid test_* topics from newest want, ignores invalid strings, and cleans up unenroll & prevToken', async () => {
    const now = new Date('2026-11-15T12:00:00Z');
    const older = new Date('2026-11-15T11:50:00Z').toISOString();
    const newer = new Date('2026-11-15T11:55:00Z').toISOString();
    const iidCalls = [];

    const tok1 = 'tok1_' + 'x'.repeat(115);
    const oldTok = 'old1_' + 'y'.repeat(115);
    const tok2 = 'tok2_' + 'z'.repeat(115);

    const queueDocsResponse = [
      // Token 1 older doc: enrolled in test_old_topic and test_keep_topic, plus prevToken
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docA1',
          fields: {
            token: { stringValue: tok1 },
            prevToken: { stringValue: oldTok },
            want: {
              arrayValue: {
                values: [
                  { stringValue: 'web_announcements_ar' },
                  { stringValue: 'test_old_topic' },
                  { stringValue: 'test_keep_topic' },
                ],
              },
            },
            rem: { stringValue: 'web_rem_lit-sun1_60_ar' },
            createdAt: { stringValue: older },
          },
        },
      },
      // Token 1 newer doc: keeps test_keep_topic, drops test_old_topic, adds test_kerollos1, plus invalid strings
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docA2',
          fields: {
            token: { stringValue: tok1 },
            want: {
              arrayValue: {
                values: [
                  { stringValue: 'web_announcements_ar' },
                  { stringValue: 'test_keep_topic' },
                  { stringValue: 'test_kerollos1' },
                  { stringValue: 'all' },
                  { stringValue: 'app_announcements_ar' },
                  { stringValue: 'test_AB' },
                  { stringValue: 'test_ab' },
                  { stringValue: 'test_xx-yy' },
                ],
              },
            },
            createdAt: { stringValue: newer },
          },
        },
      },
      // Token 2: has invalid test topic in want and a reminder in rem/drop (rem/drop must not be treated as test topics)
      {
        document: {
          name: 'projects/test-project/databases/(default)/documents/push_queue/docB1',
          fields: {
            token: { stringValue: tok2 },
            want: {
              arrayValue: {
                values: [{ stringValue: 'test_INVALID' }],
              },
            },
            rem: { stringValue: 'web_rem_meeting-youth_15_ar' },
            drop: { stringValue: 'web_rem_day-old_30_ar' },
            createdAt: { stringValue: newer },
          },
        },
      },
    ];

    const fakeFetch = async (url, options) => {
      if (url.includes(':runQuery')) {
        return new Response(JSON.stringify(queueDocsResponse), { status: 200 });
      }
      if (url.includes(':batchGet')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('iid.googleapis.com')) {
        const op = url.split(':').pop();
        const body = JSON.parse(options.body);
        iidCalls.push({ op, ...body });
        return new Response(
          JSON.stringify({ results: body.registration_tokens.map(() => ({})) }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushQueueDrain(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    assert.equal(res.processed, 3);

    const hasCall = (op, topic, token) =>
      iidCalls.some(
        (c) => c.op === op && c.to === `/topics/${topic}` && c.registration_tokens.includes(token),
      );

    // Subscribed to newest valid test topics
    assert.ok(hasCall('batchAdd', 'test_keep_topic', tok1));
    assert.ok(hasCall('batchAdd', 'test_kerollos1', tok1));

    // Unsubscribed tok1 from test_old_topic (present in older doc, missing in newest)
    assert.ok(hasCall('batchRemove', 'test_old_topic', tok1));

    // Unsubscribed prevToken from all test topics seen for tok1
    assert.ok(hasCall('batchRemove', 'test_old_topic', oldTok));
    assert.ok(hasCall('batchRemove', 'test_keep_topic', oldTok));
    assert.ok(hasCall('batchRemove', 'test_kerollos1', oldTok));

    // Invalid want strings never trigger IID calls
    for (const bad of ['all', 'app_announcements_ar', 'test_AB', 'test_ab', 'test_xx-yy', 'test_INVALID']) {
      assert.equal(
        iidCalls.some((c) => c.to === `/topics/${bad}`),
        false,
        `must not call IID for invalid topic ${bad}`,
      );
    }

    // Reminder topics handled normally via rem/drop
    assert.ok(hasCall('batchAdd', 'web_rem_meeting-youth_15_ar', tok2));
    assert.ok(hasCall('batchRemove', 'web_rem_day-old_30_ar', tok2));
  });
});
