import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_portal/domain/readings.dart';
import 'package:church_portal/data/readings_store.dart';

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
  });
}
