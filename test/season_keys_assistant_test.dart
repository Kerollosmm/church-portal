// ADR-051 (issues 4–7, 9–14 of the seasons v2 run): new season keys, the
// admin-configurable exceptional-quota list, the prompt's church-calendar
// line, Arabic digits in the limit message, /ask greeting and chips that skip
// hidden sections, the preset's live-banner end, per-date replace override,
// fast presets without weddings, Holy Week day names and the EN live label.
import 'dart:io';

import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/assistant_settings.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/coptic_calendar.dart';
import 'package:church_portal/domain/daily_verse.dart' show Verse;
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/occasion_theme.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/domain/season_keys.dart';
import 'package:church_portal/domain/season_preset.dart';
import 'package:church_portal/domain/season_verses.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime cairo(int y, int m, int d, [int h = 0, int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

Liturgy lit(String id,
        {int? weekday,
        DateTime? date,
        required String start,
        String? end,
        String type = 'mass',
        String? season,
        bool sample = false}) =>
    Liturgy(
      id: id,
      type: type,
      nameAr: id,
      nameEn: id,
      weekday: weekday,
      date: date,
      start: start,
      end: end ?? '',
      seasonKey: season,
      sample: sample,
    );

const _church = ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: '');

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('issue 9: season keys', () {
    test('one list everywhere: rules, admin, verses, theme map, labels', () {
      final rules = File('firestore.rules').readAsStringSync();
      final l10n = File('lib/core/l10n.dart').readAsStringSync();
      final fn = RegExp(r'function seasonKeyList\(\) \{\s*return \[([^\]]*)\]', multiLine: true).firstMatch(rules)!;
      final ruleKeys = RegExp(r"'([a-z_]+)'").allMatches(fn.group(1)!).map((m) => m.group(1)).toList();
      expect(ruleKeys, SeasonKeys.all);
      expect(seasonKeys, SeasonKeys.all);
      expect(SeasonVerses.seasonKeys, SeasonKeys.all);
      expect(SeasonThemes.seasonKeys.toSet(), SeasonKeys.all.toSet());
      expect(SeasonThemes.defaults.keys.toSet(), SeasonKeys.all.toSet());
      // The verse regex knows every key too.
      expect(rules, contains('(${SeasonKeys.all.join('|')})'));
      for (final k in SeasonKeys.all) {
        expect(l10n, contains("'opt_$k': ["), reason: 'label for $k');
      }
      expect(SeasonKeys.all, containsAll(['apostles', 'nayrouz', 'kiahk', 'great_lent', 'fast']));
      expect(SeasonKeys.all, isNot(contains('cross')), reason: 'Nayrouz covers the Feast of the Cross');
    });

    test('themes: fasting family on the fasting palette, Nayrouz festive red, never violet', () {
      const occ = OccasionConfig.defaults;
      for (final k in ['great_lent', 'apostles', 'kiahk', 'fast']) {
        expect(occ.themeForSeason(k), ThemePresets.fasting, reason: k);
      }
      expect(occ.themeForSeason('nayrouz'), ThemePresets.resurrection);
      expect(SeasonThemes.defaults.values, isNot(contains(ThemePresets.legacyPurple)));
      // Holy Week still wins over Great Lent when both are active.
      final i = SeasonThemes.seasonKeys.indexOf;
      expect(i('holy_week'), lessThan(i('great_lent')));
      expect(i('great_lent'), lessThan(i('fast')));
      // The admin can still remap a new key.
      final mapped = occ.copyWith(seasonThemes: {'kiahk': ThemePresets.marian});
      expect(mapped.themeForSeason('kiahk'), ThemePresets.marian);
    });

    test('verses: a fasting key falls back to the general fast set', () {
      final v = SeasonVerses.fromList([
        'fast\u001fآية الصوم\u001f',
        'apostles\u001fآية الرسل\u001f',
      ]);
      expect(v.versesFor('apostles').single.textAr, 'آية الرسل');
      expect(v.versesFor('great_lent').single.textAr, 'آية الصوم');
      expect(v.versesFor('kiahk').single.textAr, 'آية الصوم');
      expect(v.versesFor('nayrouz'), isEmpty);
      final lent = Season(
          id: 'gl', key: 'great_lent', nameAr: '', nameEn: '', startsAt: cairo(2027, 3, 8), endsAt: cairo(2027, 4, 23, 23, 59));
      expect(v.activeSet([lent], cairo(2027, 3, 16, 13)), isA<List<Verse>>().having((l) => l.single.textAr, 'text', 'آية الصوم'));
    });

    test('season docs with the new keys parse; fast stays valid', () {
      for (final k in [...SeasonKeys.all]) {
        expect(Season.fromMap('s', {'key': k, 'nameAr': 'x'}).key, k);
      }
    });
  });

  group('issue 5: exceptional-quota list', () {
    test('defaults: big seasons, Great Lent, Kiahk and the Marian seasons', () {
      const s = AssistantSettings.defaults;
      expect(s.exceptionalSeasons, [
        'holy_week', 'pascha', 'nativity', 'revival_maximus', 'revival_moses', 'great_lent', 'kiahk', 'marian', //
      ]);
      for (final k in ['great_lent', 'kiahk', 'marian', 'holy_week']) {
        expect(s.perDayFor([k]), 6, reason: k);
      }
      for (final k in ['fast', 'apostles', 'nayrouz', 'summer', 'epiphany']) {
        expect(s.perDayFor([k]), 3, reason: k);
      }
    });

    test('the admin list replaces the defaults; empty = no season raises it; unknown keys dropped', () {
      final s = AssistantSettings.fromMap({
        'perDay': 3,
        'perDaySeason': 8,
        'exceptionalSeasons': ['apostles', 'bogus', 5],
      });
      expect(s.exceptionalSeasons, ['apostles']);
      expect(s.perDayFor(['apostles']), 8);
      expect(s.perDayFor(['holy_week']), 3);
      expect(s.withSeasonLimit(['apostles']).perDay, 8);
      expect(s.withSeasonLimit(['apostles']).exceptionalSeasons, ['apostles']);
      final none = AssistantSettings.fromMap({'exceptionalSeasons': <String>[]});
      expect(none.perDayFor(['holy_week']), 3);
    });

    test('admin form: a multi-choice of every key, defaulting to the code list', () {
      final f = assistantSettingsDoc.fields.firstWhere((f) => f.key == 'exceptionalSeasons');
      expect(f.type, FieldType.choices);
      expect(f.options, SeasonKeys.all);
      expect(f.defaultValues, exceptionalSeasonKeys);
      final perDay = assistantSettingsDoc.fields.firstWhere((f) => f.key == 'perDaySeason');
      expect(perDay.min, 1);
      expect(perDay.max, 100);
    });
  });

  group('issue 13: Holy Week day names', () {
    test('Palm Sunday … Joyous Saturday from the Easter computus', () {
      // Easter 2027 = 2 May.
      final names = {
        DateTime.utc(2027, 4, 25): ('أحد الشعانين', 'Palm Sunday'),
        DateTime.utc(2027, 4, 26): ('اثنين البصخة', 'Holy Monday'),
        DateTime.utc(2027, 4, 27): ('ثلاثاء البصخة', 'Holy Tuesday'),
        DateTime.utc(2027, 4, 28): ('أربعاء البصخة', 'Holy Wednesday'),
        DateTime.utc(2027, 4, 29): ('خميس العهد', 'Covenant Thursday'),
        DateTime.utc(2027, 4, 30): ('الجمعة العظيمة', 'Good Friday'),
        DateTime.utc(2027, 5, 1): ('سبت النور', 'Joyous Saturday'),
      };
      names.forEach((d, n) {
        expect(holyWeekDayName(d, arabic: true), n.$1);
        expect(holyWeekDayName(d, arabic: false), n.$2);
      });
      expect(holyWeekDayName(DateTime.utc(2027, 5, 2), arabic: true), isNull, reason: 'Easter Sunday');
      expect(holyWeekDayName(DateTime.utc(2027, 4, 24), arabic: true), isNull, reason: 'Lazarus Saturday');
      // 2026: Easter 12 April → Good Friday 10 April.
      expect(holyWeekDayName(DateTime.utc(2026, 4, 10), arabic: true), 'الجمعة العظيمة');
    });

    test('the top-bar label: the name replaces the weekday, «ليلة …» after the rollover', () {
      expect(liturgicalDayAt(cairo(2027, 4, 29, 18, 30)).label(arabic: true), 'ليلة الجمعة العظيمة ٢٢ برموده ١٧٤٣ ش');
      expect(liturgicalDayAt(cairo(2027, 4, 29, 18, 30)).label(arabic: false), 'Eve of Good Friday 22 Baramouda 1743 AM');
      expect(liturgicalDayAt(cairo(2027, 4, 29, 10)).label(arabic: true), 'خميس العهد ٢١ برموده ١٧٤٣ ش');
      expect(liturgicalDayAt(cairo(2027, 4, 24, 19)).label(arabic: true), startsWith('ليلة أحد الشعانين'));
      // Outside Holy Week: unchanged.
      expect(liturgicalDayAt(cairo(2026, 11, 4, 10)).label(arabic: true), 'الأربعاء ٢٥ بابه ١٧٤٣ ش');
      expect(liturgicalDayAt(cairo(2027, 5, 1, 19)).label(arabic: true), startsWith('ليلة الأحد'));
    });
  });

  group('issue 4: church calendar line in the prompt', () {
    test('Coptic date and the computed feast, rolling over at 18:00', () {
      const f = FeatureSettings.defaults;
      final before = churchCalendarLine(f, cairo(2027, 4, 29, 17, 59));
      expect(before, contains('Covenant Thursday 21 Baramouda 1743 AM (خميس العهد ٢١ برموده ١٧٤٣ ش)'));
      expect(before, contains('Feast of the day: Covenant Thursday (خميس العهد)'));
      expect(before, contains('at 18:00'));
      final after = churchCalendarLine(f, cairo(2027, 4, 29, 18));
      expect(after, contains('Eve of Good Friday 22 Baramouda 1743 AM'));
      expect(after, contains('Good Friday (الجمعة العظيمة)'));
      final plain = churchCalendarLine(f, cairo(2026, 11, 4, 10));
      expect(plain, contains('Wednesday 25 Baba 1743 AM'));
      expect(plain, contains('No major feast or fast begins on this day.'));
    });

    test('the loaded Katameros day adds its feast and commemorations; sunset mode is named', () {
      final f = FeatureSettings.fromMap(const {'dayStartMode': 'sunset'});
      final k = SynaxariumData(days: {
        '2027-09-12': const SynaxariumDay(
          feastAr: 'عيد النيروز',
          feastEn: 'Nayrouz (Coptic New Year)',
          ar: ['عيد النيروز رأس السنة القبطية', 'تذكار شفاء أيوب الصديق'],
          en: ['Feast of El-Nayrouz', 'The Healing of the Righteous Job'],
        ),
      });
      final line = churchCalendarLine(f, cairo(2027, 9, 12, 8), synaxarium: k);
      expect(line, contains('Sunday 1 Tout 1744 AM'));
      expect(line, contains('Nayrouz (Coptic New Year) (عيد النيروز)'));
      expect(line, contains('Feast of El-Nayrouz (Coptic New Year) (عيد النيروز (رأس السنة القبطية))'));
      expect(line, contains('The Healing of the Righteous Job (تذكار شفاء أيوب الصديق)'));
      expect(line, contains('at sunset'));
    });

    test('the system instruction carries the line (built per question)', () {
      String build(DateTime now) => buildAssistantInstruction(
            settings: _church,
            liturgies: const [],
            seasons: const [],
            clinics: const [],
            meetings: const [],
            activities: const [],
            facilities: const [],
            now: now,
          );
      expect(build(cairo(2027, 4, 29, 18, 30)), contains('Church calendar (the Coptic liturgical day starts the evening before'));
      expect(build(cairo(2027, 4, 29, 18, 30)), contains('Eve of Good Friday'));
      expect(build(cairo(2027, 4, 29, 12)), contains('Covenant Thursday 21 Baramouda'));
    });

    test('an additive season lists its feast-night replace dates', () {
      final s = Season(
          id: 'ap',
          key: 'apostles',
          nameAr: 'صوم الرسل',
          nameEn: "Apostles' fast",
          startsAt: cairo(2027, 6, 21),
          endsAt: cairo(2027, 7, 12, 23, 59),
          replacesRegular: false,
          replaceDates: const ['2027-07-12']);
      final out = buildAssistantInstruction(
        settings: _church,
        liturgies: [lit('feast', date: DateTime.utc(2027, 7, 12), start: '06:00', end: '09:00', season: 'apostles')],
        seasons: [s],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        now: cairo(2027, 7, 1, 10),
      );
      expect(out, contains('On 2027-07-12 this season REPLACES the regular services (feast night).'));
    });
  });

  group('issue 7: greeting and chips skip hidden sections', () {
    test('the built-in welcome names only switched-on sections', () {
      bool all(String _) => true;
      expect(askIntroText(arabic: true, enabled: all),
          'أهلًا بك! أجيب عن مواعيد القداسات والعيادات والاجتماعات وطرق التواصل، من بيانات الكنيسة الرسمية.');
      bool noClinicsMeetings(String s) => s != 'clinics' && s != 'meetings';
      final ar = askIntroText(arabic: true, enabled: noClinicsMeetings);
      expect(ar, 'أهلًا بك! أجيب عن مواعيد القداسات وطرق التواصل، من بيانات الكنيسة الرسمية.');
      expect(ar, isNot(contains('العيادات')));
      expect(askIntroText(arabic: false, enabled: noClinicsMeetings),
          "Welcome! I answer questions about liturgy times and contacts using the church's official data.");
      expect(askIntroText(arabic: false, enabled: all),
          "Welcome! I answer questions about liturgy times, clinics, meetings and contacts using the church's official data.");
      expect(askIntroText(arabic: true, enabled: (_) => false), contains('أسئلتك عن الكنيسة'));
    });

    test('suggested questions about a hidden section are dropped', () {
      final s = AssistantSettings.fromMap({
        'showSuggestions': true,
        'suggestionsAr': 'متى القداس؟\nمواعيد العيادة؟\nاجتماع الشباب امتى؟',
      });
      expect(s.visibleSuggestions(true), hasLength(3));
      expect(s.visibleSuggestions(true, (sec) => sec != 'clinics' && sec != 'meetings'), ['متى القداس؟']);
    });
  });

  group('issue 12: fast presets untick weddings', () {
    test('every fasting key defaults to weddingOff; feasts and revivals unchanged', () {
      for (final k in SeasonKeys.fastFamily) {
        expect(PresetRequest.defaultsFor(k), {PresetOption.weddingOff}, reason: k);
      }
      expect(PresetRequest.defaultsFor('holy_week'), contains(PresetOption.weddingOff));
      expect(PresetRequest.defaultsFor('pascha'), {PresetOption.replaceRegular});
      expect(PresetRequest.defaultsFor('nayrouz'), isEmpty);
      expect(PresetRequest.defaultsFor('revival_moses'), isEmpty);
      expect(PresetRequest.defaultsFor('marian'), isEmpty);
    });
  });

  group('issue 10: live banner end defaults to tonight', () {
    final marian = Season(
        id: 'm', key: 'marian', nameAr: 'العذراء', nameEn: '', startsAt: cairo(2027, 8, 7), endsAt: cairo(2027, 8, 21, 23, 59),
        active: false, replacesRegular: false);
    final rev = lit('rev', weekday: 2, start: '18:30', end: '21:30', type: 'other', season: 'marian');
    final youth = lit('youth', date: DateTime.utc(2027, 8, 10), start: '19:00', end: '22:00', type: 'other', season: 'marian');
    final regular = lit('reg', weekday: 2, start: '07:00', end: '23:00');

    test('the last service of the season tonight + 30 min (regular services ignored)', () {
      final end = presetLiveEnd(season: marian, liturgies: [rev, youth, regular], now: cairo(2027, 8, 10, 9));
      expect(end.millisecondsSinceEpoch, cairo(2027, 8, 10, 22, 30).millisecondsSinceEpoch);
      expect(end.isUtc, isTrue);
    });

    test('an overnight service ends the next morning', () {
      final kiahk = Season(
          id: 'k', key: 'kiahk', nameAr: 'كيهك', nameEn: '', startsAt: cairo(2026, 12, 10), endsAt: cairo(2027, 1, 7),
          replacesRegular: false);
      final praise = lit('praise', weekday: 6, start: '21:00', end: '05:30', type: 'praise', season: 'kiahk');
      expect(presetLiveEnd(season: kiahk, liturgies: [praise], now: cairo(2026, 12, 19, 12)).millisecondsSinceEpoch, cairo(2026, 12, 20, 6).millisecondsSinceEpoch);
    });

    test('no service tonight → 23:59; services all ended → 23:59; season not started → its first evening', () {
      expect(presetLiveEnd(season: marian, liturgies: [regular], now: cairo(2027, 8, 10, 9)).millisecondsSinceEpoch, cairo(2027, 8, 10, 23, 59).millisecondsSinceEpoch);
      expect(presetLiveEnd(season: marian, liturgies: [rev], now: cairo(2027, 8, 10, 22, 45)).millisecondsSinceEpoch, cairo(2027, 8, 10, 23, 59).millisecondsSinceEpoch);
      // Applied two days before the season (Thursday 5 Aug); first evening Sat 7 Aug.
      final sat = lit('sat', weekday: 6, start: '19:00', end: '21:00', type: 'other', season: 'marian');
      expect(presetLiveEnd(season: marian, liturgies: [sat], now: cairo(2027, 8, 5, 12)).millisecondsSinceEpoch, cairo(2027, 8, 7, 21, 30).millisecondsSinceEpoch);
    });

    test('never after the season end', () {
      final short = Season(
          id: 's', key: 'nayrouz', nameAr: 'النيروز', nameEn: '', startsAt: cairo(2027, 9, 11, 18), endsAt: cairo(2027, 9, 11, 22),
          replacesRegular: false);
      final eve = lit('eve', date: DateTime.utc(2027, 9, 11), start: '19:00', end: '21:45', type: 'vespers', season: 'nayrouz');
      expect(presetLiveEnd(season: short, liturgies: [eve], now: cairo(2027, 9, 11, 17)).millisecondsSinceEpoch, cairo(2027, 9, 11, 22).millisecondsSinceEpoch);
    });

    test('planApply writes the given end; older callers keep the season end', () {
      PresetWrites apply(DateTime? liveEnd) => planApply(
            r: const PresetRequest(options: {PresetOption.live}, liveUrl: 'https://youtube.com/live/x'),
            season: marian,
            sections: const {},
            sectionKeys: Sections.all,
            heroMotion: true,
            weddingBookingOff: false,
            liveUrl: '',
            liveEndsAt: null,
            now: cairo(2027, 8, 10, 9),
            liveEnd: liveEnd,
          );
      expect(apply(cairo(2027, 8, 10, 22, 30)).features['liveEndsAt'], cairo(2027, 8, 10, 22, 30));
      expect(apply(null).features['liveEndsAt'], marian.endsAt);
      // The preset end (auto-revert) is still the season's end.
      expect((apply(cairo(2027, 8, 10, 22, 30)).features['seasonPreset'] as Map)['endsAt'], marian.endsAt);
    });
  });

  group('issue 11: per-date replace override', () {
    final apostles = Season(
        id: 'ap', key: 'apostles', nameAr: 'صوم الرسل', nameEn: '', startsAt: cairo(2027, 6, 21), endsAt: cairo(2027, 7, 12, 23, 59),
        replacesRegular: false, replaceDates: const ['2027-07-12']);
    final regularMon = lit('regMon', weekday: 1, start: '07:00', end: '09:00');
    final regularVespersMon = lit('vesMon', weekday: 1, start: '18:00', end: '19:00', type: 'vespers');
    final feastEve = lit('feastNight', date: DateTime.utc(2027, 7, 12), start: '20:00', end: '23:00', type: 'other', season: 'apostles');
    final weekNight = lit('night', date: DateTime.utc(2027, 7, 5), start: '20:00', end: '22:00', type: 'other', season: 'apostles');

    List<String> ids(DateTime day) => [
          for (final o in occurrencesForDay(
              liturgies: [regularMon, regularVespersMon, feastEve, weekNight],
              seasons: [apostles],
              day: CairoTime.fromInstant(day),
              dayOffset: 0))
            o.liturgy.id,
        ];

    test('on a replace date the season hides the regular services in its window', () {
      expect(ids(cairo(2027, 7, 12)), ['feastNight']);
    });

    test('every other day stays additive', () {
      expect(ids(cairo(2027, 7, 5)), ['regMon', 'vesMon', 'night']);
    });

    test('Season.replacesOn and parsing', () {
      expect(apostles.replacesOn(DateTime(2027, 7, 12)), isTrue);
      expect(apostles.replacesOn(DateTime(2027, 7, 11)), isFalse);
      const full = Season(id: 'hw', key: 'holy_week', nameAr: '', nameEn: '');
      expect(full.replacesOn(DateTime(2027, 1, 1)), isTrue);
      final parsed = Season.fromMap('s', {
        'key': 'apostles',
        'replacesRegular': false,
        'replaceDates': ['2027-07-12', ' 2027-07-13 ', 'bad', 5],
      });
      expect(parsed.replaceDates, ['2027-07-12', '2027-07-13']);
      expect(Season.fromMap('s', {'key': 'fast'}).replaceDates, isEmpty);
    });

    test('admin season form: a date-chip list of at most 10', () {
      final f = adminCollections.firstWhere((c) => c.id == 'seasons').fields.firstWhere((f) => f.key == 'replaceDates');
      expect(f.type, FieldType.dateList);
      expect(f.maxRows, 10);
    });
  });

  group('issue 14: live label per language', () {
    test('EN pages never show the Arabic label', () {
      final t = TodaySettings.fromMap(const {'liveLabelAr': 'بث مباشر: قداس عيد القيامة'});
      expect(t.liveLabelFor(arabic: true), 'بث مباشر: قداس عيد القيامة');
      expect(t.liveLabelFor(arabic: false), '');
      final both = TodaySettings.fromMap(const {'liveLabelAr': 'بث', 'liveLabelEn': ' Live: Easter liturgy '});
      expect(both.liveLabelFor(arabic: false), 'Live: Easter liturgy');
      final enOnly = TodaySettings.fromMap(const {'liveLabelEn': 'Live'});
      expect(enOnly.liveLabelFor(arabic: true), '', reason: 'the Arabic page keeps its own default');
    });

    test('the admin field exists in «اليوم والبث المباشر»', () {
      final f = todaySettingsDoc.fields.firstWhere((f) => f.key == 'liveLabelEn');
      expect(f.maxLength, 120);
      expect(f.hintEn, contains('English pages only'));
    });
  });
}
