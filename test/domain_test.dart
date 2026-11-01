import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/rules.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

Liturgy lit(String id, int? weekday, String start, String end,
        {String type = 'mass', String? season, DateTime? date, int order = 0}) =>
    Liturgy(
        id: id,
        type: type,
        nameAr: id,
        nameEn: id,
        weekday: weekday,
        date: date,
        start: start,
        end: end,
        seasonKey: season,
        order: order);

/// Cairo wall time -> UTC instant (via the tz database).
DateTime cairo(int y, int mo, int d, int h, [int mi = 0]) => CairoTime.at(y, mo, d, h * 60 + mi).toUtc();

void main() {
  setUpAll(CairoTime.ensureInitialized);

  final regular = [
    lit('fri1', 5, '06:30', '08:30'),
    lit('fri2', 5, '08:30', '10:30'),
    lit('friKids', 5, '10:30', '12:00'),
    lit('sat1', 6, '07:00', '09:00'),
    lit('satVespers', 6, '18:30', '19:30', type: 'vespers'),
    lit('sun1', 7, '06:00', '08:00'),
    lit('wed1', 3, '07:00', '09:00'),
    lit('thu1', 4, '07:00', '08:30'),
  ];
  final nativity = Season(
    id: 'nat',
    key: 'nativity',
    nameAr: 'الميلاد',
    nameEn: 'Nativity',
    startsAt: cairo(2027, 1, 6, 0),
    endsAt: cairo(2027, 1, 8, 23, 59),
  );
  final seasonal = [
    lit('natEve', null, '20:00', '00:30', season: 'nativity', date: DateTime(2027, 1, 6)),
    lit('natDay', null, '08:00', '10:00', season: 'nativity', date: DateTime(2027, 1, 7)),
  ];
  final all = [...regular, ...seasonal];

  group('Cairo time zone', () {
    test('winter is UTC+2 and summer (DST) is UTC+3', () {
      expect(CairoTime.at(2026, 11, 6, 6 * 60 + 30).timeZoneOffset, const Duration(hours: 2));
      expect(CairoTime.at(2026, 7, 3, 6 * 60 + 30).timeZoneOffset, const Duration(hours: 3));
    });
  });

  group('next mass', () {
    test('during the first Friday liturgy -> happening now + next is the second', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2026, 11, 6, 7, 0));
      expect(r.happeningNow?.liturgy.id, 'fri1');
      expect(r.next?.liturgy.id, 'fri2');
      expect(r.next?.dayOffset, 0);
    });

    test('after the last liturgy today -> tomorrow\'s first', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2026, 11, 6, 21, 0));
      expect(r.happeningNow, isNull);
      expect(r.next?.liturgy.id, 'sat1');
      expect(r.next?.dayOffset, 1);
    });

    test('vespers are ignored by default but included on request', () {
      final now = cairo(2026, 11, 7, 12, 0);
      expect(computeNextMass(liturgies: all, seasons: const [], now: now).next?.liturgy.id, 'sun1');
      expect(
          computeNextMass(liturgies: all, seasons: const [], now: now, types: {'mass', 'vespers'}).next?.liturgy.id,
          'satVespers');
    });

    test('DST: summer Friday 06:30 Cairo is 03:30 UTC', () {
      final r = computeNextMass(liturgies: all, seasons: const [], now: cairo(2026, 7, 3, 6, 0));
      expect(r.next?.liturgy.id, 'fri1');
      expect(r.next!.start.toUtc(), DateTime.utc(2026, 7, 3, 3, 30));
    });

    test('skips days without liturgies (Monday night -> Wednesday)', () {
      // Mon 9 Nov 2026 22:00; Tuesday has none, Wednesday has wed1.
      final r = computeNextMass(liturgies: regular, seasons: const [], now: cairo(2026, 11, 9, 22));
      expect(r.next?.liturgy.id, 'wed1');
      expect(r.next?.dayOffset, 2);
    });

    test('active season replaces the regular liturgies of that day', () {
      // Wed 6 Jan 2027 05:00: regular wed1 (07:00) is replaced by the eve liturgy.
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'natEve');
      expect(r.activeSeasons.map((s) => s.key), ['nativity']);
    });

    test('a liturgy crossing midnight is happening now on both sides of midnight', () {
      expect(computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 6, 23, 30)).happeningNow?.liturgy.id,
          'natEve');
      final after = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 7, 0, 15));
      expect(after.happeningNow?.liturgy.id, 'natEve');
      expect(after.next?.liturgy.id, 'natDay');
    });

    test('inactive season flag is ignored', () {
      final off = Season(
          id: 'nat', key: 'nativity', nameAr: '', nameEn: '', startsAt: nativity.startsAt, endsAt: nativity.endsAt, active: false);
      final r = computeNextMass(liturgies: all, seasons: [off], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'wed1');
      expect(r.activeSeasons, isEmpty);
    });

    test('a season starting mid-day keeps the regular services before it', () {
      // Wed 13 Jan 2027: season from 18:00, seasonal service 19:00.
      final evening = Season(
        id: 'rev',
        key: 'revival_maximus',
        nameAr: '',
        nameEn: '',
        startsAt: cairo(2027, 1, 13, 18),
        endsAt: cairo(2027, 1, 14, 23, 59),
      );
      final ls = [...regular, lit('revEve', 3, '19:00', '20:30', type: 'mass', season: 'revival_maximus')];
      final morning = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 13, 5));
      expect(morning.next?.liturgy.id, 'wed1'); // regular 07:00 is before the season starts
      final afternoon = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 13, 12));
      expect(afternoon.next?.liturgy.id, 'revEve');
      // Thursday is fully inside the season but has no seasonal service -> regular.
      final thu = computeNextMass(liturgies: ls, seasons: [evening], now: cairo(2027, 1, 14, 5));
      expect(thu.next?.liturgy.id, 'thu1');
    });

    test('a seasonal service before its season starts is not used', () {
      final late = Season(
        id: 'n2',
        key: 'nativity',
        nameAr: '',
        nameEn: '',
        startsAt: cairo(2027, 1, 6, 21),
        endsAt: cairo(2027, 1, 7, 23, 59),
      );
      // natEve (20:00) starts before the 21:00 season start -> regular wed1 stays.
      final r = computeNextMass(liturgies: all, seasons: [late], now: cairo(2027, 1, 6, 5));
      expect(r.next?.liturgy.id, 'wed1');
    });

    test('regular days outside the season are unaffected', () {
      final r = computeNextMass(liturgies: all, seasons: [nativity], now: cairo(2027, 1, 9, 5)); // Saturday
      expect(r.next?.liturgy.id, 'sat1');
    });

    test('schedule tabs group weekdays and exclude vespers', () {
      expect(regularLiturgiesForTab(all, ScheduleTab.friday).map((l) => l.id), ['fri1', 'fri2', 'friKids']);
      expect(regularLiturgiesForTab(all, ScheduleTab.other).map((l) => l.id), ['thu1']);
      expect(regularLiturgiesForTab(all, ScheduleTab.saturday).map((l) => l.id), ['sat1']);
      expect(vespersAndPraise(all).map((l) => l.id), ['satVespers']);
      expect(seasonalSchedule([nativity], all)[nativity]!.map((l) => l.id), ['natEve', 'natDay']);
    });
  });

  group('additive revival seasons (replacesRegular: false)', () {
    // St Moses revival: 22 Jun – 1 Jul 2027, evening services every day, the
    // martyrdom-feast liturgy on Thursday 1 July.
    Season moses({bool replaces = false}) => Season(
          id: 'rev-moses',
          key: 'revival_moses',
          nameAr: 'نهضة الأنبا موسى',
          nameEn: 'St Moses revival',
          startsAt: cairo(2027, 6, 22, 0),
          endsAt: cairo(2027, 7, 1, 23, 59),
          replacesRegular: replaces,
        );
    final revival = [
      for (var wd = 1; wd <= 7; wd++) lit('revEve$wd', wd, '18:30', '21:00', type: 'other', season: 'revival_moses'),
      lit('revFeast', null, '06:30', '10:30', season: 'revival_moses', date: DateTime(2027, 7, 1)),
    ];
    final ls = [...regular, ...revival];

    test('regular Friday and Sunday morning masses continue during the revival', () {
      final fri = computeNextMass(liturgies: ls, seasons: [moses()], now: cairo(2027, 6, 25, 5));
      expect(fri.next?.liturgy.id, 'fri1');
      expect(fri.activeSeasons.map((s) => s.key), ['revival_moses']);
      final sun = computeNextMass(liturgies: ls, seasons: [moses()], now: cairo(2027, 6, 27, 5));
      expect(sun.next?.liturgy.id, 'sun1');
      // The first revival days (Tue 22 Jun) still find a mass within the week.
      expect(computeNextMass(liturgies: ls, seasons: [moses()], now: cairo(2027, 6, 22, 12)).next, isNotNull);
    });

    test('the feast-day mass supersedes the regular mass of that day', () {
      final day = CairoTime.at(2027, 7, 1);
      final ids = occurrencesForDay(liturgies: ls, seasons: [moses()], day: day, dayOffset: 0)
          .map((o) => o.liturgy.id)
          .toList();
      expect(ids, ['revFeast', 'revEve4']);
      expect(computeNextMass(liturgies: ls, seasons: [moses()], now: cairo(2027, 7, 1, 5)).next?.liturgy.id, 'revFeast');
    });

    test('overlapping evening vespers give way; the morning mass stays', () {
      final sat = CairoTime.at(2027, 6, 26);
      final ids = occurrencesForDay(liturgies: ls, seasons: [moses()], day: sat, dayOffset: 0)
          .map((o) => o.liturgy.id)
          .toList();
      expect(ids, ['sat1', 'revEve6']); // satVespers 18:30 overlaps the revival service
      // A vespers that does not overlap any revival service is kept.
      final early = [...ls, lit('satEarlyVespers', 6, '16:00', '17:00', type: 'vespers')];
      expect(
          occurrencesForDay(liturgies: early, seasons: [moses()], day: sat, dayOffset: 0).map((o) => o.liturgy.id),
          ['sat1', 'satEarlyVespers', 'revEve6']);
    });

    test('a full-override season still replaces the regular schedule', () {
      final fri = computeNextMass(liturgies: ls, seasons: [moses(replaces: true)], now: cairo(2027, 6, 25, 5));
      expect(fri.next?.liturgy.id, isNot('fri1'));
    });

    test('effectiveLiturgiesForDay matches occurrencesForDay', () {
      for (final season in [moses(), moses(replaces: true), nativity]) {
        for (final day in [
          CairoTime.at(2027, 6, 25),
          CairoTime.at(2027, 6, 26),
          CairoTime.at(2027, 7, 1),
          CairoTime.at(2027, 1, 6),
          CairoTime.at(2027, 1, 7),
        ]) {
          final lsAll = [...ls, ...seasonal];
          expect(
            effectiveLiturgiesForDay(liturgies: lsAll, seasons: [season], day: day).map((l) => l.id),
            occurrencesForDay(liturgies: lsAll, seasons: [season], day: day, dayOffset: 0).map((o) => o.liturgy.id),
            reason: '${season.key} $day',
          );
        }
      }
    });

    test('Season.replacesRegular defaults to true when absent', () {
      expect(Season.fromMap('s', {'key': 'nativity'}).replacesRegular, isTrue);
      expect(Season.fromMap('s', {'key': 'revival_moses', 'replacesRegular': false}).replacesRegular, isFalse);
      expect(Season.fromMap('s', {'key': 'pascha', 'replacesRegular': 'no'}).replacesRegular, isTrue);
    });
  });

  group('mass-schedule page lists', () {
    final now = cairo(2026, 12, 20, 12); // Sunday 20 Dec 2026
    test('upcomingSpecialLiturgies: dated, non-seasonal, from today, sorted', () {
      final ls = [
        ...regular,
        lit('past', null, '08:00', '10:00', date: DateTime(2026, 12, 19)),
        lit('todayLate', null, '18:00', '20:00', date: DateTime(2026, 12, 20)),
        lit('todayEarlyB', null, '07:00', '09:00', date: DateTime(2026, 12, 20), order: 2),
        lit('todayEarlyA', null, '07:00', '09:00', date: DateTime(2026, 12, 20), order: 1),
        lit('newYear', null, '22:00', '01:00', date: DateTime.utc(2026, 12, 31, 10)),
        lit('datedVespers', null, '18:00', '19:00', type: 'vespers', date: DateTime(2026, 12, 24)),
        ...seasonal,
      ];
      expect(upcomingSpecialLiturgies(ls, now).map((l) => l.id), ['todayEarlyA', 'todayEarlyB', 'todayLate', 'newYear']);
    });

    test('vespersAndPraise drops past one-off vespers but keeps the weekly ones', () {
      final ls = [
        ...regular,
        lit('oldVespers', null, '18:00', '19:00', type: 'vespers', date: DateTime(2026, 12, 1)),
        lit('nextVespers', null, '18:00', '19:00', type: 'praise', date: DateTime(2026, 12, 24)),
      ];
      expect(vespersAndPraise(ls, now: now).map((l) => l.id), ['nextVespers', 'satVespers']);
      expect(vespersAndPraise(ls).map((l) => l.id), containsAll(['oldVespers', 'nextVespers', 'satVespers']));
    });

    test('a one-off service running past midnight stays listed until it ends', () {
      final ls = [
        lit('nyeVespers', null, '22:00', '01:00', type: 'praise', date: DateTime(2026, 12, 31)),
        lit('nyeMass', null, '23:00', '02:00', date: DateTime(2026, 12, 31)),
        lit('noEnd', null, '23:30', '', type: 'vespers', date: DateTime(2026, 12, 31)), // default 2 h
      ];
      final at0030 = cairo(2027, 1, 1, 0, 30);
      expect(vespersAndPraise(ls, now: at0030).map((l) => l.id), ['nyeVespers', 'noEnd']);
      expect(upcomingSpecialLiturgies(ls, at0030).map((l) => l.id), ['nyeMass']);
      final at0115 = cairo(2027, 1, 1, 1, 15); // nyeVespers ended at 01:00, noEnd runs to 01:30
      expect(vespersAndPraise(ls, now: at0115).map((l) => l.id), ['noEnd']);
      expect(upcomingSpecialLiturgies(ls, at0115).map((l) => l.id), ['nyeMass']);
      final at0300 = cairo(2027, 1, 1, 3);
      expect(vespersAndPraise(ls, now: at0300), isEmpty);
      expect(upcomingSpecialLiturgies(ls, at0300), isEmpty);
    });

    test('seasonalSchedule skips inactive seasons', () {
      final off = Season(
          id: 'nat', key: 'nativity', nameAr: '', nameEn: '', startsAt: nativity.startsAt, endsAt: nativity.endsAt, active: false);
      expect(seasonalSchedule([off], all), isEmpty);
    });

    test('seasonalSchedule scopes dated services to their own year', () {
      final nat2028 = Season(
        id: 'nat28',
        key: 'nativity',
        nameAr: '',
        nameEn: '',
        startsAt: cairo(2028, 1, 6, 0),
        endsAt: cairo(2028, 1, 7, 23, 59),
      );
      final ls = [
        ...all,
        lit('natEve28', null, '20:00', '00:30', season: 'nativity', date: DateTime(2028, 1, 6)),
        lit('natWeekly', 5, '09:00', '10:00', season: 'nativity'), // weekday-based: every matching season
      ];
      final grouped = seasonalSchedule([nat2028, nativity], ls);
      expect(grouped.keys.map((s) => s.id), ['nat', 'nat28']);
      // Weekday-based services sort ahead of dated ones (unchanged order).
      expect(grouped[nativity]!.map((l) => l.id), ['natWeekly', 'natEve', 'natDay']);
      expect(grouped[nat2028]!.map((l) => l.id), ['natWeekly', 'natEve28']);
    });

    test('seasonalSchedule breaks equal start times by order', () {
      final ls = [
        lit('b', null, '08:00', '10:00', season: 'nativity', date: DateTime(2027, 1, 7), order: 2),
        lit('a', null, '08:00', '10:00', season: 'nativity', date: DateTime(2027, 1, 7), order: 1),
      ];
      expect(seasonalSchedule([nativity], ls)[nativity]!.map((l) => l.id), ['a', 'b']);
    });
  });

  group('assistant grounding', () {
    const settings = ChurchSettings(
      nameAr: 'كنيسة',
      nameEn: 'Church',
      addressAr: 'العصافرة',
      addressEn: '',
      transportAr: 'آخر شارع 45',
      historyAr: 'تاريخ الكنيسة',
      bishopAr: 'الأنبا بافلي',
    );
    final now = cairo(2026, 11, 1, 12);
    String build({FeatureSettings f = FeatureSettings.defaults, List<Season> seasons = const []}) =>
        buildAssistantInstruction(
          settings: settings,
          liturgies: [
            const Liturgy(id: 'x', type: 'mass', nameAr: 'قداس الجمعة', nameEn: '', weekday: 5, start: '07:00', end: '09:00',
                placeAr: 'الكنيسة الكبرى', audienceAr: 'للشباب'),
            const Liturgy(id: 's', type: 'other', nameAr: 'عشية النهضة', nameEn: '', weekday: 5, start: '18:00', end: '20:00',
                placeAr: 'مذبح الأنبا موسى', seasonKey: 'revival_moses'),
          ],
          seasons: seasons,
          clinics: const [
            Clinic(id: 'c', specialty: 'dental', specialtyAr: 'الأسنان', specialtyEn: '', doctorName: 'د. مينا', degreeAr: 'ماجستير',
                days: [5], whatsapp: '01012345678'),
          ],
          meetings: const [
            Meeting(id: 'm', stage: 'youth', nameAr: 'اجتماع الشباب', nameEn: '', start: '19:00', end: '20:00', hallAr: 'قاعة البابا',
                notes: 'يبدأ بعد العشية'),
          ],
          activities: const [
            Activity(id: 'a', category: 'choir', titleAr: 'الكورال', titleEn: '', descAr: 'خورس الكنيسة', scheduleAr: 'كل جمعة'),
          ],
          facilities: const [],
          now: now,
          features: f,
          alerts: [
            const Alert(id: 'al', titleAr: 'تنويه مهم', titleEn: '', bodyAr: 'تغيير المواعيد', active: true, priority: 1),
            const Alert(id: 'off', titleAr: 'قديم', titleEn: 'Old', active: false, priority: 9),
          ],
          priests: const [
            Priest(id: 'p', name: 'القمص بموا', nameEn: '', rank: 'hegumen', ordinationDate: '1998-03-21'),
            Priest(id: 'd', name: 'المتنيح القمص تادرس', nameEn: '', status: 'departed', departedDate: '2022-02-10'),
          ],
          saints: const [
            Saint(id: 'st', nameAr: 'الأنبا موسى الأسود', nameEn: 'St Moses the Black', feastGregorian: '1 July'),
          ],
        );

    test('Arabic-only admin entries are never blank', () {
      final t = build();
      expect(t, contains('Friday: قداس الجمعة [mass] 07:00 AM – 09:00 AM at الكنيسة الكبرى - للشباب'));
      expect(t, contains('Directions: آخر شارع 45'));
      expect(t, contains('الأسنان: د. مينا, ماجستير'));
      expect(t, contains('WhatsApp 01012345678'));
      expect(t, contains('اجتماع الشباب [youth]'));
      expect(t, contains('at قاعة البابا'));
      expect(t, contains('notes: يبدأ بعد العشية'));
      expect(t, contains('الكورال: خورس الكنيسة Schedule: كل جمعة.'));
      expect(t, isNot(contains(' at ;')));
      expect(t, isNot(contains(':  (')));
    });

    test('seasons say whether they replace or add to the regular schedule', () {
      final additive = Season(
          id: 'rm', key: 'revival_moses', nameAr: 'نهضة الأنبا موسى', nameEn: '', replacesRegular: false,
          startsAt: cairo(2027, 6, 22, 0), endsAt: cairo(2027, 7, 1, 23, 59));
      final t = build(seasons: [additive, nativity]);
      expect(t, contains('### نهضة الأنبا موسى'));
      expect(t, contains('[ADDITIVE — regular morning masses continue]'));
      expect(t, contains('- Friday: عشية النهضة [other] 06:00 PM – 08:00 PM at مذبح الأنبا موسى'));
      final off = build(seasons: [
        Season(id: 'rm', key: 'revival_moses', nameAr: 'x', nameEn: 'x', active: false, replacesRegular: false),
      ]);
      expect(off, isNot(contains('عشية النهضة')));
    });

    test('alerts, priests, departed priests, saints and history are grounded', () {
      final t = build();
      expect(t, contains('## Current announcements'));
      expect(t, contains('تنويه مهم: تغيير المواعيد'));
      expect(t, isNot(contains('Old')));
      expect(t, contains('## Priests serving the church'));
      expect(t, contains('القمص بموا (hegumen); ordained 1998-03-21'));
      expect(t, contains('## Departed priests of the church'));
      expect(t, contains('departed 2022-02-10'));
      expect(t, contains('St Moses the Black (الأنبا موسى الأسود); feast: 1 July'));
      expect(t, contains('Bishop: الأنبا بافلي'));
      expect(t, contains('History (summary): تاريخ الكنيسة'));
    });

    test('history and bios carry both languages when both are filled', () {
      final t = buildAssistantInstruction(
        settings: const ChurchSettings(
            nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: '', historyAr: 'تاريخ', historyEn: 'History text'),
        liturgies: const [],
        seasons: const [],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        now: now,
        priests: const [Priest(id: 'p', name: 'أبونا', nameEn: 'Fr X', bioAr: 'سيرة', bioEn: 'Bio')],
        saints: const [Saint(id: 's', nameAr: 'قديس', nameEn: 'Saint', bioAr: 'سيرة القديس', bioEn: 'Saint bio')],
      );
      expect(t, contains('History (summary): History text (تاريخ)'));
      expect(t, contains('Fr X (أبونا) (priest). Bio (سيرة)'));
      expect(t, contains('. Saint bio (سيرة القديس)'));
    });

    test('switched-off sections are not grounded', () {
      final t = build(
          f: FeatureSettings.fromMap({
        'sections': {'alerts': false, 'priests': false, 'departedPriests': false, 'saints': false, 'history': false},
      }));
      for (final h in ['## Current announcements', '## Priests', '## Departed priests', '## Patron saints', '## About the church']) {
        expect(t, isNot(contains(h)), reason: h);
      }
    });
  });

  group('alerts', () {
    final now = cairo(2026, 11, 1, 12);
    final alerts = [
      Alert(id: 'low', titleAr: '', titleEn: '', active: true, priority: 1, startsAt: cairo(2026, 10, 1, 0), endsAt: cairo(2026, 12, 1, 0)),
      Alert(id: 'high', titleAr: '', titleEn: '', active: true, priority: 5, startsAt: cairo(2026, 10, 30, 0), endsAt: cairo(2026, 11, 3, 0)),
      Alert(id: 'inactive', titleAr: '', titleEn: '', active: false, priority: 9),
      Alert(id: 'future', titleAr: '', titleEn: '', active: true, priority: 9, startsAt: cairo(2026, 12, 1, 0)),
      Alert(id: 'expired', titleAr: '', titleEn: '', active: true, priority: 9, endsAt: cairo(2026, 10, 1, 0)),
      const Alert(id: 'open', titleAr: '', titleEn: '', active: true, priority: 1),
    ];
    test('only active & in-window alerts, highest priority first', () {
      expect(visibleAlerts(alerts, now).map((a) => a.id), ['high', 'low', 'open']);
    });
  });

  group('clinics', () {
    final clinics = [
      const Clinic(id: 'd1', specialty: 'dental', specialtyAr: 'أسنان', specialtyEn: 'Dental', doctorName: 'B', days: [7]),
      const Clinic(id: 'p1', specialty: 'pediatrics', specialtyAr: 'أطفال', specialtyEn: 'Pediatrics', doctorName: 'A', days: [5, 7]),
      const Clinic(id: 'p2', specialty: 'pediatrics', specialtyAr: 'أطفال', specialtyEn: 'Pediatrics', doctorName: 'C', days: [1]),
      const Clinic(id: 'x', specialty: 'dental', specialtyAr: 'أسنان', specialtyEn: 'Dental', doctorName: 'Z', days: [5], active: false),
    ];
    final friday = cairo(2026, 11, 6, 9);
    test('available today uses the Cairo weekday', () {
      expect(isClinicAvailableToday(clinics[1], friday), isTrue);
      expect(isClinicAvailableToday(clinics[0], friday), isFalse);
      // 23:30 UTC Thursday is already Friday 01:30 in Cairo.
      expect(cairoWeekday(DateTime.utc(2026, 11, 5, 23, 30)), 5);
    });
    test('filter by specialty, hide inactive, open-today first', () {
      expect(filterClinics(clinics, now: friday).map((c) => c.id), ['p1', 'd1', 'p2']);
      expect(filterClinics(clinics, specialty: 'pediatrics', now: friday).map((c) => c.id), ['p1', 'p2']);
      expect(filterClinics(clinics, specialty: 'dental', now: friday).map((c) => c.id), ['d1']);
      // The admin's drag order wins after "open today".
      final ordered = [
        const Clinic(id: 'a', specialty: 'dental', specialtyAr: '', specialtyEn: '', doctorName: 'A', days: [5], order: 20),
        const Clinic(id: 'b', specialty: 'pediatrics', specialtyAr: '', specialtyEn: '', doctorName: 'B', days: [5], order: 10),
        const Clinic(id: 'c', specialty: 'ent', specialtyAr: '', specialtyEn: '', doctorName: 'C', days: [1], order: 5),
      ];
      expect(filterClinics(ordered, now: friday).map((c) => c.id), ['b', 'a', 'c']);
      expect(clinicSpecialties(clinics).keys, ['dental', 'pediatrics']);
    });
    test('links', () {
      expect(whatsappLink('0101 234 5678'), 'https://wa.me/201012345678');
      expect(whatsappLink('+20 101 234 5678'), 'https://wa.me/201012345678');
      expect(whatsappLink('٠١٠١٢٣٤٥٦٧٨'), 'https://wa.me/201012345678');
      expect(telLink('03 555 1234'), 'tel:035551234');
    });
  });

  group('contact form', () {
    test('valid with Arabic-digit mobile', () {
      final v = validateContactForm(const ContactFormInput(name: '  مينا  عادل ', phone: '٠١٢٢٣٤٥٦٧٨٩', message: 'أريد موعد القداس'));
      expect(v.isValid, isTrue);
      expect(v.payload!['name'], 'مينا عادل');
      expect(v.payload!['phone'], '01223456789');
    });
    test('valid with email only, landline and +20 forms', () {
      expect(validateContactForm(const ContactFormInput(name: 'Mina', email: 'mina@example.com', message: 'Hello there')).isValid, isTrue);
      expect(isValidEgyptianPhone('03 555 1234'), isTrue);
      expect(isValidEgyptianPhone('+201012345678'), isTrue);
      expect(isValidEgyptianPhone('0020 115 123 4567'), isTrue);
      expect(isValidEgyptianPhone('0131234567'), isFalse);
      expect(isValidEgyptianPhone('12345'), isTrue); // hotline
      expect(isValidEgyptianPhone('abc'), isFalse);
      // Bare 20 country prefix (no +) for landlines and mobiles.
      expect(normalizeEgyptianPhone('2035551234'), '035551234');
      expect(normalizeEgyptianPhone('20225551234'), '0225551234');
      expect(normalizeEgyptianPhone('201012345678'), '01012345678');
    });
    test('mobile vs landline', () {
      expect(isEgyptianMobile('0101 234 5678'), isTrue);
      expect(isEgyptianMobile('+201012345678'), isTrue);
      expect(isEgyptianMobile('03 555 1234'), isFalse);
      expect(isEgyptianMobile(''), isFalse);
    });
    test('errors', () {
      final v = validateContactForm(const ContactFormInput(name: 'M', message: 'hey'));
      expect(v.isValid, isFalse);
      expect(v.errors[ContactField.name], ContactError.nameLength);
      expect(v.errors[ContactField.contact], ContactError.phoneOrEmailRequired);
      expect(v.errors[ContactField.message], ContactError.messageLength);
      final v2 = validateContactForm(ContactFormInput(name: 'Mina', phone: '0123', email: 'bad@', message: 'x' * 1001));
      expect(v2.errors[ContactField.phone], ContactError.phoneInvalid);
      expect(v2.errors[ContactField.email], ContactError.emailInvalid);
      expect(v2.errors[ContactField.message], ContactError.messageLength);
      expect(v2.errors.containsKey(ContactField.contact), isFalse);
    });
    test('rate limiter', () {
      final rl = ContactRateLimiter();
      final t0 = DateTime(2026, 11, 1, 10);
      expect(rl.canSubmit(t0), isTrue);
      rl.recordSubmission(t0);
      expect(rl.canSubmit(t0.add(const Duration(seconds: 30))), isFalse);
      expect(rl.waitTime(t0.add(const Duration(seconds: 30))), const Duration(seconds: 30));
      rl.recordSubmission(t0.add(const Duration(minutes: 2)));
      rl.recordSubmission(t0.add(const Duration(minutes: 4)));
      expect(rl.canSubmit(t0.add(const Duration(minutes: 10))), isFalse); // 3 in the hour
      expect(rl.canSubmit(t0.add(const Duration(minutes: 61))), isTrue);
    });
  });

  group('formatting', () {
    test('times in Latin and Arabic digits', () {
      expect(formatTimeLatin('06:30'), '06:30 AM');
      expect(formatTimeLatin('18:30'), '06:30 PM');
      expect(formatTimeLatin('00:15'), '12:15 AM');
      expect(formatTimeArabic('06:30'), '٠٦:٣٠ ص');
      expect(formatTimeArabic('18:30'), '٠٦:٣٠ م');
      expect(formatRangeLatin('06:30', '08:30'), '06:30 AM – 08:30 AM');
      expect(weekdayName(5, arabic: true), 'الجمعة');
      expect(normalizeDigits('٢٠٢٦'), '2026');
    });
  });

  group('models', () {
    test('fromMap tolerates missing / string values', () {
      final l = Liturgy.fromMap('a', {'weekday': '5', 'start': '06:30', 'end': '08:30', 'nameAr': 'x'});
      expect(l.type, 'mass');
      expect(l.weekday, 5);
      expect(l.startMinutes, 390);
      final s = Season.fromMap('s', {'key': 'summer', 'startsAt': '2026-06-15T00:00:00+03:00', 'active': true});
      expect(s.startsAt, DateTime.utc(2026, 6, 14, 21));
      expect(parseHm('25:00'), isNull);
    });
  });
}
