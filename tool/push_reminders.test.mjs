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
});
