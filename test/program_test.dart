// ADR-041: programme details (speaker, topic, choir, venue, audience, Drive
// PDF link) on liturgies, meetings and seasons; admin venue / audience lists;
// parallel services in several halls; admin schema vs firestore.rules.
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/data/admin_repository.dart' show AdminRoles;
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/schedule.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart' show adminDestinations;
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_validators.dart' show validateRowUnique;
import 'package:church_portal/ui/pages/mass_schedule_page.dart' show audienceMatches;
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Liturgy lit(String id,
        {String start = '19:00',
        String end = '21:00',
        int? weekday,
        DateTime? date,
        String venue = '',
        String audience = '',
        String place = '',
        String placeEn = ''}) =>
    Liturgy(
      id: id,
      type: 'other',
      nameAr: 'صلاة $id',
      nameEn: '',
      weekday: weekday,
      date: date,
      start: start,
      end: end,
      placeAr: place,
      placeEn: placeEn,
      program: ProgramInfo(venue: venue, audience: audience),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('ProgramInfo', () {
    test('missing keys = empty (cards look as before)', () {
      final p = ProgramInfo.fromMap(const {'nameAr': 'x'});
      expect(p.isEmpty, isTrue);
      expect(p.hasAttachment, isFalse);
    });

    test('reads every key; only https links; invalid keys dropped', () {
      final p = ProgramInfo.fromMap(const {
        'speakerAr': ' نيافة الأنبا … ',
        'topicAr': 'التوبة',
        'choirAr': 'كورال الشمامسة',
        'venue': 'lower',
        'audience': 'youth',
        'attachmentUrl': 'https://drive.google.com/file/d/abc/view',
        'attachmentLabelAr': 'كتيب البصخة',
      });
      expect(p.speakerAr, 'نيافة الأنبا …');
      expect(p.venue, 'lower');
      expect(p.audience, 'youth');
      expect(p.hasAttachment, isTrue);
      expect(p.isEmpty, isFalse);
      expect(ProgramInfo.fromMap(const {'attachmentUrl': 'http://drive.google.com/x'}).hasAttachment, isFalse);
      expect(ProgramInfo.fromMap(const {'attachmentUrl': 'javascript:alert(1)'}).hasAttachment, isFalse);
      expect(ProgramInfo.fromMap(const {'venue': 'Lower Hall'}).venue, '');
      expect(ProgramInfo.fromMap(const {'speakerAr': 5}).speakerAr, '');
    });

    test('Liturgy, Meeting and Season carry it', () {
      const m = {'nameAr': 'x', 'stage': 'youth', 'key': 'holy_week', 'start': '19:00', 'speakerAr': 'أبونا'};
      expect(Liturgy.fromMap('a', m).program.speakerAr, 'أبونا');
      expect(Meeting.fromMap('b', m).program.speakerAr, 'أبونا');
      expect(Season.fromMap('c', m).program.speakerAr, 'أبونا');
    });
  });

  group('ProgramOptions (settings/features.venues / .audiences)', () {
    test('defaults when missing or empty', () {
      expect(FeatureSettings.fromMap(const {'theme': 'goldenHour'}).programOptions.venues, ProgramOptions.defaultVenues);
      expect(ProgramOptions.fromMap(const {'venues': []}).venues, ProgramOptions.defaultVenues);
      expect(ProgramOptions.defaults.audience('youth')!.labelAr, 'شباب');
    });

    test('stored rows key␟labelAr␟labelEn; bad / duplicate rows skipped; max 12', () {
      final o = ProgramOptions.fromMap({
        'venues': [
          'main\u001fالكنيسة الكبرى\u001fMain church',
          'main\u001fمكرر\u001f',
          'Bad Key\u001fx\u001f',
          'roof\u001f\u001fRoof',
          'garden\u001fالحديقة\u001f',
          ...List.generate(20, (i) => 'v$i\u001fقاعة $i\u001f'),
        ],
      });
      expect(o.venues.first, const ProgramOption('main', 'الكنيسة الكبرى', 'Main church'));
      expect(o.venues.where((v) => v.key == 'main'), hasLength(1));
      expect(o.venue('roof'), isNull);
      expect(o.venue('garden')!.labelEn, '');
      expect(o.venues, hasLength(ProgramOptions.max));
      expect(o.audiences, ProgramOptions.defaultAudiences);
      expect(const ProgramOption('a', 'ب', 'C').encode(), 'a\u001fب\u001fC');
    });

    test('a default key keeps its label after the admin replaces the list (Sentry review)', () {
      final o = ProgramOptions.fromMap({
        'venues': ['roof\u001fالسطح\u001fRoof'],
      });
      expect(o.venues.map((v) => v.key), ['roof']);
      expect(o.venue('main')!.labelAr, 'الكنيسة الكبرى');
      expect(o.venue('nope'), isNull);
      expect(ProgramOptions.withUsed(o.venues, ['main', 'roof', 'nope', ''], o.venue).map((v) => v.key), ['roof', 'main']);
    });
  });

  group('parallelServices', () {
    final day = DateTime.utc(2027, 4, 26, 10);
    test('same date, overlapping times, different venues', () {
      final r = parallelServices([
        lit('a', date: day, venue: 'main'),
        lit('b', date: day, venue: 'lower', audience: 'youth', start: '19:30'),
        lit('c', date: day, venue: 'services', start: '21:00', end: '22:00'), // starts when a ends
        lit('d', date: day.add(const Duration(days: 1)), venue: 'lower'), // another day
        lit('e', date: day, venue: 'main', start: '19:00'), // same venue as a
      ]);
      expect(r['a']!.map((l) => l.id), ['b']);
      expect(r['b']!.map((l) => l.id), ['a', 'e']);
      expect(r.containsKey('c'), isFalse);
      expect(r.containsKey('d'), isFalse);
    });

    test('weekly services by weekday; free-text place counts; no place = never parallel', () {
      final r = parallelServices([
        lit('a', weekday: 5, place: 'المذبح الرئيسي', end: ''),
        lit('b', weekday: 5, venue: 'lower', end: ''),
        lit('c', weekday: 5),
        lit('d', weekday: 6, venue: 'main'),
      ]);
      expect(r['a']!.single.id, 'b');
      expect(r.containsKey('c'), isFalse);
      expect(r.containsKey('d'), isFalse);
    });

    test('a venue key and its own name as free text are the same place (CodeRabbit review)', () {
      final services = [
        lit('a', weekday: 5, venue: 'main'),
        lit('b', weekday: 5, place: 'الكنيسة الكبرى'),
        lit('c', weekday: 5, placeEn: 'Lower hall'),
        lit('d', weekday: 5, placeEn: 'lower hall '),
      ];
      final r = parallelServices(services, ProgramOptions.defaults);
      expect(r['a']!.map((l) => l.id), ['c', 'd']);
      expect(r['b']!.map((l) => l.id), ['c', 'd']);
      expect(r.containsKey('c') && r['c']!.any((l) => l.id == 'd'), isFalse); // same English place
      // Without the options the key and the text differ (older callers).
      expect(parallelServices(services)['a']!.map((l) => l.id), contains('b'));
    });

    test('a service crossing midnight overlaps one later that night (CodeRabbit review)', () {
      final r = parallelServices([
        lit('a', weekday: 6, venue: 'main', start: '23:30', end: '01:00'),
        lit('b', weekday: 6, venue: 'lower', start: '23:45', end: '00:30'),
        lit('c', weekday: 6, venue: 'services', start: '22:00', end: '23:00'),
      ]);
      expect(r['a']!.single.id, 'b');
      expect(r['b']!.single.id, 'a');
      expect(r.containsKey('c'), isFalse);
    });
  });

  group('next-service parallel line (Sentry review)', () {
    test('only that day\'s real occurrences count: an out-of-season service is never named', () {
      final friday = CairoTime.at(2027, 4, 30); // a Friday
      Liturgy seasonal(String id, String venue) => Liturgy(
          id: id, type: 'other', nameAr: id, nameEn: '', weekday: 5, start: '08:00', end: '10:00',
          seasonKey: 'revival_moses', program: ProgramInfo(venue: venue));
      final all = [
        lit('mass', weekday: 5, start: '08:00', end: '10:00', venue: 'main'),
        lit('youth', weekday: 5, start: '09:00', end: '10:00', venue: 'lower'),
        seasonal('rev', 'services'),
      ];
      Season revival({required bool active}) => Season(
          id: 's', key: 'revival_moses', nameAr: 'نهضة', nameEn: '', active: active, replacesRegular: false,
          startsAt: DateTime.utc(2027, 4, 1), endsAt: DateTime.utc(2027, 5, 30));
      List<String> names(bool active) {
        final day = occurrencesForDay(liturgies: all, seasons: [revival(active: active)], day: friday, dayOffset: 0);
        final mass = day.firstWhere((o) => o.liturgy.id == 'mass');
        return parallelOccurrences(mass, day, ProgramOptions.defaults).map((l) => l.id).toList();
      }

      expect(names(false), ['youth']);
      expect(names(true), ['rev', 'youth']);
    });
  });

  test('a service with no or an unknown audience shows under every chip (Sentry review)', () {
    const o = ProgramOptions.defaults;
    expect(audienceMatches(lit('a', audience: 'youth'), 'youth', o), isTrue);
    expect(audienceMatches(lit('a', audience: 'youth'), 'children', o), isFalse);
    expect(audienceMatches(lit('a'), 'children', o), isTrue);
    expect(audienceMatches(lit('a', audience: 'deleted'), 'children', o), isTrue);
    expect(audienceMatches(lit('a', audience: 'youth'), '', o), isTrue);
  });

  group('admin rows', () {
    test('a repeated venue / audience key is refused on the later row (CodeRabbit review)', () {
      final venues = seasonSettingsDoc.fields.firstWhere((f) => f.key == 'venues');
      expect(venues.rowUniqueKey, 'key');
      expect(seasonSettingsDoc.fields.firstWhere((f) => f.key == 'audiences').rowUniqueKey, 'key');
      final keys = ['main', 'lower', ' main', ''];
      expect(validateRowUnique(venues, keys, 0), isNull);
      expect(validateRowUnique(venues, keys, 1), isNull);
      expect(validateRowUnique(venues, keys, 2), 'duplicateKey');
      expect(validateRowUnique(venues, keys, 3), isNull);
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child, {String lang = 'ar'}) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          featuresReadyProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          locale: Locale(lang),
          theme: buildTheme(Locale(lang)),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a liturgy card without programme details shows none of it', (tester) async {
      await pump(tester, LiturgyCard(liturgy: lit('a', weekday: 5)));
      expect(find.byKey(const Key('programPdf')), findsNothing);
      expect(find.textContaining('المتكلم'), findsNothing);
    });

    testWidgets('speaker, topic, choir, venue, audience, PDF and parallel line', (tester) async {
      const l = Liturgy(
        id: 'x',
        type: 'other',
        nameAr: 'بصخة ليلة الثلاثاء',
        nameEn: '',
        weekday: 1,
        start: '19:00',
        end: '',
        program: ProgramInfo(
          speakerAr: 'القمص يوحنا',
          topicAr: 'ساعات البصخة',
          choirAr: 'كورال الشمامسة',
          venue: 'main',
          audience: 'general',
          attachmentUrl: 'https://drive.google.com/file/d/abc/view',
        ),
      );
      await pump(tester, const LiturgyCard(liturgy: l, parallelText: 'القاعة السفلية (شباب)'));
      expect(find.text('المتكلم: القمص يوحنا'), findsOneWidget);
      expect(find.text('الموضوع: ساعات البصخة'), findsOneWidget);
      expect(find.text('الكورال: كورال الشمامسة'), findsOneWidget);
      expect(find.text('الكنيسة الكبرى'), findsOneWidget);
      expect(find.text('عام'), findsOneWidget);
      expect(find.text('وفي نفس الوقت: القاعة السفلية (شباب)'), findsOneWidget);
      expect(find.byKey(const Key('programPdf')), findsOneWidget);
      expect(find.text('البرنامج / الكتيب'), findsOneWidget);
    });
  });

  group('admin', () {
    final rules = File('firestore.rules').readAsStringSync();

    test('liturgies, meetings and seasons offer the programme group', () {
      for (final id in ['liturgies', 'meetings', 'seasons']) {
        final keys = collectionById(id)!.fields.where((f) => f.group == FieldGroup.program).map((f) => f.key).toList();
        expect(keys, ProgramInfo.keys, reason: id);
      }
      final venue = collectionById('liturgies')!.fields.firstWhere((f) => f.key == 'venue');
      expect(venue.dynamicOptions, 'venues');
    });

    test('rules allow-list = ProgramInfo.keys, used by the three collections', () {
      final fn = rules.substring(rules.indexOf('function programKeys()'), rules.indexOf('function validProgram('));
      for (final k in ProgramInfo.keys) {
        expect(fn, contains("'$k'"), reason: k);
      }
      for (final f in ['validSeason(d)', 'validLiturgy(d)', 'validMeeting(d, changed)']) {
        final i = rules.indexOf('function $f');
        expect(rules.substring(i, rules.indexOf('}', i)), contains('programKeys()'), reason: f);
      }
    });

    test('Season settings screen: venues / audiences rows match the stored format and the rules', () {
      expect(adminDestinations(AdminRoles.editor).map((d) => d.id), contains('seasonSettings'));
      expect(seasonSettingsDoc.path, 'settings/features');
      final block = rules.substring(rules.indexOf('function validFeatures('), rules.indexOf('function validProgramOptions('));
      // Only the venue / audience lists here; the season verse sets (ADR-042) have their own format and limits.
      final lists = seasonSettingsDoc.fields.where((f) => f.key == 'venues' || f.key == 'audiences').toList();
      expect(lists.map((f) => f.key), containsAll(['venues', 'audiences']));
      for (final f in lists) {
        expect(block, contains("'${f.key}'"), reason: f.key);
        expect(f.encodedRows, isTrue);
        expect(f.maxRows, ProgramOptions.max);
        expect(f.subFields.map((s) => s.key).toList(), ['key', 'labelAr', 'labelEn']);
      }
    });
  });
}
