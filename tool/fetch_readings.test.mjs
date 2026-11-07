import test from 'node:test';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
import { BIBLE_BOOKS_EN, parseKatamerosDay } from './fetch_readings.js';

test('BIBLE_BOOKS_EN contains all 66 canonical books', () => {
  assert.equal(Object.keys(BIBLE_BOOKS_EN).length, 66);
  assert.equal(BIBLE_BOOKS_EN[1], 'Genesis');
  assert.equal(BIBLE_BOOKS_EN[19], 'Psalms');
  assert.equal(BIBLE_BOOKS_EN[40], 'Matthew');
  assert.equal(BIBLE_BOOKS_EN[42], 'Luke');
  assert.equal(BIBLE_BOOKS_EN[44], 'Acts');
  assert.equal(BIBLE_BOOKS_EN[45], 'Romans');
  assert.equal(BIBLE_BOOKS_EN[62], '1 John');
  assert.equal(BIBLE_BOOKS_EN[66], 'Revelation');
});

test('parseKatamerosDay transforms raw API structure into DayReadings JSON', () => {
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
                conclusion: 'والمجد لله دائما',
                passages: [
                  {
                    bookId: 42,
                    bookTranslation: 'لوقا',
                    chapter: 7,
                    ref: '7:36-50',
                    verses: [
                      { number: 36, text: 'وَسَأَلَهُ وَاحِدٌ مِنَ ٱلْفَرِّيسِيِّينَ' },
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
        title: 'قداس',
        subSections: [
          {
            id: 3,
            title: 'البولس',
            readings: [
              {
                id: 301,
                title: null,
                introduction: 'فصل من رسالة بولس',
                conclusion: 'نعمة الله معكم',
                passages: [
                  {
                    bookId: 45,
                    bookTranslation: 'رومية',
                    chapter: 3,
                    ref: '3:1-31',
                    verses: [
                      { number: 1, text: 'إِذًا مَا هُوَ فَضْلُ ٱلْيَهُودِيِّ' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            id: 10,
            title: 'السنكسار',
            readings: [
              {
                id: 1001,
                title: 'تذكار القديسين',
                introduction: null,
                conclusion: null,
                passages: null,
                html: '<p>في مثل هذا اليوم تنيح القديس.</p><p>بركته معنا.</p>',
              },
            ],
          },
        ],
      },
    ],
  };

  const testDate = new Date('2026-11-08T00:00:00Z');
  const result = parseKatamerosDay(fixture, testDate);

  assert.equal(result.date, '2026-11-08');
  assert.equal(result.coptic, '29/2/1743'); // fallback computed from copticDateOf
  assert.equal(result.titleAr, 'تذكار الأعياد السيدية');
  assert.equal(result.source, 'api.katameros.app');
  assert.equal(result.bibleAr, 'Van Dyck');
  assert.equal(result.bibleEn, 'refs-only');

  assert.equal(result.sections.length, 2);
  const vespers = result.sections[0];
  assert.equal(vespers.key, 'vespers');
  assert.equal(vespers.titleAr, 'العشية');
  assert.equal(vespers.titleEn, 'Vespers');
  assert.equal(vespers.readings.length, 2);

  // Psalm
  const psalm = vespers.readings[0];
  assert.equal(psalm.kind, 'psalm');
  assert.equal(psalm.titleAr, 'المزمور');
  assert.equal(psalm.titleEn, 'Psalm');
  assert.equal(psalm.refAr, 'مزامير 144:5,7');
  assert.equal(psalm.refEn, 'Psalms 144:5,7');
  assert.equal(psalm.textAr, 'يَارَبُّ، طَأْطِئْ سَمَاوَاتِكَ أَرْسِلْ يَدَكَ مِنَ ٱلْعَلَاءِ');
  assert.equal(psalm.textEn, '');
  assert.equal(psalm.introAr, 'مزمور لداود');
  assert.equal(psalm.conclusionAr, 'هللويا');

  // Gospel
  const gospel = vespers.readings[1];
  assert.equal(gospel.kind, 'gospel');
  assert.equal(gospel.titleAr, 'الإنجيل');
  assert.equal(gospel.titleEn, 'Gospel');
  assert.equal(gospel.refAr, 'لوقا 7:36-50');
  assert.equal(gospel.refEn, 'Luke 7:36-50');
  assert.equal(gospel.textAr, 'وَسَأَلَهُ وَاحِدٌ مِنَ ٱلْفَرِّيسِيِّينَ');

  // Liturgy
  const liturgy = result.sections[1];
  assert.equal(liturgy.key, 'liturgy');
  assert.equal(liturgy.readings.length, 2);

  const pauline = liturgy.readings[0];
  assert.equal(pauline.kind, 'pauline');
  assert.equal(pauline.refEn, 'Romans 3:1-31');

  const synaxarium = liturgy.readings[1];
  assert.equal(synaxarium.kind, 'synaxarium');
  assert.equal(synaxarium.titleAr, 'تذكار القديسين');
  assert.equal(synaxarium.titleEn, 'Synaxarium');
  assert.equal(synaxarium.textAr, 'في مثل هذا اليوم تنيح القديس. بركته معنا.');

  // Check JSON size constraints
  const json = JSON.stringify(result);
  const gz = zlib.gzipSync(json);
  assert.ok(json.length < 25000, `JSON length (${json.length}) should be under 25KB`);
  assert.ok(gz.length < 25000, `Gzip length (${gz.length}) should be under 25KB`);
});
