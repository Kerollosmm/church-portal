import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import {
  calculateLiturgicalRolloverDate,
  formatDdMmYyyy,
  copticDateOfIso,
  parseKatamerosDay,
  countReadingsAndSynaxarium,
  syncDailyReadingsAndSynaxarium,
} from './readings_syncer.js';
import { _resetL1TokenCacheForTesting } from './firestore_rest.js';

test('calculateLiturgicalRolloverDate: rolls over at 18:00 Cairo time (16:00 UTC in standard time)', () => {
  // Before rollover (15:59:59 UTC -> 17:59:59 Cairo)
  const dBefore = new Date('2026-11-11T15:59:59Z');
  assert.equal(calculateLiturgicalRolloverDate(dBefore), '2026-11-11');

  // Exact rollover (16:00:00 UTC -> 18:00:00 Cairo)
  const dAt = new Date('2026-11-11T16:00:00Z');
  assert.equal(calculateLiturgicalRolloverDate(dAt), '2026-11-12');

  // After rollover (16:30:00 UTC -> 18:30:00 Cairo)
  const dAfter = new Date('2026-11-11T16:30:00Z');
  assert.equal(calculateLiturgicalRolloverDate(dAfter), '2026-11-12');
});

test('formatDdMmYyyy formats ISO date to Katameros API format', () => {
  assert.equal(formatDdMmYyyy('2026-11-12'), '12-11-2026');
  assert.equal(formatDdMmYyyy('2027-01-07'), '07-01-2027');
});

test('copticDateOfIso computes accurate Coptic calendar date', () => {
  // 8 Nov 2026 is 29 Paopi 1743 (29/2/1743)
  assert.equal(copticDateOfIso('2026-11-08'), '29/2/1743');
});

test('parseKatamerosDay transforms raw API structure into DayReadings JSON preserving tashkeel', () => {
  const fixture = {
    title: 'تذكار الأعياد السيدية',
    copticDate: null,
    sections: [
      {
        id: 1,
        title: 'العشية',
        subSections: [
          {
            id: 1,
            title: 'المزمور والإنجيل',
            readings: [
              {
                id: 101,
                title: null,
                introduction: 'مزمور لداود',
                conclusion: 'هللويا',
                passages: [
                  {
                    bookId: 19,
                    bookTranslation: 'مزامير',
                    chapter: 144,
                    ref: '144:5,7',
                    verses: [
                      { number: 5, text: 'يَارَبُّ، طَأْطِئْ سَمَاوَاتِكَ' },
                      { number: 7, text: 'أَرْسِلْ يَدَكَ مِنَ ٱلْعَلَاءِ' },
                    ],
                  },
                ],
              },
              {
                id: 102,
                title: null,
                introduction: 'من إنجيل لوقا',
                conclusion: 'والمجد لله دائماً',
                passages: [
                  {
                    bookId: 42,
                    bookTranslation: 'لوقا',
                    chapter: 12,
                    ref: '12:32-44',
                    verses: [
                      { number: 32, text: 'لَا تَخَفْ، أَيُّهَا ٱلْقَطِيعُ ٱلصَّغِيرُ' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
      {
        id: 3,
        title: 'القداس',
        subSections: [
          {
            id: 10,
            title: 'السنكسار',
            readings: [
              {
                id: 301,
                title: 'تذكار رئيس الملائكة ميخائيل',
                introduction: '',
                conclusion: '',
                passages: [],
                html: '<p>في مثل هذا اليوم تُعيّد الكنيسة بتذكار الملاك ميخائيل.</p>',
              },
            ],
          },
        ],
      },
    ],
  };

  const parsed = parseKatamerosDay(fixture, '2026-11-12');
  assert.equal(parsed.date, '2026-11-12');
  assert.equal(parsed.coptic, '3/3/1743'); // Fallback computed date
  assert.equal(parsed.titleAr, 'تذكار الأعياد السيدية');
  assert.equal(parsed.sections.length, 2);

  // Vespers section
  const vespers = parsed.sections[0];
  assert.equal(vespers.key, 'vespers');
  assert.equal(vespers.readings.length, 2);
  assert.equal(vespers.readings[0].kind, 'psalm');
  assert.equal(vespers.readings[0].refEn, 'Psalms 144:5,7');
  assert.equal(vespers.readings[0].textAr, 'يَارَبُّ، طَأْطِئْ سَمَاوَاتِكَ أَرْسِلْ يَدَكَ مِنَ ٱلْعَلَاءِ');
  assert.equal(vespers.readings[1].kind, 'gospel');
  assert.equal(vespers.readings[1].refEn, 'Luke 12:32-44');

  // Liturgy Synaxarium
  const liturgy = parsed.sections[1];
  assert.equal(liturgy.key, 'liturgy');
  assert.equal(liturgy.readings[0].kind, 'synaxarium');
  assert.equal(liturgy.readings[0].titleAr, 'تذكار رئيس الملائكة ميخائيل');
  assert.equal(liturgy.readings[0].textAr, 'في مثل هذا اليوم تُعيّد الكنيسة بتذكار الملاك ميخائيل.');

  const counts = countReadingsAndSynaxarium(parsed);
  assert.equal(counts.readingsCount, 3);
  assert.equal(counts.synaxariumCount, 1);
});

test('syncDailyReadingsAndSynaxarium: skips duplicate write when KV already has fresh data', async () => {
  const cachedData = {
    date: '2026-11-12',
    sections: [{ key: 'liturgy', readings: [{ kind: 'gospel' }, { kind: 'synaxarium' }] }],
  };

  const mockKv = {
    get: async (key) => (key === 'reading:2026-11-12' ? cachedData : null),
    put: async () => assert.fail('Should not write to KV when already cached'),
  };

  const res = await syncDailyReadingsAndSynaxarium(
    { PUSH_KV: mockKv },
    { targetDate: '2026-11-12' }
  );

  assert.equal(res.status, 'skipped');
  assert.equal(res.date, '2026-11-12');
  assert.equal(res.readingsCount, 2);
  assert.equal(res.synaxariumCount, 1);
});

test('syncDailyReadingsAndSynaxarium: handles unreachable Katameros API gracefully', async () => {
  const mockFetch = async () => new Response('Internal Server Error', { status: 500 });
  const mockKv = {
    get: async () => null,
    put: async () => {},
  };

  const res = await syncDailyReadingsAndSynaxarium(
    { PUSH_KV: mockKv },
    {
      targetDate: '2026-11-12',
      fetchImpl: mockFetch,
    }
  );

  assert.equal(res.status, 'error');
  assert.equal(res.date, '2026-11-12');
  assert.ok(res.error.includes('Katameros API failed (500)'));
});

test('syncDailyReadingsAndSynaxarium: executes full sync to Firestore and KV on fresh date', async () => {
  _resetL1TokenCacheForTesting();

  const { privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });

  const validSa = {
    project_id: 'test-project',
    client_email: 'test@serviceaccount.com',
    private_key: privateKey,
  };

  const rawApiFixture = {
    title: 'تذكار سنوي',
    copticDate: '3/3/1743',
    sections: [
      {
        id: 3,
        title: 'القداس',
        subSections: [
          {
            id: 1,
            title: 'المزمور والإنجيل',
            readings: [
              {
                id: 1,
                title: 'المزمور',
                passages: [{ bookId: 19, ref: '23:1', verses: [{ text: 'الرب راعي' }] }],
              },
            ],
          },
        ],
      },
    ],
  };

  let writtenDocUrl = null;
  let writtenDocBody = null;
  let kvPutKey = null;
  let kvPutVal = null;
  let kvTtl = null;

  const mockFetch = async (url, options) => {
    if (url.includes('api.katameros.app')) {
      return new Response(JSON.stringify(rawApiFixture), { status: 200 });
    }
    if (url.includes('oauth2.googleapis.com')) {
      return new Response(JSON.stringify({ access_token: 'fake_access_token' }), { status: 200 });
    }
    if (url.includes('firestore.googleapis.com')) {
      writtenDocUrl = url;
      writtenDocBody = JSON.parse(options.body);
      return new Response(JSON.stringify({ fields: writtenDocBody.fields }), { status: 200 });
    }
    return new Response('Not found', { status: 404 });
  };

  const mockKv = {
    get: async () => null,
    put: async (k, v, opts) => {
      kvPutKey = k;
      kvPutVal = JSON.parse(v);
      kvTtl = opts?.expirationTtl;
    },
  };

  const res = await syncDailyReadingsAndSynaxarium(
    {
      PUSH_KV: mockKv,
      FIREBASE_PROJECT_ID: 'test-project',
      FIREBASE_SERVICE_ACCOUNT: JSON.stringify(validSa),
    },
    {
      targetDate: '2026-11-12',
      fetchImpl: mockFetch,
    }
  );

  assert.equal(res.status, 'ok');
  assert.equal(res.date, '2026-11-12');
  assert.equal(res.readingsCount, 1);
  assert.equal(res.synaxariumCount, 0);

  // Check Firestore write
  assert.ok(writtenDocUrl.includes('/projects/test-project/databases/(default)/documents/readings/2026-11-12'));
  assert.equal(writtenDocBody.fields.date.stringValue, '2026-11-12');
  assert.equal(writtenDocBody.fields.titleAr.stringValue, 'تذكار سنوي');

  // Check KV write
  assert.equal(kvPutKey, 'reading:2026-11-12');
  assert.equal(kvPutVal.date, '2026-11-12');
  assert.equal(kvPutVal.titleAr, 'تذكار سنوي');
  assert.equal(kvTtl, 7 * 86400);
});
