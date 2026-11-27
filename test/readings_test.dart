import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/readings.dart';
import 'package:church_portal/data/readings_store.dart';
import 'package:church_portal/state/notify_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleFixture = {
    'date': '2026-11-08',
    'coptic': '29/2/1743',
    'titleAr': 'تذكار الأعياد الثلاثة السيدية',
    'titleEn': 'Feast of the Three Major Feasts',
    'sections': [
      {
        'key': 'vespers',
        'titleAr': 'العشية',
        'titleEn': 'Vespers',
        'readings': [
          {
            'kind': 'psalm',
            'titleAr': 'المزمور',
            'titleEn': 'Psalm',
            'refAr': 'مزامير 144:5,7',
            'refEn': 'Psalms 144:5,7',
            'introAr': 'مزمور لداود',
            'introEn': '',
            'textAr': 'يَارَبُّ، طَأْطِئْ سَمَاوَاتِكَ',
            'textEn': '',
            'conclusionAr': 'هللويا',
            'conclusionEn': '',
          },
          {
            'kind': 'gospel',
            'titleAr': 'الإنجيل',
            'titleEn': 'Gospel',
            'refAr': 'لوقا 7:36-50',
            'refEn': 'Luke 7:36-50',
            'introAr': '',
            'introEn': '',
            'textAr': 'وَسَأَلَهُ وَاحِدٌ مِنَ ٱلْفَرِّيسِيِّينَ',
            'textEn': '',
            'conclusionAr': '',
            'conclusionEn': '',
          },
        ],
      },
      {
        'key': 'liturgy',
        'titleAr': 'قداس',
        'titleEn': 'Liturgy',
        'readings': [
          {
            'kind': 'pauline',
            'titleAr': 'البولس',
            'titleEn': 'Pauline Epistle',
            'refAr': 'رومية 3:1-31',
            'refEn': 'Romans 3:1-31',
            'introAr': 'فصل من رسالة بولس',
            'introEn': '',
            'textAr': 'إِذًا مَا هُوَ فَضْلُ ٱلْيَهُودِيِّ',
            'textEn': '',
            'conclusionAr': '',
            'conclusionEn': '',
          },
          {
            'kind': 'gospel',
            'titleAr': 'الإنجيل',
            'titleEn': 'Gospel',
            'refAr': 'يوحنا 15:1-12',
            'refEn': 'John 15:1-12',
            'introAr': '',
            'introEn': '',
            'textAr': 'أَنَا ٱلْكَرْمَةُ ٱلْحَقِيقِيَّةُ',
            'textEn': '',
            'conclusionAr': '',
            'conclusionEn': '',
          },
        ],
      },
    ],
    'source': 'api.katameros.app',
    'bibleAr': 'Van Dyck',
    'bibleEn': 'refs-only',
  };

  group('DayReadings model', () {
    test('parses full fixture correctly', () {
      final readings = DayReadings.fromJson(sampleFixture);
      expect(readings.date, '2026-11-08');
      expect(readings.coptic, '29/2/1743');
      expect(readings.title(true), 'تذكار الأعياد الثلاثة السيدية');
      expect(readings.title(false), 'Feast of the Three Major Feasts');
      expect(readings.sections.length, 2);

      final vespers = readings.sections[0];
      expect(vespers.key, 'vespers');
      expect(vespers.readings.length, 2);
      expect(vespers.readings[0].kind, 'psalm');
      expect(vespers.readings[0].refAr, 'مزامير 144:5,7');
      expect(vespers.readings[0].refEn, 'Psalms 144:5,7');

      final liturgy = readings.sections[1];
      expect(liturgy.key, 'liturgy');
      expect(liturgy.readings[1].kind, 'gospel');
      expect(liturgy.readings[1].refEn, 'John 15:1-12');

      // Liturgy gospel getter
      final liturgyGospel = readings.liturgyGospel;
      expect(liturgyGospel, isNotNull);
      expect(liturgyGospel!.refAr, 'يوحنا 15:1-12');
      expect(liturgyGospel.refEn, 'John 15:1-12');
    });

    test('tolerates missing and malformed fields', () {
      final empty = DayReadings.fromJson({});
      expect(empty.date, '');
      expect(empty.coptic, '');
      expect(empty.sections, isEmpty);
      expect(empty.liturgyGospel, isNull);
    });

    test('toJson roundtrip preserves data', () {
      final original = DayReadings.fromJson(sampleFixture);
      final json = original.toJson();
      final roundtrip = DayReadings.fromJson(json);

      expect(roundtrip.date, original.date);
      expect(roundtrip.sections.length, original.sections.length);
      expect(roundtrip.sections[0].readings.length, original.sections[0].readings.length);
      expect(roundtrip.sections[0].readings[0].refEn, original.sections[0].readings[0].refEn);
    });
  });

  group('ReadingsStore', () {
    test('returns cached readings without network call', () async {
      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-11-08': jsonEncode(sampleFixture),
      });
      final store = ReadingsStore();

      final result = await store.getReadings('2026-11-08');
      expect(result, isNotNull);
      expect(result!.date, '2026-11-08');
      expect(result.sections.length, 2);
    });

    test('prunes cached dates older than yesterday', () async {
      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-11-05': jsonEncode(sampleFixture),
        'church_portal_readings_2026-11-06': jsonEncode(sampleFixture),
        'church_portal_readings_2026-11-07': jsonEncode(sampleFixture),
        'church_portal_readings_2026-11-08': jsonEncode(sampleFixture),
      });

      final store = ReadingsStore();
      final removed = await store.pruneOldReadings('2026-11-07');
      expect(removed, 2); // 11-05 and 11-06 removed

      final remaining = await store.listCachedDates();
      expect(remaining, ['2026-11-07', '2026-11-08']);
    });

    test('getReadings times out stalled HTTP request after 8 s and falls back cleanly', () async {
      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-11-08': jsonEncode(sampleFixture),
      });
      await SharedPreferences.getInstance();

      fakeAsync((async) {
        final neverCompletes = Completer<http.Response>();
        final store = ReadingsStore(client: MockClient((_) => neverCompletes.future));

        DayReadings? cachedFallback;
        var resolvedCached = false;
        store.getReadings('2026-11-08', forceFetch: true).then((v) {
          cachedFallback = v;
          resolvedCached = true;
        });

        DayReadings? missingResult;
        var resolvedMissing = false;
        store.getReadings('2026-11-09').then((v) {
          missingResult = v;
          resolvedMissing = true;
        });

        async.elapse(const Duration(seconds: 7));
        expect(resolvedCached, isFalse);
        expect(resolvedMissing, isFalse);

        async.elapse(const Duration(seconds: 1, milliseconds: 10));
        expect(resolvedCached, isTrue);
        expect(cachedFallback?.date, '2026-11-08');
        expect(resolvedMissing, isTrue);
        expect(missingResult, isNull);
      });
    });

    test('prefetchUpcomingDays fetches 7 Cairo days and prunes older than yesterday at 18:30 & 23:30 EEST',
        () async {
      CairoTime.ensureInitialized();
      // 2026-07-15 23:30 EEST (UTC+3) = 2026-07-15 20:30Z -> still 2026-07-15 in Cairo (#135),
      // while also post-18:00 (#112). Also seed pre-cached 2026-07-16 to prove missing-only fetch.
      final fixtureFor = (String iso) => {...sampleFixture, 'date': iso};
      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-07-13': jsonEncode(fixtureFor('2026-07-13')), // older than yesterday -> pruned
        'church_portal_readings_2026-07-14': jsonEncode(fixtureFor('2026-07-14')), // yesterday -> kept
        'church_portal_readings_2026-07-16': jsonEncode(fixtureFor('2026-07-16')), // already cached -> skipped
      });

      final requestedDates = <String>[];
      final store = ReadingsStore(
        client: MockClient((req) async {
          final name = req.url.pathSegments.last;
          final iso = name.replaceAll('.json', '');
          requestedDates.add(iso);
          return http.Response.bytes(utf8.encode(jsonEncode(fixtureFor(iso))), 200);
        }),
      );

      await store.prefetchUpcomingDays(
        todayCairo: DateTime.utc(2026, 7, 15, 20, 30),
        days: 7,
      );

      expect(requestedDates, [
        '2026-07-15',
        '2026-07-17',
        '2026-07-18',
        '2026-07-19',
        '2026-07-20',
        '2026-07-21',
      ]);
      expect(await store.listCachedDates(), [
        '2026-07-14',
        '2026-07-15',
        '2026-07-16',
        '2026-07-17',
        '2026-07-18',
        '2026-07-19',
        '2026-07-20',
        '2026-07-21',
      ]);

      // Also verify post-18:00 UTC-vs-Cairo midnight rollover: 2026-07-15 21:15Z == 2026-07-16 00:15 EEST.
      requestedDates.clear();
      await executeReadingsPrefetchTask(
        now: DateTime.utc(2026, 7, 15, 21, 15),
        store: store,
      );
      expect(requestedDates, ['2026-07-22']);
      expect(await store.listCachedDates(), isNot(contains('2026-07-14')));
    });
  });
}
