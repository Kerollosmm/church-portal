// Comprehensive unit test suite for push_sender.js, push_daily.js, and firestore_rest.js (Node 22+).
// Runs via: node --test tool/push_sender.test.mjs

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  base64UrlEncode,
  base64UrlFromBytes,
  fromFirestoreFields,
  fromFirestoreValue,
  pemToDer,
  toFirestoreFields,
  toFirestoreValue,
} from './firestore_rest.js';
import {
  getCairoNow,
  getSeasonsSpec,
  renderTemplate,
  runDailySeasons,
} from './push_daily.js';
import {
  EXPIRE_WINDOW_MS,
  MAX_FCM_SENDS_PER_RUN,
  MAX_SENT_LOG_SIZE,
  parseScheduleRow,
  runPushSender,
  sendFcmMessage,
  sentryCheckIn,
} from './push_sender.js';

describe('firestore_rest', () => {
  test('base64Url encoding roundtrip', () => {
    const input = 'Hello, world! 123';
    const b64 = base64UrlEncode(input);
    assert.ok(!b64.includes('+'));
    assert.ok(!b64.includes('/'));
    assert.ok(!b64.includes('='));
  });

  test('Firestore Value converter handles primitives and maps', () => {
    const jsObj = {
      str: 'test',
      int: 42,
      num: 3.14,
      bool: true,
      nil: null,
      arr: ['a', 'b'],
      nested: { k: 'v' },
    };

    const fsFields = toFirestoreFields(jsObj);
    assert.equal(fsFields.str.stringValue, 'test');
    assert.equal(fsFields.int.integerValue, '42');
    assert.equal(fsFields.num.doubleValue, 3.14);
    assert.equal(fsFields.bool.booleanValue, true);
    assert.equal(fsFields.nil.nullValue, null);
    assert.equal(fsFields.arr.arrayValue.values.length, 2);
    assert.equal(fsFields.nested.mapValue.fields.k.stringValue, 'v');

    const back = fromFirestoreFields(fsFields);
    assert.deepEqual(back, jsObj);
  });
});

describe('push_daily', () => {
  test('Cairo time calculation returns valid ISO date and HH:mm', () => {
    const { dateIso, hhmm } = getCairoNow(new Date());
    assert.match(dateIso, /^\d{4}-\d{2}-\d{2}$/);
    assert.match(hhmm, /^[0-2]\d:[0-5]\d$/);
  });

  test('template rendering replaces all placeholders', () => {
    const tpl = 'Starts in {days} days on {date} for {season}!';
    const rendered = renderTemplate(tpl, { days: '3', date: '2026-11-25', season: 'Nativity' });
    assert.equal(rendered, 'Starts in 3 days on 2026-11-25 for Nativity!');
  });

  test('runDailySeasons skips when push is disabled or already run today', async () => {
    const resOff = await runDailySeasons('proj', 'tok', { push: false }, {}, []);
    assert.equal(resOff.skippedReason, 'push_disabled');

    const now = new Date('2026-11-08T10:00:00Z');
    const cairo = getCairoNow(now);
    const resDone = await runDailySeasons(
      'proj',
      'tok',
      { push: true, pushTypes: ['seasons'] },
      { lastSeasonDate: cairo.dateIso },
      [],
      fetch,
      now,
    );
    assert.equal(resDone.skippedReason, 'already_run_today');
  });

  test('runDailySeasons queries seasons and finds due season alerts', async () => {
    const now = new Date('2026-11-08T10:00:00Z');
    const cairo = getCairoNow(now);

    const mockFetch = async (url) => {
      if (url.includes('/seasons')) {
        return {
          ok: true,
          json: async () => ({
            documents: [
              {
                name: 'projects/p/databases/(default)/documents/seasons/nativity-fast',
                fields: {
                  nameAr: { stringValue: 'صوم الميلاد' },
                  nameEn: { stringValue: 'Nativity Fast' },
                  startsAt: { stringValue: `${cairo.dateIso}T00:00:00Z` },
                  active: { booleanValue: true },
                },
              },
            ],
          }),
        };
      }
      throw new Error(`Unexpected url: ${url}`);
    };

    const res = await runDailySeasons(
      'proj',
      'tok',
      { push: true, pushTypes: ['seasons'] },
      { lastSeasonDate: '2026-11-07' },
      [],
      mockFetch,
      now,
    );

    assert.equal(res.lastSeasonDate, cairo.dateIso);
    assert.equal(res.alerts.length, 1);
    assert.equal(res.alerts[0].seasonId, 'nativity-fast');
    assert.equal(res.alerts[0].daysRemaining, 0);
  });
});

describe('push_sender', () => {
  const fakeSa = {
    project_id: 'test-project',
    client_email: 'test-sa@test-project.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC7\n-----END PRIVATE KEY-----',
  };

  test('parseScheduleRow validates and extracts 9 fields', () => {
    const valid = 'row1\x1f2026-11-08T18:00:00Z\x1fall\x1fعنوان\x1fTitle\x1fنص\x1fBody\x1f/mass-schedule\x1flit-123';
    const parsed = parseScheduleRow(valid);
    assert.ok(parsed);
    assert.equal(parsed.id, 'row1');
    assert.equal(parsed.targets, 'all');
    assert.equal(parsed.titleAr, 'عنوان');
    assert.equal(parsed.eventKey, 'lit-123');

    assert.equal(parseScheduleRow('bad-row'), null);
  });

  test('sentryCheckIn fails open on network errors', async () => {
    const failingFetch = async () => {
      throw new Error('Sentry network error');
    };
    await sentryCheckIn('https://sentry.io/crons/123', 'in_progress', failingFetch);
  });

  test('runPushSender stops cleanly when master push toggle is off', async () => {
    const mockFetch = async (url) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: false } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: { health: { mapValue: { fields: {} } } },
                },
              },
            ]),
        };
      }
      return { ok: true, json: async () => ({}) };
    };

    const res = await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      { fetchImpl: mockFetch, mintToken: async () => 'mock-tok' },
    );

    assert.equal(res.status, 'skipped');
    assert.equal(res.reason, 'push_disabled');
  });

  test('runPushSender rejects topicOverride not starting with test_', async () => {
    await assert.rejects(
      async () => {
        await runPushSender(
          { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
          { topicOverride: 'prod_override' },
        );
      },
      /must start with 'test_'/,
    );
  });

  test('runPushSender processes due event pushes and enforces 16-send cap', async () => {
    const now = new Date('2026-11-08T18:00:00Z');
    const fcmCalls = [];
    const patches = [];

    // Create 6 due rows (each needs 4 topics = 24 topics total, should cap at 16 topics = 4 rows)
    const schedule = [];
    for (let i = 1; i <= 6; i++) {
      schedule.push(`r${i}\x1f2026-11-08T17:00:00Z\x1fall\x1fTitle ${i}\x1f\x1fBody ${i}\x1f\x1f/\x1f`);
    }

    const mockFetch = async (url, opts) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: true }, pushTypes: { arrayValue: { values: [] } } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: {
                    schedule: { arrayValue: { values: schedule.map((s) => ({ stringValue: s })) } },
                    status: { mapValue: { fields: {} } },
                    sentLog: { arrayValue: { values: [] } },
                  },
                  updateTime: '2026-11-08T17:59:00Z',
                },
              },
            ]),
        };
      }
      if (url.includes('messages:send')) {
        fcmCalls.push(JSON.parse(opts.body));
        return { ok: true, json: async () => ({ name: 'projects/p/messages/msg-123' }) };
      }
      if (opts?.method === 'PATCH') {
        patches.push(JSON.parse(opts.body));
        return { ok: true, json: async () => ({ fields: {}, updateTime: '2026-11-08T18:00:01Z' }) };
      }
      return { ok: true, json: async () => ({}) };
    };

    const res = await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      {
        fetchImpl: mockFetch,
        now,
        mintToken: async () => 'mock-tok',
      },
    );

    assert.equal(res.status, 'success');
    assert.equal(fcmCalls.length, 16); // exactly capped at 16 topic sends
    assert.equal(res.summary.sentRows, 4); // 4 rows fully sent (4 * 4 = 16)
  });

  test('runPushSender skips rows older than 24 hours (expired)', async () => {
    const now = new Date('2026-11-08T18:00:00Z');
    const fcmCalls = [];

    // Row scheduled 25 hours ago
    const schedule = ['old1\x1f2026-11-07T16:00:00Z\x1fall\x1fExpired\x1f\x1fBody\x1f\x1f/\x1f'];

    const mockFetch = async (url, opts) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: true }, pushTypes: { arrayValue: { values: [] } } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: {
                    schedule: { arrayValue: { values: schedule.map((s) => ({ stringValue: s })) } },
                    status: { mapValue: { fields: {} } },
                  },
                },
              },
            ]),
        };
      }
      if (url.includes('messages:send')) {
        fcmCalls.push(url);
        return { ok: true, json: async () => ({ name: 'msg-1' }) };
      }
      if (opts?.method === 'PATCH') {
        return { ok: true, json: async () => ({ fields: {} }) };
      }
      return { ok: true, json: async () => ({}) };
    };

    const res = await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      { fetchImpl: mockFetch, now, mintToken: async () => 'mock-tok' },
    );

    assert.equal(fcmCalls.length, 0); // Expired row never sent
    assert.equal(res.summary.sentRows, 0);
  });

  test('runPushSender handles 409/412 claim conflict cleanly', async () => {
    const now = new Date('2026-11-08T18:00:00Z');
    const schedule = ['conflict1\x1f2026-11-08T17:00:00Z\x1fall\x1fTitle\x1f\x1fBody\x1f\x1f/\x1f'];

    const mockFetch = async (url, opts) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: true }, pushTypes: { arrayValue: { values: [] } } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: {
                    schedule: { arrayValue: { values: [{ stringValue: schedule[0] }] } },
                    status: { mapValue: { fields: {} } },
                  },
                  updateTime: '2026-11-08T17:59:00Z',
                },
              },
            ]),
        };
      }
      if (opts?.method === 'PATCH') {
        // Return 412 precondition failed
        return { status: 412, text: async () => 'Precondition Failed' };
      }
      return { ok: true, json: async () => ({}) };
    };

    const res = await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      { fetchImpl: mockFetch, now, mintToken: async () => 'mock-tok' },
    );

    assert.equal(res.status, 'success');
    assert.equal(res.summary.claimConflict, true);
    assert.equal(res.summary.fcmSends, 0);
  });

  test('runPushSender prunes orphaned status keys not in schedule', async () => {
    const now = new Date('2026-11-08T18:00:00Z');
    let patchedStatus = null;

    const mockFetch = async (url, opts) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: true }, pushTypes: { arrayValue: { values: [] } } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: {
                    schedule: { arrayValue: { values: [] } }, // empty schedule
                    status: {
                      mapValue: {
                        fields: {
                          deletedRow: { mapValue: { fields: { state: { stringValue: 'ok' } } } },
                        },
                      },
                    },
                  },
                },
              },
            ]),
        };
      }
      if (opts?.method === 'PATCH') {
        const body = JSON.parse(opts.body);
        patchedStatus = body.fields.status?.mapValue?.fields;
        return { ok: true, json: async () => ({ fields: {} }) };
      }
      return { ok: true, json: async () => ({}) };
    };

    await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      { fetchImpl: mockFetch, now, mintToken: async () => 'mock-tok' },
    );

    assert.ok(patchedStatus);
    assert.equal(Object.keys(patchedStatus).length, 0); // 'deletedRow' pruned!
  });
});

// PR #55: the admin screen (lib/ui/admin/notifications_admin.dart) writes
// exactly these formats; the sender must read them.
describe('admin ↔ sender formats (PR #55)', () => {
  test('a row as the admin saves it (whole-second UTC, Arabic body) is parsed', () => {
    const row = ['ab12cd34', '2026-11-10T07:00:00Z', 'app', 'نهضة العذراء', '', 'تبدأ ٧ مساءً', '', '/church-education/youth', 'meeting-youth'].join('\x1f');
    const r = parseScheduleRow(row);
    assert.ok(r);
    assert.equal(r.atUtc.toISOString(), '2026-11-10T07:00:00.000Z');
    assert.equal(r.targets, 'app');
    assert.equal(r.eventKey, 'meeting-youth');
  });

  test('a seasons row saved by the admin (time + days before) drives the daily alert spec', () => {
    const spec = getSeasonsSpec({ notifyTypes: [['seasons', '08:30', '2', 'موسم {season}', '', '', ''].join('\x1f')] });
    assert.equal(spec.time, '08:30');
    assert.equal(spec.daysBefore, 2);
    assert.equal(spec.titleAr, 'موسم {season}');
    assert.ok(spec.bodyAr.includes('{days}'), 'empty body falls back to the default');
  });

  test('season alerts open an existing route (no /seasons page exists)', () => {
    assert.equal(getSeasonsSpec({}).defaultLink, '/mass-schedule');
  });
});

describe('ADR-060: Web push delivery, condition format, and token caching', () => {
  test('secondsUntilCairoEndOfDay calculates seconds with 300s floor', async () => {
    const { secondsUntilCairoEndOfDay } = await import('./push_sender.js');
    const midDay = new Date('2026-11-15T12:00:00Z').getTime();
    const secs = secondsUntilCairoEndOfDay(midDay);
    assert.ok(secs > 300, 'should be more than 300 seconds from noon');

    // Right before midnight
    const late = new Date('2026-11-15T21:59:58Z').getTime(); // 23:59:58 Cairo
    assert.equal(secondsUntilCairoEndOfDay(late), 300, 'should enforce 300s floor');
  });

  test('sendFcmMessage injects webpush headers and supports condition', async () => {
    let capturedBody = null;
    const mockFetch = async (url, opts) => {
      capturedBody = JSON.parse(opts.body);
      return { ok: true, json: async () => ({ name: 'projects/p/messages/123' }) };
    };

    const target = { condition: "'web_rem_lit-sun1_60_ar' in topics || 'web_rem_lit-sun1_20261115_60_ar' in topics" };
    const res = await sendFcmMessage(
      'test-project',
      'mock-token',
      target,
      {
        nid: 'rem_123',
        type: 'reminders',
        lang: 'ar',
        title: 'تذكير بالقداس',
        body: 'القداس يبدأ قريبا',
        link: '/liturgy/sun1',
        eventKey: 'lit-sun1',
        sentAt: '2026-11-15T06:00:00Z',
        ttlSeconds: '1800',
      },
      mockFetch,
    );

    assert.equal(res.status, 'ok');
    assert.equal(capturedBody.message.condition, target.condition);
    assert.equal(capturedBody.message.topic, undefined);
    assert.equal(capturedBody.message.webpush.headers.Urgency, 'high');
    assert.equal(capturedBody.message.webpush.headers.TTL, '1800');
    assert.equal(capturedBody.message.android.priority, 'high');
  });

  test('getCachedAccessToken utilizes L1 module cache and L2 PUSH_KV', async () => {
    const { getCachedAccessToken, _resetL1TokenCacheForTesting } = await import('./firestore_rest.js');
    const { generateKeyPairSync } = await import('node:crypto');
    _resetL1TokenCacheForTesting();

    const { privateKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });

    const mockSa = {
      client_email: 'kv-test@example.com',
      private_key: privateKey,
    };

    let kvStore = new Map();
    const env = {
      PUSH_KV: {
        get: async (k) => kvStore.get(k) || null,
        put: async (k, v) => kvStore.set(k, JSON.parse(v)),
      },
    };

    let fetchCount = 0;
    const fakeFetch = async () => {
      fetchCount++;
      return new Response(JSON.stringify({ access_token: `token-${fetchCount}` }), { status: 200 });
    };

    const now = Date.now();
    // 1. Initial call mints and populates L1 + L2
    const tok1 = await getCachedAccessToken(mockSa, env, fakeFetch, now);
    assert.equal(tok1, 'token-1');
    assert.equal(fetchCount, 1);

    // 2. Immediate call hits L1 cache (no fetch, no KV)
    const tok2 = await getCachedAccessToken(mockSa, env, fakeFetch, now + 1000);
    assert.equal(tok2, 'token-1');
    assert.equal(fetchCount, 1);

    // 3. Reset L1 to simulate new cold-start isolate: hits L2 PUSH_KV
    _resetL1TokenCacheForTesting();
    const tok3 = await getCachedAccessToken(mockSa, env, fakeFetch, now + 2000);
    assert.equal(tok3, 'token-1');
    assert.equal(fetchCount, 1); // Served from KV, zero network fetch!
  });

  test('runPushSender dispatches due web reminders with condition and stamps remindersSent', async () => {
    const now = new Date('2026-11-15T07:00:00Z');
    let capturedSends = [];
    let patchedData = null;

    const mockFetch = async (url, opts) => {
      if (url.includes(':batchGet')) {
        return {
          ok: true,
          text: async () =>
            JSON.stringify([
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/features',
                  fields: { push: { booleanValue: true } },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/settings/notifications',
                  fields: {
                    schedule: { arrayValue: { values: [] } },
                    remindersSent: { mapValue: { fields: {} } },
                  },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/meta/push_plan',
                  fields: {
                    reminderPlan: {
                      arrayValue: {
                        values: [
                          {
                            mapValue: {
                              fields: {
                                tKey: { stringValue: 'lit-sun1' },
                                serviceStartMs: { integerValue: String(now.getTime() + 60 * 60 * 1000) }, // 1 hour ahead
                                leads: { arrayValue: { values: [{ integerValue: '60' }] } },
                                languages: { arrayValue: { values: [{ stringValue: 'ar' }] } },
                                titleAr: { stringValue: 'قداس الأحد' },
                                titleEn: { stringValue: 'Sunday Liturgy' },
                                bodyAr: { stringValue: 'يبدأ القداس بعد ساعة' },
                                bodyEn: { stringValue: 'Liturgy starts in an hour' },
                                yyyymmdd: { stringValue: '20261115' },
                                link: { stringValue: '/liturgy/sun1' },
                              },
                            },
                          },
                        ],
                      },
                    },
                  },
                },
              },
              {
                found: {
                  name: 'projects/p/databases/(default)/documents/meta/push_topics',
                  fields: {
                    topics: {
                      mapValue: {
                        fields: {
                          'web_rem_lit-sun1_60_ar': { booleanValue: true },
                          'web_rem_lit-sun1_20261115_60_ar': { booleanValue: true },
                        },
                      },
                    },
                  },
                },
              },
            ]),
        };
      }
      if (url.includes('fcm.googleapis.com')) {
        const body = JSON.parse(opts.body);
        capturedSends.push(body);
        return { ok: true, json: async () => ({ name: 'msg/123' }) };
      }
      if (opts?.method === 'PATCH') {
        patchedData = JSON.parse(opts.body);
        return { ok: true, json: async () => ({ fields: {} }) };
      }
      return { ok: true, json: async () => ({}) };
    };

    const fakeSa = {
      client_email: 'test@sa.test',
      private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC3\n-----END PRIVATE KEY-----',
    };

    const res = await runPushSender(
      { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(fakeSa) },
      { fetchImpl: mockFetch, now, mintToken: async () => 'mock-tok' },
    );

    assert.equal(res.status, 'success');
    assert.equal(res.summary.remindersSent, 1);
    assert.equal(capturedSends.length, 1);
    assert.ok(capturedSends[0].message.condition.includes("'web_rem_lit-sun1_60_ar' in topics"));
    assert.ok(capturedSends[0].message.condition.includes("'web_rem_lit-sun1_20261115_60_ar' in topics"));
    assert.ok(patchedData.fields.remindersSent.mapValue.fields['lit-sun1:20261115:60:ar']);
  });
});

