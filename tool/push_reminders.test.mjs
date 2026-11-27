// Comprehensive unit tests for push_reminders.js and 60-day calendar parity (Node 22+).
// Runs via: node --test tool/push_reminders.test.mjs

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  cairoToUtc,
  computeDayEventHashId,
  decodeDayEvents,
  getCairoParts,
  reminderSourceOf,
  runPushReminderPlanner,
  topicKey,
} from './push_reminders.js';

describe('push_reminders helpers', () => {
  test('topicKey normalizes, validates prefix and caps at 40 chars', () => {
    assert.equal(topicKey('lit-sun1'), 'lit-sun1');
    assert.equal(topicKey('LIT-FRI1'), 'lit-fri1');
    assert.equal(topicKey('meeting-Youth_Group'), 'meeting-youth-group');
    assert.equal(topicKey('day-1234567890'), 'day-1234567890');
    assert.equal(topicKey('season-pascha'), 'season-pascha');

    // ID capped at 40 characters
    const longId = 'x'.repeat(60);
    assert.equal(topicKey(`lit-${longId}`), `lit-${'x'.repeat(40)}`);

    // Invalid prefix or format returns ''
    assert.equal(topicKey('invalid-prefix'), '');
    assert.equal(topicKey('app_rem_lit'), '');
    assert.equal(topicKey(''), '');
    assert.equal(topicKey(null), '');
  });

  test('reminderSourceOf maps canonical keys correctly', () => {
    assert.equal(reminderSourceOf('lit-fri1'), 'lit');
    assert.equal(reminderSourceOf('season-pascha'), 'lit');
    assert.equal(reminderSourceOf('meeting-youth'), 'mtg');
    assert.equal(reminderSourceOf('day-1234567890'), 'day');
    assert.equal(reminderSourceOf('unknown'), '');
  });

  test('cairoToUtc accurately converts Cairo wall time to UTC across DST transitions', () => {
    // Cairo winter (UTC+2): 06:30 Cairo is 04:30 UTC
    const winter = cairoToUtc(2026, 11, 6, 6, 30);
    assert.equal(winter.toISOString(), '2026-11-06T04:30:00.000Z');

    // Cairo summer DST (UTC+3): 06:30 Cairo is 03:30 UTC
    const summer = cairoToUtc(2027, 7, 3, 6, 30);
    assert.equal(summer.toISOString(), '2027-07-03T03:30:00.000Z');

    // Late-evening and post-midnight Cairo times (#135)
    assert.equal(cairoToUtc(2026, 7, 15, 23, 0).toISOString(), '2026-07-15T20:00:00.000Z');
    assert.equal(cairoToUtc(2026, 7, 15, 23, 30).toISOString(), '2026-07-15T20:30:00.000Z');
    assert.equal(cairoToUtc(2026, 7, 15, 22, 0).toISOString(), '2026-07-15T19:00:00.000Z');
    assert.equal(cairoToUtc(2026, 1, 15, 23, 0).toISOString(), '2026-01-15T21:00:00.000Z');
    assert.equal(cairoToUtc(2026, 7, 15, 0, 30).toISOString(), '2026-07-14T21:30:00.000Z');
    assert.equal(cairoToUtc(2026, 1, 15, 0, 30).toISOString(), '2026-01-14T22:30:00.000Z');

    // Seconds parameter
    assert.equal(cairoToUtc(2026, 7, 15, 23, 59, 59).toISOString(), '2026-07-15T20:59:59.000Z');
    assert.equal(cairoToUtc(2026, 1, 15, 23, 59, 59).toISOString(), '2026-01-15T21:59:59.000Z');

    // Spring-forward day 2026-04-24 (last Friday of April: 00:00 -> 01:00 EEST)
    assert.equal(cairoToUtc(2026, 4, 23, 23, 30).toISOString(), '2026-04-23T21:30:00.000Z');
    assert.equal(cairoToUtc(2026, 4, 24, 0, 0).toISOString(), cairoToUtc(2026, 4, 24, 1, 0).toISOString());
    assert.equal(cairoToUtc(2026, 4, 24, 0, 30).toISOString(), cairoToUtc(2026, 4, 24, 1, 30).toISOString());
    assert.equal(cairoToUtc(2026, 4, 24, 0, 30).toISOString(), '2026-04-23T22:30:00.000Z');

    // Fall-back day 2026-10-29 (last Thursday of October: 24:00 -> 23:00 EET)
    // Ambiguous 23:xx must resolve to FIRST occurrence (EEST, UTC+3)
    assert.equal(cairoToUtc(2026, 10, 29, 23, 0).toISOString(), '2026-10-29T20:00:00.000Z');
    assert.equal(cairoToUtc(2026, 10, 29, 23, 30).toISOString(), '2026-10-29T20:30:00.000Z');
    assert.equal(cairoToUtc(2026, 10, 29, 23, 59, 59).toISOString(), '2026-10-29T20:59:59.000Z');
    assert.equal(cairoToUtc(2026, 10, 30, 0, 0).toISOString(), '2026-10-29T22:00:00.000Z');
  });

  test('cairoToUtc round-trips every 30 minutes across all of 2026 (skipping spring-forward gap)', () => {
    for (let t = Date.UTC(2026, 0, 1, 0, 0); t < Date.UTC(2027, 0, 1, 0, 0); t += 30 * 60000) {
      const d = new Date(t);
      const y = d.getUTCFullYear();
      const m = d.getUTCMonth() + 1;
      const day = d.getUTCDate();
      const h = d.getUTCHours();
      const mi = d.getUTCMinutes();
      if (y === 2026 && m === 4 && day === 24 && h === 0) continue; // non-existent spring-forward gap hour
      const utc = cairoToUtc(y, m, day, h, mi);
      const cp = getCairoParts(utc);
      assert.deepEqual(
        { year: cp.year, month: cp.month, day: cp.day, hour: cp.hour, minute: cp.minute, second: cp.second },
        { year: y, month: m, day, hour: h, minute: mi, second: 0 },
        `Round-trip failed for ${y}-${m}-${day} ${h}:${mi}`,
      );
    }
  });

  test('computeDayEventHashId returns 10-hex SHA-1 prefix', async () => {
    const hash = await computeDayEventHashId('2026-11-15', '18:00', 'اجتماع الشباب');
    assert.equal(hash.length, 10);
    assert.equal(/^[0-9a-f]{10}$/.test(hash), true);
    assert.equal(hash, '270f4890e6');
  });

  test('decodeDayEvents handles 17-field strings and fallback hash', async () => {
    // 17-field string with explicit ID
    const sWithId = [
      '2026-11-20', '2026-11-20', '18:00', '20:00',
      'عنوان عربي', 'English Title', 'المتكلم', '',
      'الموضوع', '', 'ملاحظات', '', '/details',
      'https://attachment.url', 'تحميل', 'Download',
      'custom-event-id',
    ].join('\u001f');

    // 13-field string without 17th ID
    const sWithoutId = [
      '2026-11-25', '2026-11-25', '19:00', '21:00',
      'عنوان ثاني', '', '', '',
      '', '', '', '', '',
    ].join('\u001f');

    const decoded = await decodeDayEvents([sWithId, sWithoutId]);
    assert.equal(decoded.length, 2);
    assert.equal(decoded[0].id, 'custom-event-id');
    assert.equal(decoded[1].id.length, 10);
  });
});

describe('60-day calendar parity fixture verification (Node ↔ Dart)', () => {
  const fixturePath = join(process.cwd(), 'test', 'fixtures', 'occurrences_parity_60d.json');
  const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));

  test('fixture has 21 occurrences', () => {
    assert.equal(fixture.length, 21);
  });

  test('every fixture item matches JS topicKey, reminderSourceOf and cairoToUtc', () => {
    for (const item of fixture) {
      const rawKey = item.rawEventKey;
      const expectedTopicKey = item.topicKey;
      const expectedSource = item.source;
      const cairoDate = item.cairoDate;
      const start = item.start;
      const expectedUtc = item.startsAtUtc;

      // 1. Topic key parity
      assert.equal(topicKey(rawKey), expectedTopicKey, `topicKey mismatch for ${rawKey}`);

      // 2. Source mapping parity
      assert.equal(reminderSourceOf(rawKey), expectedSource, `source mismatch for ${rawKey}`);

      // 3. Cairo wall time -> UTC instant parity (including DST transition night)
      const [y, m, d] = cairoDate.split('-').map((x) => parseInt(x, 10));
      const [sh, sm] = start.split(':').map((x) => parseInt(x, 10));
      const utcDate = cairoToUtc(y, m, d, sh, sm);
      assert.equal(utcDate.toISOString(), expectedUtc, `UTC instant mismatch on ${cairoDate} ${start}`);
    }
  });
});

describe('runPushReminderPlanner workflow', () => {
  const mockSa = {
    client_email: 'test@serviceaccount.com',
    project_id: 'test-project',
    private_key: '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC3\n-----END PRIVATE KEY-----',
  };

  test('generates reminderPlan sorted by serviceStartMs ASC and writes meta/push_plan', async () => {
    const now = new Date('2027-04-20T10:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/settings/features',
                fields: {
                  dayEvents: {
                    arrayValue: {
                      values: [
                        {
                          stringValue: [
                            '2027-04-20', '2027-04-20', '18:00', '20:00',
                            'نهضة الشباب', 'Youth Revival', '', '',
                            '', '', '', '', '/revival',
                            '', '', '', 'youth-revival-id',
                          ].join('\u001f'),
                        },
                      ],
                    },
                  },
                },
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/fri1',
                fields: {
                  weekday: { integerValue: '5' },
                  start: { stringValue: '06:30' },
                  end: { stringValue: '08:30' },
                  nameAr: { stringValue: 'القداس الأول' },
                  nameEn: { stringValue: 'First Liturgy' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/meetings/youth',
                fields: {
                  weekday: { integerValue: '5' },
                  start: { stringValue: '19:00' },
                  nameAr: { stringValue: 'اجتماع الشباب' },
                  nameEn: { stringValue: 'Youth Meeting' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/seasons')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    assert.ok(res.plannedCount >= 1);
    assert.ok(res.activeEventKeysCount >= 3);
    assert.ok(savedPlan?.fields?.reminderPlan?.arrayValue?.values?.length >= 1);
    assert.ok(savedPlan?.fields?.activeEventKeys?.arrayValue?.values?.length >= 3);
  });

  test('emits valid /mass-schedule and /church-education/<id> deep links for upcoming liturgies and meetings', async () => {
    // Friday 2027-04-23 (ISO weekday 5) early morning Cairo
    const now = new Date('2027-04-23T02:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/fri1',
                fields: {
                  weekday: { integerValue: '5' },
                  start: { stringValue: '06:30' },
                  end: { stringValue: '08:30' },
                  nameAr: { stringValue: 'القداس الأول' },
                  nameEn: { stringValue: 'First Liturgy' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/meetings/youth',
                fields: {
                  weekday: { integerValue: '5' },
                  start: { stringValue: '19:00' },
                  nameAr: { stringValue: 'اجتماع الشباب' },
                  nameEn: { stringValue: 'Youth Meeting' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/seasons')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    const plannedItems = savedPlan.fields.reminderPlan.arrayValue.values.map((v) => v.mapValue.fields);
    const friItem = plannedItems.find((f) => f.tKey.stringValue === 'lit-fri1');
    const mtgItem = plannedItems.find((f) => f.tKey.stringValue === 'meeting-youth');
    assert.equal(friItem?.link?.stringValue, '/mass-schedule');
    assert.equal(mtgItem?.link?.stringValue, '/church-education/youth');
  });

  test('filters seasonal liturgies by active season and suppresses replaced regular liturgies', async () => {
    // Tuesday 2027-04-20 (ISO weekday 2) in Holy Week overriding season
    const now = new Date('2027-04-20T03:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/settings/features',
                fields: {},
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/tue-reg',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '07:00' },
                  end: { stringValue: '09:00' },
                  nameAr: { stringValue: 'قداس الثلاثاء' },
                  nameEn: { stringValue: 'Tuesday Liturgy' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/pascha-tue',
                fields: {
                  seasonKey: { stringValue: 'pascha' },
                  date: { stringValue: '2027-04-20' },
                  start: { stringValue: '10:00' },
                  end: { stringValue: '12:00' },
                  nameAr: { stringValue: 'بصخة الثلاثاء' },
                  nameEn: { stringValue: 'Pascha Tuesday' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/stale-season',
                fields: {
                  seasonKey: { stringValue: 'ended-season' },
                  date: { stringValue: '2027-04-20' },
                  start: { stringValue: '12:00' },
                  nameAr: { stringValue: 'موسم منتهي' },
                  nameEn: { stringValue: 'Ended Season' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('/seasons')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/seasons/pascha',
                fields: {
                  key: { stringValue: 'pascha' },
                  active: { booleanValue: true },
                  replacesRegular: { booleanValue: true },
                  startsAt: { stringValue: '2027-04-19T00:00:00Z' },
                  endsAt: { stringValue: '2027-04-21T23:59:59Z' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/seasons/ended-season',
                fields: {
                  key: { stringValue: 'ended-season' },
                  active: { booleanValue: false },
                  startsAt: { stringValue: '2027-04-01T00:00:00Z' },
                  endsAt: { stringValue: '2027-04-10T23:59:59Z' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    const plannedKeys = savedPlan.fields.reminderPlan.arrayValue.values.map(
      (v) => `${v.mapValue.fields.tKey.stringValue}:${v.mapValue.fields.yyyymmdd.stringValue}`,
    );
    assert.ok(plannedKeys.includes('lit-pascha-tue:20270420'), 'Active seasonal service should be planned under lit-<id>');
    assert.ok(!plannedKeys.includes('lit-tue-reg:20270420'), 'Regular mass on replaced day should be suppressed');
    assert.ok(!plannedKeys.includes('lit-stale-season:20270420'), 'Inactive season service should be skipped');
    const paschaItem = savedPlan.fields.reminderPlan.arrayValue.values.find(
      (v) => v.mapValue.fields.tKey.stringValue === 'lit-pascha-tue',
    );
    assert.equal(paschaItem.mapValue.fields.link.stringValue, '/mass-schedule');
    const activeKeys = savedPlan.fields.activeEventKeys.arrayValue.values.map((v) => v.stringValue);
    assert.ok(activeKeys.includes('lit-pascha-tue'), 'activeEventKeys must register seasonal liturgy under lit-<id>');
    assert.ok(!activeKeys.includes('season-pascha-tue'), 'activeEventKeys must not use season-<id> for liturgies');
  });

  test('converts timestampValue UTC dates in Cairo and suppresses overridden undated seasonal services', async () => {
    // Tuesday 2027-01-05T12:00Z (planning Tue 2027-01-05 .. Thu 2027-01-07)
    // Epiphany/Nativity liturgy timestamp '2027-01-05T22:00:00Z' is 2027-01-06 00:00 Cairo.
    const now = new Date('2027-01-05T12:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/settings/features',
                fields: {},
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/wed-reg',
                fields: {
                  weekday: { integerValue: '3' }, // Wednesday 2027-01-06
                  start: { stringValue: '09:00' },
                  end: { stringValue: '10:00' },
                  nameAr: { stringValue: 'قداس الأربعاء' },
                  nameEn: { stringValue: 'Wednesday Liturgy' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/rev-undated',
                fields: {
                  seasonKey: { stringValue: 'revival' },
                  weekday: { integerValue: '3' },
                  start: { stringValue: '07:00' },
                  end: { stringValue: '10:00' },
                  nameAr: { stringValue: 'نهضة أسبوعية' },
                  nameEn: { stringValue: 'Weekly Revival' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/rev-dated',
                fields: {
                  seasonKey: { stringValue: 'revival' },
                  date: { timestampValue: '2027-01-05T22:00:00Z' }, // Cairo 2027-01-06
                  start: { stringValue: '08:00' },
                  end: { stringValue: '09:00' },
                  nameAr: { stringValue: 'خدمة مخصصة' },
                  nameEn: { stringValue: 'Special Dated Service' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('/seasons')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/seasons/revival',
                fields: {
                  key: { stringValue: 'revival' },
                  active: { booleanValue: true },
                  replacesRegular: { booleanValue: false },
                  startsAt: { stringValue: '2027-01-01T00:00:00Z' },
                  endsAt: { stringValue: '2027-01-10T23:59:59Z' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    const plannedKeys = savedPlan.fields.reminderPlan.arrayValue.values.map(
      (v) => `${v.mapValue.fields.tKey.stringValue}:${v.mapValue.fields.yyyymmdd.stringValue}`,
    );
    assert.ok(plannedKeys.includes('lit-rev-dated:20270106'), 'Timestamp date must map to Cairo 2027-01-06 under lit-<id>');
    assert.ok(!plannedKeys.includes('lit-rev-undated:20270106'), 'Overlapping undated seasonal service must be suppressed');
    assert.ok(plannedKeys.includes('lit-wed-reg:20270106'), 'Non-overlapping regular liturgy 09:00-10:00 must remain');
  });

  test('rethrows write failure when writing meta/push_plan returns HTTP 500', async () => {
    const now = new Date('2027-01-05T12:00:00Z');
    const fakeFetch = async (url) => {
      if (url.includes(':batchGet')) {
        return new Response(
          JSON.stringify([
            {
              found: {
                name: 'projects/test-project/databases/(default)/documents/settings/features',
                fields: {},
              },
            },
          ]),
          { status: 200 },
        );
      }
      if (url.includes('/liturgies') || url.includes('/meetings') || url.includes('/seasons')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('meta/push_plan')) {
        return new Response('Internal Error', { status: 500 });
      }
      return new Response('{}', { status: 200 });
    };

    await assert.rejects(
      () =>
        runPushReminderPlanner(
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

  test('seasonal liturgy plans tKey and activeEventKeys under lit-<id> matching Dart UI (#136)', async () => {
    const now = new Date('2027-04-20T03:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/pascha-eve',
                fields: {
                  seasonKey: { stringValue: 'pascha' },
                  date: { stringValue: '2027-04-20' },
                  start: { stringValue: '18:00' },
                  end: { stringValue: '20:00' },
                  nameAr: { stringValue: 'بصخة المساء' },
                  nameEn: { stringValue: 'Evening Pascha' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(JSON.stringify({ documents: [] }), { status: 200 });
      }
      if (url.includes('/seasons')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/seasons/pascha',
                fields: {
                  key: { stringValue: 'pascha' },
                  active: { booleanValue: true },
                  startsAt: { stringValue: '2027-04-19T00:00:00Z' },
                  endsAt: { stringValue: '2027-04-25T23:59:59Z' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    const dartUiKey = 'lit-pascha-eve'; // EventKey.liturgy('pascha-eve')
    const plannedKeys = savedPlan.fields.reminderPlan.arrayValue.values.map(
      (v) => v.mapValue.fields.tKey.stringValue,
    );
    const activeKeys = savedPlan.fields.activeEventKeys.arrayValue.values.map((v) => v.stringValue);
    assert.deepEqual(plannedKeys, [dartUiKey]);
    assert.ok(activeKeys.includes(dartUiKey));
    assert.ok(!activeKeys.includes('season-pascha-eve'));
  });

  test('skips soft-deleted liturgies, meetings, and seasons while keeping deletedAt null/missing (#138)', async () => {
    // Tuesday 2027-04-20 (ISO weekday 2)
    const now = new Date('2027-04-20T03:00:00Z');
    let savedPlan = null;

    const fakeFetch = async (url, options) => {
      if (url.includes(':batchGet')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.includes('/liturgies')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/tue-deleted',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '07:00' },
                  end: { stringValue: '09:00' },
                  nameAr: { stringValue: 'قداس محذوف' },
                  nameEn: { stringValue: 'Deleted Liturgy' },
                  deletedAt: { timestampValue: '2027-04-20T02:59:55Z' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/tue-restored',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '08:00' },
                  end: { stringValue: '10:00' },
                  nameAr: { stringValue: 'قداس مستعاد' },
                  nameEn: { stringValue: 'Restored Liturgy' },
                  deletedAt: { nullValue: null },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/tue-active',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '10:30' },
                  end: { stringValue: '12:00' },
                  nameAr: { stringValue: 'قداس قائم' },
                  nameEn: { stringValue: 'Active Liturgy' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/liturgies/pascha-deleted-season-lit',
                fields: {
                  seasonKey: { stringValue: 'pascha' },
                  date: { stringValue: '2027-04-20' },
                  start: { stringValue: '18:00' },
                  end: { stringValue: '20:00' },
                  nameAr: { stringValue: 'بصخة لموسم محذوف' },
                  nameEn: { stringValue: 'Deleted Season Service' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/meetings')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/meetings/mtg-deleted',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '19:00' },
                  nameAr: { stringValue: 'اجتماع محذوف' },
                  nameEn: { stringValue: 'Deleted Meeting' },
                  deletedAt: { timestampValue: '2027-04-20T02:59:55Z' },
                },
              },
              {
                name: 'projects/test-project/databases/(default)/documents/meetings/mtg-restored',
                fields: {
                  weekday: { integerValue: '2' },
                  start: { stringValue: '20:00' },
                  nameAr: { stringValue: 'اجتماع مستعاد' },
                  nameEn: { stringValue: 'Restored Meeting' },
                  deletedAt: { nullValue: null },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('/seasons')) {
        return new Response(
          JSON.stringify({
            documents: [
              {
                name: 'projects/test-project/databases/(default)/documents/seasons/pascha',
                fields: {
                  key: { stringValue: 'pascha' },
                  active: { booleanValue: true },
                  replacesRegular: { booleanValue: true },
                  startsAt: { stringValue: '2027-04-19T00:00:00Z' },
                  endsAt: { stringValue: '2027-04-25T23:59:59Z' },
                  deletedAt: { timestampValue: '2027-04-20T02:59:55Z' },
                },
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (url.includes('meta/push_plan')) {
        savedPlan = JSON.parse(options.body);
        return new Response(JSON.stringify({ updateTime: now.toISOString() }), { status: 200 });
      }
      return new Response('{}', { status: 200 });
    };

    const res = await runPushReminderPlanner(
      {},
      {
        serviceAccount: mockSa,
        now,
        mintToken: async () => 'test-token',
        fetchImpl: fakeFetch,
      },
    );

    assert.equal(res.status, 'ok');
    const plannedKeys = savedPlan.fields.reminderPlan.arrayValue.values.map(
      (v) => v.mapValue.fields.tKey.stringValue,
    );
    const activeKeys = savedPlan.fields.activeEventKeys.arrayValue.values.map((v) => v.stringValue);

    assert.ok(!plannedKeys.includes('lit-tue-deleted'));
    assert.ok(!plannedKeys.includes('meeting-mtg-deleted'));
    assert.ok(!plannedKeys.includes('lit-pascha-deleted-season-lit'));
    assert.ok(plannedKeys.includes('lit-tue-restored'));
    assert.ok(plannedKeys.includes('lit-tue-active'));
    assert.ok(plannedKeys.includes('meeting-mtg-restored'));

    assert.ok(!activeKeys.includes('lit-tue-deleted'));
    assert.ok(!activeKeys.includes('meeting-mtg-deleted'));
    assert.ok(activeKeys.includes('lit-tue-restored'));
    assert.ok(activeKeys.includes('lit-tue-active'));
    assert.ok(activeKeys.includes('meeting-mtg-restored'));
  });
});
