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
});
