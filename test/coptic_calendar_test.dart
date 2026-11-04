// ADR-039 / ADR-040: Coptic calendar engine, liturgical day, sunset, feast
// list, top event of the day, live banner, today.json parsing.
// Reference dates: api.katameros.app (copticDate / feast titles, read
// 2026-11-04) and timeanddate.com (Alexandria sunsets) — docs/CONTENT_SOURCES.md.
import 'dart:convert';

import 'package:church_portal/data/synaxarium_source.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/coptic_calendar.dart';
import 'package:church_portal/domain/coptic_feasts.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/sun.dart';
import 'package:church_portal/domain/today.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

/// A Cairo wall-clock instant.
DateTime cairo(int y, int m, int day, int h, [int min = 0]) => CairoTime.at(y, m, day, h * 60 + min);

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('Gregorian <-> Coptic', () {
    const known = {
      '2026-09-11': CopticDate(1743, 1, 1), // Nayrouz 1743
      '2026-09-27': CopticDate(1743, 1, 17), // Feast of the Cross
      '2026-11-04': CopticDate(1743, 2, 25), // katameros: 25/2/1743
      '2027-01-07': CopticDate(1743, 4, 29), // Nativity = 29 Kiahk
      '2027-04-19': CopticDate(1743, 8, 11), // katameros: 11/8/1743
      '2027-06-10': CopticDate(1743, 10, 3), // katameros: 3/10/1743 (Ascension)
      '2027-08-19': CopticDate(1743, 12, 13), // Transfiguration
      '2027-08-22': CopticDate(1743, 12, 16), // Assumption
      '2027-09-11': CopticDate(1743, 13, 6), // leap year: 6th day of Nasie
      '2027-09-12': CopticDate(1744, 1, 1), // Nayrouz 1744 on 12 Sep
      '2028-01-07': CopticDate(1744, 4, 28), // Nativity = 28 Kiahk that year
      '2028-01-20': CopticDate(1744, 5, 11), // Theophany = 11 Touba
    };
    for (final e in known.entries) {
      test('${e.key} = ${e.value}', () {
        final g = DateTime.parse('${e.key}T00:00:00Z');
        expect(CopticDate.fromGregorian(g), e.value);
        expect(e.value.toGregorian(), g);
      });
    }

    test('round trip over 1900-2100 and leap years', () {
      expect(CopticDate.isLeapYear(1743), isTrue);
      expect(CopticDate.isLeapYear(1744), isFalse);
      expect(CopticDate.daysInMonth(1743, 13), 6);
      expect(CopticDate.daysInMonth(1742, 13), 5);
      for (var g = d(1900, 1, 1); g.isBefore(d(2100, 1, 1)); g = g.add(const Duration(days: 13))) {
        final c = CopticDate.fromGregorian(g);
        expect(c.toGregorian(), g);
        expect(c.day, inInclusiveRange(1, CopticDate.daysInMonth(c.year, c.month)));
      }
    });

    test('formatting', () {
      const c = CopticDate(1743, 2, 25);
      expect(c.format(arabic: true), '٢٥ بابه ١٧٤٣ ش');
      expect(c.format(arabic: false), '25 Baba 1743 AM');
    });
  });

  group('liturgical day', () {
    test('fixed 18:00 by default: rolls at 18:00, eve label', () {
      final before = liturgicalDayAt(cairo(2026, 11, 4, 17, 59));
      expect(before.date, d(2026, 11, 4));
      expect(before.isEve, isFalse);
      expect(before.label(arabic: true), 'الأربعاء ٢٥ بابه ١٧٤٣ ش');
      final after = liturgicalDayAt(cairo(2026, 11, 4, 18));
      expect(after.date, d(2026, 11, 5));
      expect(after.civilDate, d(2026, 11, 4));
      expect(after.isEve, isTrue);
      expect(after.label(arabic: true), 'ليلة الخميس ٢٦ بابه ١٧٤٣ ش');
      expect(after.label(arabic: false), 'Eve of Thursday 26 Baba 1743 AM');
      expect(liturgicalDayAt(cairo(2026, 11, 5, 0, 30)).date, d(2026, 11, 5));
    });

    test('summer time (EEST) keeps the wall clock', () {
      expect(liturgicalDayAt(cairo(2027, 7, 1, 17, 59)).date, d(2027, 7, 1));
      expect(liturgicalDayAt(cairo(2027, 7, 1, 18, 0)).date, d(2027, 7, 2));
    });

    test('admin fixed time and midnight', () {
      expect(liturgicalDayAt(cairo(2026, 11, 4, 19), fixedAt: '20:00').date, d(2026, 11, 4));
      expect(liturgicalDayAt(cairo(2026, 11, 4, 20), fixedAt: '20:00').date, d(2026, 11, 5));
      expect(liturgicalDayAt(cairo(2026, 11, 4, 23, 59), fixedAt: '00:00').date, d(2026, 11, 4));
      expect(dayStartMinutes(''), 18 * 60);
      expect(dayStartMinutes('25:00'), 18 * 60);
    });

    test('sunset mode uses the church coordinates', () {
      // Sunset in Alexandria on 4 Nov 2026 is 17:09 (timeanddate.com).
      expect(liturgicalDayAt(cairo(2026, 11, 4, 17, 5), mode: DayStartModes.sunset).date, d(2026, 11, 4));
      expect(liturgicalDayAt(cairo(2026, 11, 4, 17, 12), mode: DayStartModes.sunset).date, d(2026, 11, 5));
    });

    test('TodaySettings reads the mode, defaults to fixed', () {
      expect(TodaySettings.fromMap(const {}).dayStartMode, DayStartModes.fixed);
      expect(TodaySettings.fromMap(const {'dayStartMode': 'sunset'}).dayStartMode, DayStartModes.sunset);
      expect(TodaySettings.fromMap(const {'dayStartMode': 'x'}).dayStartMode, DayStartModes.fixed);
      const t = TodaySettings();
      expect(t.isEveService(cairo(2026, 11, 4, 19)), isTrue);
      expect(t.isEveService(cairo(2026, 11, 4, 7)), isFalse);
    });
  });

  group('sunset (NOAA)', () {
    // timeanddate.com, Alexandria, Nov 2026: 4th 5:09 pm, 20th 4:59 pm, 30th 4:57 pm.
    const ref = {'2026-11-04': 17 * 60 + 9, '2026-11-20': 16 * 60 + 59, '2026-11-30': 16 * 60 + 57};
    for (final e in ref.entries) {
      test('${e.key} within 2 minutes', () {
        final m = sunsetLocalMinutes(DateTime.parse('${e.key}T00:00:00Z'));
        expect((m - e.value).abs(), lessThanOrEqualTo(2));
      });
    }
    test('summer sunset is after 19:30 local (EEST)', () {
      expect(sunsetLocalMinutes(d(2027, 6, 21)), inInclusiveRange(19 * 60 + 55, 20 * 60 + 15));
    });
  });

  group('computed feasts', () {
    String first(DateTime x) => copticFeastsOn(x).first.en;
    test('fixed and movable feasts (checked against api.katameros.app)', () {
      expect(first(d(2026, 9, 11)), contains('Nayrouz'));
      expect(first(d(2026, 9, 27)), contains('Cross'));
      expect(first(d(2027, 1, 7)), contains('Nativity'));
      expect(first(d(2028, 1, 7)), contains('Nativity'));
      expect(first(d(2027, 1, 19)), contains('Theophany'));
      expect(first(d(2028, 1, 20)), contains('Theophany'));
      expect(first(d(2027, 4, 7)), contains('Annunciation'));
      expect(first(d(2027, 6, 1)), contains('Egypt'));
      expect(first(d(2027, 8, 19)), contains('Transfiguration'));
      expect(first(d(2027, 8, 22)), contains('Assumption'));
      // Coptic Easter 2027 = 2 May.
      expect(first(d(2027, 5, 2)), contains('Resurrection'));
      expect(first(d(2027, 4, 25)), 'Palm Sunday');
      expect(first(d(2027, 4, 30)), 'Good Friday');
      expect(first(d(2027, 6, 10)), contains('Ascension'));
      expect(first(d(2027, 6, 20)), contains('Pentecost'));
      expect(first(d(2027, 3, 8)), contains('Great Lent'));
      expect(first(d(2027, 2, 22)), contains('Nineveh'));
    });
    test('ordinary day: nothing', () {
      expect(copticFeastsOn(d(2026, 11, 4)), isEmpty);
    });
  });

  group('SynaxariumSource.load (device copy, one GET when needed)', () {
    String file(String day) => '{"days":{"$day":{"ar":["تذكار $day"],"en":["C $day"]}}}';

    test('stored copy lacks the day: one GET, fresh data returned and stored', () async {
      SharedPreferences.setMockInitialValues({SynaxariumSource.storeKey: file('2026-11-01')});
      var gets = 0;
      final src = SynaxariumSource(
        client: MockClient((r) async {
          gets++;
          return http.Response.bytes(utf8.encode(file('2026-11-04')), 200);
        }),
        prefs: SharedPreferences.getInstance,
      );
      final d = await src.load(DateTime.utc(2026, 11, 4));
      expect(gets, 1);
      expect(d.dayOf(DateTime.utc(2026, 11, 4))!.ar.single, 'تذكار 2026-11-04');
      expect((await SharedPreferences.getInstance()).getString(SynaxariumSource.storeKey), file('2026-11-04'));
    });

    test('stored copy covers the day: no GET', () async {
      SharedPreferences.setMockInitialValues({SynaxariumSource.storeKey: file('2026-11-04')});
      var gets = 0;
      final src = SynaxariumSource(
        client: MockClient((r) async {
          gets++;
          return http.Response('{}', 200);
        }),
        prefs: SharedPreferences.getInstance,
      );
      expect((await src.load(DateTime.utc(2026, 11, 4))).dayOf(DateTime.utc(2026, 11, 4)), isNotNull);
      expect(gets, 0);
    });

    test('non-200: the stored copy is returned', () async {
      SharedPreferences.setMockInitialValues({SynaxariumSource.storeKey: file('2026-11-01')});
      final src = SynaxariumSource(
        client: MockClient((r) async => http.Response('down', 503)),
        prefs: SharedPreferences.getInstance,
      );
      final d = await src.load(DateTime.utc(2026, 11, 4));
      expect(d.dayOf(DateTime.utc(2026, 11, 1)), isNotNull);
      expect(d.dayOf(DateTime.utc(2026, 11, 4)), isNull);
    });
  });

  group('top event of the day', () {
    final events = DayEvent.listFrom([
      '2026-11-04\u001f\u001f19:00\u001f21:00\u001fالليلة الرابعة من نهضة الشفعاء\u001fFourth night\u001fنيافة الأنبا X\u001f\u001fالتوبة\u001f\u001f\u001f\u001f/mass-schedule',
      '2026-11-05\u001f\u001f\u001f\u001fبصخة ليلة الخميس\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f',
      'garbage',
    ]);

    test('stored events parse; invalid ones are dropped', () {
      expect(events.length, 2);
      expect(events.first.speakerAr, 'نيافة الأنبا X');
      expect(events.first.link, '/mass-schedule');
    });

    test('a church event leads its day until it ends, then the next night', () {
      const s = TodaySettings();
      final morning = resolveTopEvent(now: cairo(2026, 11, 4, 9), settings: s, events: events)!;
      expect(morning.kind, TopEventKind.church);
      expect(morning.titleAr, contains('نهضة'));
      final late = resolveTopEvent(now: cairo(2026, 11, 4, 21, 30), settings: s, events: events)!;
      expect(late.titleAr, 'بصخة ليلة الخميس');
    });

    test('an overnight event (22:00–02:00) stays listed after midnight until it ends', () {
      final night = DayEvent.listFrom([
        '2026-11-04\u001f\u001f22:00\u001f02:00\u001fسهرة كيهكية\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f',
      ]);
      const s = TodaySettings(commemoration: false);
      expect(night.single.overnight, isTrue);
      expect(night.single.covers(DateTime.utc(2026, 11, 5)), isTrue);
      expect(resolveTopEvent(now: cairo(2026, 11, 4, 23), settings: s, events: night)!.titleAr, 'سهرة كيهكية');
      expect(resolveTopEvent(now: cairo(2026, 11, 5, 1, 30), settings: s, events: night)!.titleAr, 'سهرة كيهكية');
      expect(resolveTopEvent(now: cairo(2026, 11, 5, 2, 1), settings: s, events: night), isNull);
    });

    test('no event: Katameros, else computed feasts; switches', () {
      const s = TodaySettings();
      final syn = SynaxariumData.fromMap({
        'days': {
          '2026-11-06': {'ar': ['تذكار أ', 'تذكار ب', 'تذكار ج'], 'en': ['A', 'B', 'C']},
        },
      });
      final c = resolveTopEvent(now: cairo(2026, 11, 6, 9), settings: s, events: const [], synaxarium: syn)!;
      expect(c.kind, TopEventKind.commemoration);
      expect(c.fromKatameros, isTrue);
      expect(c.titleAr, 'تذكار أ');
      expect(c.linesAr, ['تذكار ب', 'تذكار ج']);
      // Computed fallback (Nativity), on the eve after 18:00 too.
      final n = resolveTopEvent(now: cairo(2027, 1, 6, 19), settings: s, events: const [])!;
      expect(n.titleEn, contains('Nativity'));
      expect(n.fromKatameros, isFalse);
      expect(resolveTopEvent(now: cairo(2027, 1, 7, 9), settings: const TodaySettings(commemoration: false), events: const []),
          isNull);
      expect(resolveTopEvent(now: cairo(2027, 1, 7, 9), settings: const TodaySettings(topEvent: false), events: events),
          isNull);
    });
  });

  group('settings in settings/features (no extra document)', () {
    test('FeatureSettings parses today keys and events, toMap never writes them', () {
      final f = FeatureSettings.fromMap({
        'copticStrip': 'home',
        'liveEnabled': true,
        'liveUrl': 'https://youtube.com/live/x',
        'dayEvents': ['2026-11-04\u001f\u001f\u001f\u001fحدث\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f'],
      });
      expect(f.today.copticStrip, 'home');
      expect(f.dayEvents.single.titleAr, 'حدث');
      for (final k in ['copticStrip', 'liveEnabled', 'liveUrl', 'dayEvents', 'dayStartMode']) {
        expect(f.toMap().containsKey(k), isFalse, reason: k);
      }
    });

    test('live banner: switch, link and optional switch-off time', () {
      final now = cairo(2026, 11, 4, 19);
      expect(const TodaySettings(liveEnabled: true, liveUrl: 'https://facebook.com/x').liveOn(now), isTrue);
      expect(const TodaySettings(liveEnabled: true).liveOn(now), isFalse);
      expect(const TodaySettings(liveEnabled: true, liveUrl: 'javascript:alert(1)').liveOn(now), isFalse);
      expect(const TodaySettings(liveUrl: 'https://facebook.com/x').liveOn(now), isFalse);
      expect(
          TodaySettings(liveEnabled: true, liveUrl: 'https://youtu.be/x', liveEndsAt: cairo(2026, 11, 4, 18)).liveOn(now),
          isFalse);
    });
  });

  test('verse of the day follows the liturgical day', () {
    final verses = [for (var i = 0; i < 366; i++) Verse(textAr: 'v$i', refAr: 'r$i')];
    final eve = cairo(2026, 11, 4, 19);
    final day = liturgicalDayAt(eve).date;
    expect(resolveDailyVerse(DailyVerseConfig.defaults, verses, eve, day: day), verseForDate(verses, d(2026, 11, 5)));
    expect(resolveDailyVerse(DailyVerseConfig.defaults, verses, eve), verseForDay(verses, eve));
  });

  test('today.json parse is tolerant', () {
    expect(SynaxariumSource.parse('not json').days, isEmpty);
    final p = SynaxariumSource.parse(
        '{"days":{"2026-11-04":{"coptic":"25/2/1743","feastAr":"","ar":["نياحة"],"en":["Departure"]},"bad":5}}');
    expect(p.dayOf(d(2026, 11, 4))!.ar, ['نياحة']);
    expect(p.days.length, 1);
  });
}
