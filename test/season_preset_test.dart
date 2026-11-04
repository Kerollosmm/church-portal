// ADR-042: season preset (apply / restore / auto-revert), season verse sets,
// the assistant's season limit and section-aware topics, the wedding switch,
// the admin «تجهيز الموسم» screen, and the hero v2 video / poster budgets.
import 'dart:io';
import 'dart:typed_data';

import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/domain/assistant_context.dart';
import 'package:church_portal/domain/assistant_settings.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/contact_categories.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/season_preset.dart';
import 'package:church_portal/domain/season_verses.dart';
import 'package:church_portal/ui/admin/admin_page.dart' show adminDestinations;
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/season_preset_admin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _start = DateTime.utc(2027, 4, 25, 4); // Palm Sunday eve, Cairo
final _end = DateTime.utc(2027, 5, 1, 22);

Season _holyWeek({bool active = false, bool replaces = false, DateTime? end}) => Season(
      id: 'hw',
      key: 'holy_week',
      nameAr: 'أسبوع الآلام',
      nameEn: 'Holy Week',
      startsAt: _start,
      endsAt: end ?? _end,
      active: active,
      replacesRegular: replaces,
    );

/// In-memory admin backend recording batched writes.
class _Backend extends AdminBackend {
  _Backend({this.seasons = const [], this.features});
  final List<AdminDoc> seasons;
  Map<String, dynamic>? features;
  final batches = <Map<String, Map<String, dynamic>>>[];

  @override
  String get actor => 'owner@example.org';
  @override
  Stream<List<AdminDoc>> watch(String collection) => Stream.value(collection == 'seasons' ? seasons : const []);
  @override
  Stream<AdminDoc?> watchDoc(String path) => Stream.value(path == 'settings/features'
      ? (features != null ? AdminDoc('features', features!) : null)
      : seasons.where((d) => 'seasons/${d.id}' == path).firstOrNull);
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {}
  @override
  Future<void> saveDocs(Map<String, Map<String, dynamic>> writes) async => batches.add(writes);
  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {}
  @override
  Future<void> delete(String collection, String id) async {}
  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {}
  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}
  @override
  Future<void> removeAdmin(String uid) async {}
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('season preset: apply / restore', () {
    PresetWrites apply(Set<String> options, {String live = '', String pdf = ''}) => planApply(
          r: PresetRequest(options: options, liveUrl: live, attachmentUrl: pdf, attachmentLabelAr: 'كتيب البصخة'),
          season: _holyWeek(),
          sections: {Sections.meetings: true, Sections.clinics: false},
          sectionKeys: Sections.all,
          heroMotion: true,
          weddingBookingOff: false,
          liveUrl: 'https://youtube.com/old',
          liveEndsAt: null,
          now: _start.subtract(const Duration(days: 2)),
        );

    test('Holy Week defaults: replace, hide meetings + clinics, hero still, no weddings', () {
      expect(PresetRequest.defaultsFor('holy_week'), {
        PresetOption.replaceRegular, PresetOption.hideMeetings, PresetOption.hideClinics, //
        PresetOption.heroMotionOff, PresetOption.weddingOff,
      });
      expect(PresetRequest.defaultsFor('pascha'), {PresetOption.replaceRegular});
      expect(PresetRequest.defaultsFor('revival_moses'), isEmpty);
    });

    test('apply writes the changes and the values they replace; restore puts them back', () {
      final w = apply(PresetOption.all.toSet(),
          live: ' https://youtube.com/live/abc ', pdf: 'https://drive.google.com/file/d/x/view');
      expect(w.seasonId, 'hw');
      expect(w.season, {
        'active': true,
        'replacesRegular': true,
        'attachmentUrl': 'https://drive.google.com/file/d/x/view',
        'attachmentLabelAr': 'كتيب البصخة',
        'attachmentLabelEn': '',
      });
      final sections = w.features['sections'] as Map<String, bool>;
      expect(sections.keys.toSet(), Sections.all.toSet(), reason: 'written whole (validSections)');
      expect(sections[Sections.meetings], isFalse);
      expect(sections[Sections.clinics], isFalse);
      expect(sections[Sections.schedule], isTrue);
      expect(w.features['heroMotion'], isFalse);
      expect(w.features['weddingBookingOff'], isTrue);
      expect(w.features['liveUrl'], 'https://youtube.com/live/abc');
      expect(w.features['liveEndsAt'], _end);

      final p = SeasonPreset.fromMap(w.features['seasonPreset'])!;
      expect(p.seasonId, 'hw');
      expect(p.seasonKey, 'holy_week');
      expect(p.endsAt, _end);
      // The theme item (ADR-043) needs the season's theme; none was given here,
      // so it is dropped (occasion_subthemes_test covers it).
      expect(p.options, [for (final o in PresetOption.all) if (o != PresetOption.theme) o]);
      expect(p.prevBool(PresetPrev.seasonActive), isFalse);
      expect(p.prevBool(PresetPrev.replacesRegular), isFalse);
      expect(p.prevBool(PresetPrev.meetings), isTrue);
      expect(p.prevBool(PresetPrev.clinics), isFalse, reason: 'clinics were already off');
      expect(p.prevString(PresetPrev.liveUrl), 'https://youtube.com/old');

      final r = planRestore(p, sections: sections, sectionKeys: Sections.all);
      expect(r.features['seasonPreset'], isNull);
      expect(r.features.containsKey('seasonPreset'), isTrue);
      final back = r.features['sections'] as Map<String, bool>;
      expect(back[Sections.meetings], isTrue);
      expect(back[Sections.clinics], isFalse, reason: 'restored to its previous (off) value');
      expect(r.features['heroMotion'], isTrue);
      expect(r.features['weddingBookingOff'], isFalse);
      expect(r.features['liveUrl'], 'https://youtube.com/old');
      expect(r.features['liveEndsAt'], isNull);
      expect(r.season['active'], isFalse);
      expect(r.season['replacesRegular'], isFalse);
      expect(r.season['attachmentUrl'], '');
    });

    test('only the ticked options are written and restored', () {
      final w = apply({PresetOption.heroMotionOff});
      expect(w.features.keys.toSet(), {'heroMotion', 'seasonPreset'});
      expect(w.season, {'active': true});
      final r = planRestore(SeasonPreset.fromMap(w.features['seasonPreset'])!, sections: const {}, sectionKeys: Sections.all);
      expect(r.features.keys.toSet(), {'heroMotion', 'seasonPreset'});
      expect(r.season, {'active': false});
    });

    test('bad links and a missing season are refused before any write', () {
      final s = _holyWeek();
      expect(presetProblem(const PresetRequest(), null), 'season');
      expect(presetProblem(const PresetRequest(options: {PresetOption.live}, liveUrl: 'youtube'), s), 'liveUrl');
      expect(presetProblem(const PresetRequest(options: {PresetOption.pdf}, attachmentUrl: 'http://drive.google.com/x'), s),
          'attachmentUrl');
      expect(presetProblem(const PresetRequest(options: {PresetOption.live}, liveUrl: 'https://youtu.be/x'), s), isNull);
      // The rules' 500-character cap is checked before the dialog (CodeRabbit review).
      final long = 'https://youtu.be/${'x' * 490}';
      expect(presetProblem(PresetRequest(options: const {PresetOption.live}, liveUrl: long), s), 'liveUrl');
      expect(presetProblem(PresetRequest(options: const {PresetOption.pdf}, attachmentUrl: long), s), 'attachmentUrl');
    });

    test('fromMap ignores unknown options / keys and a bad season id', () {
      expect(SeasonPreset.fromMap(null), isNull);
      expect(SeasonPreset.fromMap({'seasonId': 'a/b'}), isNull);
      final p = SeasonPreset.fromMap({
        'seasonId': 'hw',
        'options': ['heroMotionOff', 'nuke'],
        'previous': {'heroMotion': true, 'evil': 1},
      })!;
      expect(p.options, ['heroMotionOff']);
      expect(p.previous, {'heroMotion': true});
      expect(p.expiredAt(DateTime.now()), isFalse, reason: 'no end = until restored by hand');
    });
  });

  group('season preset: visitors return to normal at the season end, with no write', () {
    final stored = FeatureSettings.fromMap({
      'sections': {'meetings': false, 'clinics': false},
      'heroMotion': false,
      'weddingBookingOff': true,
      'seasonPreset': {
        'seasonId': 'hw',
        'seasonKey': 'holy_week',
        'endsAt': _end,
        'options': ['hideMeetings', 'hideClinics', 'heroMotionOff', 'weddingOff'],
        'previous': {'meetings': true, 'clinics': false, 'heroMotion': true, 'weddingBookingOff': false},
      },
    });

    test('during the season the stored values apply', () {
      final f = stored.effectiveAt(_end.subtract(const Duration(minutes: 1)));
      expect(f.enabled(Sections.meetings), isFalse);
      expect(f.heroMotion, isFalse);
      expect(f.weddingBookingOff, isTrue);
    });

    test('after the season the previous values apply (clinics stay off: they were off)', () {
      final f = stored.effectiveAt(_end);
      expect(f.enabled(Sections.meetings), isTrue);
      expect(f.enabled(Sections.clinics), isFalse);
      expect(f.heroMotion, isTrue);
      expect(f.weddingBookingOff, isFalse);
      expect(f.seasonPreset, isNotNull, reason: 'the admin still gets the restore button');
    });
  });

  group('season verses', () {
    test('stored rows per season; bad rows skipped; at most 40', () {
      final v = SeasonVerses.fromList([
        'holy_week\u001fهوذا الحمل\u001fيو 1: 29',
        'pascha\u001fالمسيح قام',
        'nope\u001fx\u001fy',
        'holy_week\u001f  \u001fz',
        5,
        for (var i = 0; i < 50; i++) 'summer\u001fآية $i\u001f',
      ]);
      expect(v.bySeason['holy_week']!.single.refAr, 'يو 1: 29');
      expect(v.bySeason['pascha']!.single.refAr, '');
      expect(v.bySeason.values.expand((l) => l).length, SeasonVerses.max);
      expect(SeasonVerses.fromList('x').isEmpty, isTrue);
    });

    test('the active season set rotates; a fixed admin verse still wins; else the general list', () {
      final v = SeasonVerses.fromList(['holy_week\u001fهوذا الحمل\u001fيو 1: 29']);
      final during = _start.add(const Duration(days: 1));
      final set = v.activeSet([_holyWeek(active: true)], during);
      expect(set.single.textAr, 'هوذا الحمل');
      expect(v.activeSet([_holyWeek(active: false)], during), isEmpty);
      expect(v.activeSet([_holyWeek(active: true)], _end.add(const Duration(days: 1))), isEmpty);
      const general = [Verse(textAr: 'عامة', refAr: 'مز 23')];
      expect(resolveSeasonalVerse(DailyVerseConfig.defaults, general, during, seasonSet: set)!.textAr, 'هوذا الحمل');
      expect(
          resolveSeasonalVerse(const DailyVerseConfig(mode: DailyVerseConfig.fixed, textAr: 'ثابتة'), general, during,
                  seasonSet: set)!
              .textAr,
          'ثابتة');
      expect(resolveSeasonalVerse(DailyVerseConfig.defaults, general, during)!.textAr, 'عامة');
    });

    test('admin field matches the rules format (seasonKey␟textAr␟refAr, 40 rows)', () {
      final f = seasonSettingsDoc.fields.firstWhere((f) => f.key == 'seasonVerses');
      expect(f.encodedRows, isTrue);
      expect(f.maxRows, 40);
      expect(f.subFields.map((s) => s.key), ['season', 'textAr', 'refAr']);
      expect(f.subFields.first.options, SeasonVerses.seasonKeys);
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('function validSeasonVerses'));
      for (final k in ['seasonVerses', 'seasonPreset', 'weddingBookingOff', 'perDaySeason']) {
        expect(rules, contains("'$k'"), reason: k);
      }
    });
  });

  group('assistant (ADR-042)', () {
    test('season daily limit: 6 by default during exceptional seasons, not summer', () {
      const s = AssistantSettings.defaults;
      expect(s.perDayFor(const []), AssistantLimits.perDayDefault);
      expect(s.perDayFor(const ['holy_week']), 6);
      expect(s.perDayFor(const ['revival_maximus']), 6);
      expect(s.perDayFor(const ['summer']), AssistantLimits.perDayDefault);
      final custom = AssistantSettings.fromMap(const {'perDay': 2, 'perDaySeason': 500});
      expect(custom.perDaySeason, AssistantLimits.perDayMax, reason: 'clamped');
      expect(custom.withSeasonLimit(const ['pascha']).perDay, AssistantLimits.perDayMax);
      expect(custom.withSeasonLimit(const []).perDay, 2);
    });

    test('a season never lowers a higher ordinary daily limit (Sentry review)', () {
      final s = AssistantSettings.fromMap(const {'perDay': 10});
      expect(s.perDayFor(const ['holy_week']), 10);
      expect(AssistantSettings.fromMap(const {'perDay': 10, 'perDaySeason': 20}).perDayFor(const ['holy_week']), 20);
    });

    test('sync end: the preset end (and the live end it set) follow the season\'s new end (Sentry review)', () {
      final newEnd = _end.add(const Duration(days: 3));
      final p = SeasonPreset(seasonId: 'hw', seasonKey: 'holy_week', appliedAt: _start, endsAt: _end,
          options: const [PresetOption.live]);
      final w = planSyncEnd(p, newEnd, storedLiveEndsAt: _end);
      expect(SeasonPreset.fromMap(w.features['seasonPreset'])!.endsAt, newEnd);
      expect(w.features['liveEndsAt'], newEnd);
      expect(w.season, isEmpty);
      // A live end changed by hand since the apply is left alone.
      expect(planSyncEnd(p, newEnd, storedLiveEndsAt: _start).features.containsKey('liveEndsAt'), isFalse);
    });

    test('topics of switched-off sections are dropped, the admin\'s own lines too', () {
      bool on(String s) => s != Sections.clinics && s != Sections.meetings;
      final t = AssistantSettings.defaults.topicsFor(on);
      expect(t.any((l) => l.toLowerCase().contains('clinic')), isFalse);
      expect(t.any((l) => l.toLowerCase().contains('meeting')), isFalse);
      expect(t.any((l) => l.toLowerCase().contains('liturgy')), isTrue);
      final admin = AssistantSettings.fromMap(const {'topics': 'مواعيد العيادات\nالقداسات'});
      expect(admin.topicsFor(on), ['القداسات']);
    });

    test('a line naming two sections needs both: history off drops «history and milestones» (Codex review)', () {
      final t = AssistantSettings.defaults.topicsFor((s) => s != Sections.history);
      expect(t.any((l) => l.toLowerCase().contains('history')), isFalse);
      expect(AssistantSettings.defaults.topicsFor((_) => true).any((l) => l.toLowerCase().contains('history')), isTrue);
      final admin = AssistantSettings.fromMap(const {'topics': 'محطات الكنيسة\nتاريخ الكنيسة'});
      expect(admin.topicsFor((s) => s != Sections.history), ['محطات الكنيسة']);
    });

    test('instructions name the current season and the switched-off sections', () {
      final text = buildAssistantInstruction(
        assistant: AssistantSettings.defaults,
        features: FeatureSettings.fromMap(const {
          'sections': {'clinics': false},
        }),
        settings: const ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: '', addressEn: ''),
        liturgies: const [],
        clinics: const [],
        meetings: const [],
        activities: const [],
        facilities: const [],
        seasons: [_holyWeek(active: true)],
        now: _start.add(const Duration(days: 1)),
      );
      expect(text, contains('Current church season: Holy Week (أسبوع الآلام)'));
      expect(text, contains('Switched off on this website right now: '));
      expect(text, contains(Sections.labels[Sections.clinics]![1]));
    });

    test('the wedding choice is hidden while weddingBookingOff is on; condolences stay', () {
      final off = ContactSettings.defaults.withoutWedding();
      final booking = off.categories.firstWhere((c) => c.isBooking);
      expect(booking.subtypes.map((s) => s.key), isNot(contains('wedding')));
      expect(booking.subtypes.map((s) => s.key), contains('condolence'));
      expect(FeatureSettings.fromMap(const {}).weddingBookingOff, isFalse);
      expect(FeatureSettings.fromMap(const {'weddingBookingOff': true}).weddingBookingOff, isTrue);
    });

    test('a booking category whose only choice is the wedding is hidden while weddingBookingOff is on (Codex review)', () {
      final base = ContactSettings.defaults;
      final booking = base.categories.firstWhere((c) => c.isBooking);
      final weddingOnly = ContactSettings([
        for (final c in base.categories)
          c.isBooking ? c.copyWith(subtypes: [for (final s in c.subtypes) if (s.key == 'wedding') s]) : c,
      ]);
      expect(weddingOnly.categories.firstWhere((c) => c.isBooking).subtypes, hasLength(1));
      final off = weddingOnly.withoutWedding();
      expect(off.categories.any((c) => c.isBooking), isFalse);
      expect(off.categories.length, base.categories.length - 1);
      // A booking category with no choices to begin with is left as it is.
      final noChoices = ContactSettings([
        for (final c in base.categories) c.isBooking ? c.copyWith(subtypes: const []) : c,
      ]).withoutWedding();
      expect(noChoices.categories.firstWhere((c) => c.isBooking).slot, booking.slot);
    });
  });

  group('admin «تجهيز الموسم»', () {
    Future<void> pump(WidgetTester tester, _Backend b, DateTime now) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: SeasonPresetScreen(repo: b, now: () => now)),
      ));
      await tester.pumpAndSettle();
    }

    test('listed in the dashboard for every role', () {
      for (final role in ['editor', 'owner']) {
        expect(adminDestinations(role).map((d) => d.id), contains('seasonPreset'));
      }
    });

    testWidgets('apply: pick the season, keep the defaults, confirm → one batch of two documents', (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'nameEn': 'Holy Week', 'startsAt': _start, 'endsAt': _end}),
      ], features: {'heroMotion': true});
      await pump(tester, b, _start.subtract(const Duration(days: 3)));
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Holy Week').last);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('presetOpt-hideMeetings'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('presetOpt-live'))).value, isFalse);
      await tester.tap(find.byKey(const Key('presetApply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('presetApplyDialog')), findsOneWidget);
      expect(b.batches, isEmpty, reason: 'nothing is written before the confirmation');
      await tester.tap(find.byKey(const Key('presetConfirm')));
      await tester.pumpAndSettle();
      expect(b.batches, hasLength(1));
      final w = b.batches.single;
      expect(w.keys.toSet(), {'settings/features', 'seasons/hw'});
      expect(w['settings/features']!['heroMotion'], isFalse);
      expect(w['seasons/hw'], containsPair('replacesRegular', true));
    });

    testWidgets('a preset applied meanwhile by another admin is never overwritten (CodeRabbit review)', (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'nameEn': 'Holy Week', 'startsAt': _start, 'endsAt': _end}),
      ], features: {'heroMotion': true});
      await pump(tester, b, _start.subtract(const Duration(days: 3)));
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Holy Week').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('presetApply')));
      await tester.pumpAndSettle();
      // Another device applies a preset while the dialog is open.
      b.features = {
        'heroMotion': false,
        'seasonPreset': {
          'seasonId': 'hw',
          'seasonKey': 'holy_week',
          'appliedAt': _start,
          'endsAt': _end,
          'options': ['heroMotionOff'],
          'previous': {'seasonActive': false, 'heroMotion': true},
        },
      };
      await tester.tap(find.byKey(const Key('presetConfirm')));
      await tester.pumpAndSettle();
      expect(b.batches, isEmpty);
      expect(find.textContaining('nothing was saved'), findsOneWidget);
    });

    testWidgets('season end moved after the apply: one tap moves the auto-revert (Sentry review)', (tester) async {
      final later = _end.add(const Duration(days: 2));
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'startsAt': _start, 'endsAt': later, 'active': true}),
      ], features: {
        'heroMotion': false,
        'seasonPreset': {
          'seasonId': 'hw',
          'seasonKey': 'holy_week',
          'appliedAt': _start,
          'endsAt': _end,
          'options': ['heroMotionOff'],
          'previous': {'seasonActive': false, 'heroMotion': true},
        },
      });
      await pump(tester, b, _start.add(const Duration(days: 1)));
      await tester.tap(find.byKey(const Key('presetSyncEnd')));
      await tester.pumpAndSettle();
      expect(b.batches, hasLength(1));
      final w = b.batches.single;
      expect(w.keys, ['settings/features']);
      expect((w['settings/features']!['seasonPreset'] as Map)['endsAt'], later);
    });

    testWidgets('an ended season can\'t be applied (CodeRabbit review)', (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'nameEn': 'Holy Week', 'startsAt': _start, 'endsAt': _end}),
      ], features: const {});
      await pump(tester, b, _end.add(const Duration(days: 1)));
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Holy Week').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('presetEnded')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('presetApply'))).onPressed, isNull);
    });

    testWidgets('a bad live link shows an error and writes nothing', (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'startsAt': _start, 'endsAt': _end}),
      ], features: const {});
      await pump(tester, b, _start);
      await tester.tap(find.byKey(const Key('presetSeason')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('أسبوع الآلام').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('presetOpt-live')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('presetLiveUrl')), 'not a link');
      await tester.tap(find.byKey(const Key('presetApply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('presetApplyDialog')), findsNothing);
      expect(b.batches, isEmpty);
    });

    testWidgets('applied: after the season end it says visitors already see normal; restore writes back',
        (tester) async {
      final b = _Backend(seasons: [
        AdminDoc('hw', {'key': 'holy_week', 'nameAr': 'أسبوع الآلام', 'startsAt': _start, 'endsAt': _end, 'active': true}),
      ], features: {
        'heroMotion': false,
        'seasonPreset': {
          'seasonId': 'hw',
          'seasonKey': 'holy_week',
          'appliedAt': _start,
          'endsAt': _end,
          'options': ['heroMotionOff'],
          'previous': {'seasonActive': false, 'heroMotion': true},
        },
      });
      await pump(tester, b, _end.add(const Duration(days: 1)));
      expect(find.byKey(const Key('presetExpired')), findsOneWidget);
      await tester.tap(find.byKey(const Key('presetRestore')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('presetRestoreDialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('presetConfirm')));
      await tester.pumpAndSettle();
      final w = b.batches.single;
      expect(w['settings/features'], {'seasonPreset': null, 'heroMotion': true});
      expect(w['seasons/hw'], {'active': false});
    });

    testWidgets('restore never recreates a deleted season', (tester) async {
      final b = _Backend(features: {
        'seasonPreset': {
          'seasonId': 'gone',
          'seasonKey': 'pascha',
          'options': ['replaceRegular'],
          'previous': {'seasonActive': true, 'replacesRegular': false},
        },
      });
      await pump(tester, b, _start);
      expect(find.byKey(const Key('presetActive')), findsOneWidget);
      await tester.tap(find.byKey(const Key('presetRestore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('presetConfirm')));
      await tester.pumpAndSettle();
      expect(b.batches.single.keys, ['settings/features']);
    });
  });

  group('hero v2 video and posters (budgets)', () {
    (int, int) webpSize(String path) {
      final b = File(path).readAsBytesSync();
      expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF', reason: path);
      final chunk = String.fromCharCodes(b.sublist(12, 16));
      final d = ByteData.sublistView(b);
      return switch (chunk) {
        'VP8 ' => (d.getUint16(26, Endian.little) & 0x3fff, d.getUint16(28, Endian.little) & 0x3fff),
        'VP8X' => (
            1 + (b[24] | b[25] << 8 | b[26] << 16),
            1 + (b[27] | b[28] << 8 | b[29] << 16),
          ),
        _ => (
            (d.getUint32(21, Endian.little) & 0x3fff) + 1,
            ((d.getUint32(21, Endian.little) >> 14) & 0x3fff) + 1,
          ),
      };
    }

    test('posters match the sizes index.html reserves (no layout shift)', () {
      final html = File('web/index.html').readAsStringSync();
      expect(webpSize('assets/art/hero_poster.webp'), (1280, 720));
      expect(webpSize('assets/art/hero_poster_tall.webp'), (432, 768));
      expect(html, contains('hero_poster_tall.webp" width="432" height="768"'));
      expect(html, contains('hero_poster.webp" alt="" width="1280" height="720"'));
      for (final f in ['assets/art/hero_poster.webp', 'assets/art/hero_poster_tall.webp']) {
        expect(File(f).lengthSync(), lessThan(24 * 1024), reason: f);
      }
    });

    test('9 s muted loops, moov before mdat (starts before the full download), small', () {
      for (final (f, max) in [('assets/video/hero_clouds.mp4', 320 * 1024), ('assets/video/hero_clouds_tall.mp4', 160 * 1024)]) {
        final b = File(f).readAsBytesSync();
        expect(b.length, lessThan(max), reason: f);
        int find(String box) {
          final t = box.codeUnits;
          for (var i = 0; i + 4 <= b.length; i++) {
            if (b[i] == t[0] && b[i + 1] == t[1] && b[i + 2] == t[2] && b[i + 3] == t[3]) return i;
          }
          return -1;
        }

        final moov = find('moov'), mdat = find('mdat'), mvhd = find('mvhd');
        expect(moov, greaterThan(0), reason: f);
        expect(moov, lessThan(mdat), reason: '$f: faststart');
        final d = ByteData.sublistView(b);
        final v0 = b[mvhd + 4] == 0;
        final scale = d.getUint32(mvhd + (v0 ? 16 : 24));
        final dur = v0 ? d.getUint32(mvhd + 20) : d.getUint64(mvhd + 28);
        expect(dur / scale, closeTo(9, 0.2), reason: f);
        expect(find('soun'), -1, reason: '$f: no audio track');
      }
    });
  });
}
