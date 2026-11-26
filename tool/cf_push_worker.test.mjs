// Unit tests for cf_push_worker.js (Node 22+).
// Runs via: node --test tool/cf_push_worker.test.mjs

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';

import worker, { buildSentryStoreRequest } from './cf_push_worker.js';

describe('buildSentryStoreRequest', () => {
  test('builds Sentry legacy store endpoint URL and X-Sentry-Auth header from DSN', () => {
    const req = buildSentryStoreRequest(
      'https://pubKey123@o456.ingest.us.sentry.io/789',
      new Error('boom'),
      'push_queue_drain',
    );

    assert.ok(req);
    assert.equal(req.url, 'https://o456.ingest.us.sentry.io/api/789/store/');
    assert.equal(req.method, 'POST');
    assert.equal(req.headers['Content-Type'], 'application/json');
    assert.ok(req.headers['X-Sentry-Auth'].includes('sentry_key=pubKey123'));
    assert.ok(req.headers['X-Sentry-Auth'].includes('sentry_version=7'));
    assert.equal(req.headers.Authorization, undefined);

    const payload = JSON.parse(req.body);
    assert.equal(payload.level, 'error');
    assert.equal(payload.tags.section, 'push_queue_drain');
    assert.equal(payload.message, 'boom');
  });

  test('returns null for empty or invalid DSNs', () => {
    assert.equal(buildSentryStoreRequest('', new Error('boom'), 'push_queue_drain'), null);
    assert.equal(buildSentryStoreRequest(null, new Error('boom'), 'push_queue_drain'), null);
    assert.equal(buildSentryStoreRequest('not-a-url', new Error('boom'), 'push_queue_drain'), null);
    assert.equal(
      buildSentryStoreRequest('https://o456.ingest.us.sentry.io/789', new Error('boom'), 'push_queue_drain'),
      null,
    );
    assert.equal(
      buildSentryStoreRequest('https://pubKey123@o456.ingest.us.sentry.io/', new Error('boom'), 'push_queue_drain'),
      null,
    );
  });

  test('scrubs Bearer tokens and private keys from error message', () => {
    const err = new Error(
      'IID failed with Bearer ya29.super-secret-token and -----BEGIN PRIVATE KEY-----\nABC123SECRET\n-----END PRIVATE KEY-----',
    );
    const req = buildSentryStoreRequest('https://pubKey123@o456.ingest.us.sentry.io/789', err, 'push_queue_drain');

    assert.ok(req);
    const payload = JSON.parse(req.body);
    assert.equal(payload.message.includes('ya29.super-secret-token'), false);
    assert.equal(payload.message.includes('ABC123SECRET'), false);
    assert.ok(payload.message.includes('[REDACTED'));
  });
});

describe('cf_push_worker scheduled', () => {
  test('posts errors to /api/<projectId>/store/ when runner rejects (never raw DSN)', async () => {
    const origFetch = globalThis.fetch;
    const origConsoleError = console.error;
    const fetchCalls = [];
    const pending = [];

    globalThis.fetch = async (url, init) => {
      fetchCalls.push({ url, init });
      return new Response('{}', { status: 200 });
    };
    console.error = () => {};

    try {
      await worker.scheduled(
        { cron: '7,22,37,52 * * * *' },
        { SENTRY_DSN: 'https://pubKey123@o456.ingest.us.sentry.io/789' },
        { waitUntil: (p) => pending.push(p) },
      );
      await Promise.all(pending);
    } finally {
      globalThis.fetch = origFetch;
      console.error = origConsoleError;
    }

    assert.equal(fetchCalls.length, 1);
    assert.equal(fetchCalls[0].url, 'https://o456.ingest.us.sentry.io/api/789/store/');
    assert.notEqual(fetchCalls[0].url, 'https://pubKey123@o456.ingest.us.sentry.io/789');
    assert.ok(fetchCalls[0].init.headers['X-Sentry-Auth'].includes('sentry_key=pubKey123'));
    assert.equal(JSON.parse(fetchCalls[0].init.body).tags.section, 'push_queue_drain');
  });
});
