// ADR-039 / ADR-040 widgets: Coptic date strip, live banner, top event card,
// footer note debounce, the admin "Today & live stream" schema vs the rules.
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/today.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart' show adminDestinations;
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_validators.dart' show validateRowOrder;
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/today_widgets.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart' show AdminRoles;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

DateTime cairo(int y, int m, int d, int h, [int min = 0]) => CairoTime.at(y, m, d, h * 60 + min);

void main() {
  setUpAll(CairoTime.ensureInitialized);

  Future<void> pump(WidgetTester tester, Widget child,
      {FeatureSettings features = FeatureSettings.defaults, required DateTime now, String lang = 'ar'}) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        featuresProvider.overrideWithValue(features),
        featuresReadyProvider.overrideWithValue(true),
        nowProvider.overrideWith((ref) => Stream.value(now)),
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

  group('Coptic date strip', () {
    testWidgets('shows the liturgical day', (tester) async {
      await pump(tester, const CopticDateStrip(location: '/'), now: cairo(2026, 11, 4, 10));
      expect(find.text('الأربعاء ٢٥ بابه ١٧٤٣ ش'), findsOneWidget);
    });
    testWidgets('after 18:00: the eve of the next day', (tester) async {
      await pump(tester, const CopticDateStrip(location: '/about'), now: cairo(2026, 11, 4, 19));
      expect(find.text('ليلة الخميس ٢٦ بابه ١٧٤٣ ش'), findsOneWidget);
    });

    test('home only / off', () {
      expect(CopticDateStrip.shownOn('home', '/about'), isFalse);
      expect(CopticDateStrip.shownOn('home', '/'), isTrue);
      expect(CopticDateStrip.shownOn('all', '/about'), isTrue);
      expect(CopticDateStrip.shownOn('off', '/'), isFalse);
    });
    testWidgets('off hides it', (tester) async {
      final off = FeatureSettings.fromMap(const {'copticStrip': 'off'});
      await pump(tester, const CopticDateStrip(location: '/'), features: off, now: cairo(2026, 11, 4, 10));
      expect(find.byKey(const Key('copticDateStrip')), findsNothing);
    });

    testWidgets('height is 32px with liturgical styling', (tester) async {
      await pump(tester, const CopticDateStrip(location: '/'), now: cairo(2026, 11, 4, 10));
      final size = tester.getSize(find.byKey(const Key('copticDateStrip')));
      expect(size.height, 32.0);
    });

    testWidgets('shows pulsing live badge when live stream is active and opens url on tap', (tester) async {
      final on = FeatureSettings.fromMap({
        'liveEnabled': true,
        'liveUrl': 'https://www.youtube.com/live/abc',
        'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
      });
      await pump(tester, const CopticDateStrip(location: '/'), features: on, now: cairo(2026, 11, 4, 19));
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
      expect(find.text('مباشر'), findsOneWidget);

      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments;
        if (args is Map && args['url'] is String) launched.add(args['url'] as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await tester.tap(find.byKey(const Key('topBarLiveBadge')));
      await tester.pump();
      expect(launched, contains('https://www.youtube.com/live/abc'));
    });

    testWidgets('narrow screen (320px) layout renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      final on = FeatureSettings.fromMap({
        'liveEnabled': true,
        'liveUrl': 'https://www.youtube.com/live/abc',
        'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
      });
      await pump(tester, const CopticDateStrip(location: '/'), features: on, now: cairo(2026, 11, 4, 19));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('copticDateStrip')), findsOneWidget);
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
    });
  });

  group('live-stream banner', () {
    final on = FeatureSettings.fromMap({
      'liveEnabled': true,
      'liveUrl': 'https://www.youtube.com/live/abc',
      'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
    });
    testWidgets('off by default', (tester) async {
      await pump(tester, const LiveStreamBanner(), now: cairo(2026, 11, 4, 19));
      expect(find.byKey(const Key('liveStreamBanner')), findsNothing);
    });
    testWidgets('on: default label, tappable; gone after the switch-off time', (tester) async {
      await pump(tester, const LiveStreamBanner(), features: on, now: cairo(2026, 11, 4, 19));
      expect(find.text('بث مباشر الآن من الكنيسة'), findsOneWidget);
      final label = find.bySemanticsLabel(RegExp('بث مباشر الآن من الكنيسة'));
      expect(label, findsOneWidget);
      // Assistive technology can activate it (PR #31 review).
      expect(tester.getSemantics(label).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // A tap launches the stream link (url_launcher's method channel).
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments;
        if (args is Map && args['url'] is String) launched.add(args['url'] as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await tester.tap(find.byKey(const Key('liveStreamBanner')));
      await tester.pump();
      expect(launched, contains('https://www.youtube.com/live/abc'));
    });
    testWidgets('gone after the switch-off time', (tester) async {
      await pump(tester, const LiveStreamBanner(), features: on, now: cairo(2026, 11, 4, 21, 1));
      expect(find.byKey(const Key('liveStreamBanner')), findsNothing);
    });
  });

  group('top event card', () {
    testWidgets('church event with speaker and topic', (tester) async {
      final f = FeatureSettings.fromMap({
        'dayEvents': [
          '2026-11-04\u001f\u001f19:00\u001f21:00\u001fالليلة الرابعة من نهضة الشفعاء\u001f\u001fنيافة الأنبا X\u001f\u001fالتوبة\u001f\u001f\u001f\u001f',
        ],
      });
      await pump(tester, const TopEventCard(), features: f, now: cairo(2026, 11, 4, 12));
      expect(find.text('الليلة الرابعة من نهضة الشفعاء'), findsOneWidget);
      expect(find.text('حدث اليوم'), findsOneWidget);
      expect(find.textContaining('نيافة الأنبا X'), findsOneWidget);
      expect(find.textContaining('التوبة'), findsOneWidget);
    });

    testWidgets('"Learn more" only when its in-app section is on (PR #31 review)', (tester) async {
      const ev = '2026-11-04\u001f\u001f19:00\u001f21:00\u001fنهضة\u001f\u001f\u001f\u001f\u001f\u001f\u001f\u001f/mass-schedule';
      await pump(tester, const TopEventCard(), features: FeatureSettings.fromMap(const {'dayEvents': [ev]}),
          now: cairo(2026, 11, 4, 12));
      expect(find.text('اعرف المزيد'), findsOneWidget);
      await pump(tester, const TopEventCard(),
          features: FeatureSettings.fromMap(const {'dayEvents': [ev], 'sections': {'schedule': false}}),
          now: cairo(2026, 11, 4, 12));
      expect(find.text('اعرف المزيد'), findsNothing);
    });

    testWidgets('computed feast offline (no Katameros data), English', (tester) async {
      await pump(tester, const TopEventCard(), now: cairo(2027, 1, 7, 9), lang: 'en');
      expect(find.text("Today's feast"), findsOneWidget);
      expect(find.textContaining('Nativity'), findsOneWidget);
      expect(find.textContaining('katameros'), findsNothing);
    });

    testWidgets('ordinary day without data: nothing', (tester) async {
      await pump(tester, const TopEventCard(), now: cairo(2026, 11, 4, 9));
      expect(find.byKey(const Key('topEventCard')), findsNothing);
    });

    testWidgets('switched off', (tester) async {
      await pump(tester, const TopEventCard(),
          features: FeatureSettings.fromMap(const {'topEvent': false}), now: cairo(2027, 1, 7, 9));
      expect(find.byKey(const Key('topEventCard')), findsNothing);
    });
  });

  group('footer note debounce (PR #30 follow-up)', () {
    testWidgets('a short fallback never shows the note; a lasting one does', (tester) async {
      final seed = ValueNotifier<bool>(false);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SteadySeedNote(servingSeed: seed, delay: const Duration(seconds: 4), child: const Text('note')),
      ));
      seed.value = true;
      await tester.pump(const Duration(seconds: 2));
      seed.value = false;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('note'), findsNothing);
      seed.value = true;
      await tester.pump(const Duration(seconds: 4, milliseconds: 10));
      expect(find.text('note'), findsOneWidget);
      seed.value = false;
      await tester.pump();
      expect(find.text('note'), findsNothing);
    });

    testWidgets('offline (seed mode) shows it at once', (tester) async {
      final seed = ValueNotifier<bool>(true);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SteadySeedNote(servingSeed: seed, delay: Duration.zero, child: const Text('note')),
      ));
      expect(find.text('note'), findsOneWidget);
    });
  });

  group('admin "Today & live stream"', () {
    test('a dashboard destination for every admin', () {
      expect(adminDestinations(AdminRoles.editor).map((d) => d.id), contains('today'));
    });

    test('every field is allowed by validFeatures and the event row order matches the rules', () {
      final rules = File('firestore.rules').readAsStringSync();
      final block = rules.substring(rules.indexOf('function validFeatures('), rules.indexOf('function validDayEvents('));
      for (final f in todaySettingsDoc.fields) {
        expect(block, contains("'${f.key}'"), reason: f.key);
      }
      final events = todaySettingsDoc.fields.firstWhere((f) => f.key == 'dayEvents');
      expect(events.subFields.map((f) => f.key).toList(), DayEvent.storedKeys);
      expect(events.maxRows, DayEvent.maxEvents);
      expect(rules, contains("optList(d, 'dayEvents', ${DayEvent.maxEvents})"));
      // An end date before the start date is rejected in the form (PR #31 review).
      expect(events.rowNotBefore, const MapEntry('endDate', 'date'));
      expect(validateRowOrder(events, {'date': '2026-11-04', 'endDate': '2026-11-03'}), 'endDateBeforeStart');
      expect(validateRowOrder(events, {'date': '2026-11-04', 'endDate': '2026-11-04'}), isNull);
      expect(validateRowOrder(events, {'date': '2026-11-04', 'endDate': ''}), isNull);
    });
  });

  group('AppShell top utility bar integration', () {
    testWidgets('places TopUtilityBar above AppBar and adjusts SealTab position', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(FeatureSettings.defaults),
          featuresReadyProvider.overrideWithValue(true),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 4, 10))),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const AppShell(location: '/', child: Text('home content')),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('copticDateStrip')), findsOneWidget);
      final stripTop = tester.getTopLeft(find.byKey(const Key('copticDateStrip'))).dy;
      expect(stripTop, 0.0);

      final sealTop = tester.getTopLeft(find.byKey(const Key('sealTabHome'))).dy;
      expect(sealTop, 32.0);
    });
  });
}
