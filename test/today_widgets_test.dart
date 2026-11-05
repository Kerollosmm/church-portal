// ADR-039 / ADR-040 widgets: Coptic date strip, live banner, top event card,
// footer note debounce, the admin "Today & live stream" schema vs the rules.
import 'dart:io';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/occasion_theme.dart' show ThemePresets, contrastRatio;
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
      {FeatureSettings features = FeatureSettings.defaults,
      required DateTime now,
      String lang = 'ar',
      Size? physicalSize,
      String themeKey = 'goldenHour',
      double textScale = 1}) async {
    tester.view.physicalSize = physicalSize ?? const Size(1000, 2000);
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
        theme: buildTheme(Locale(lang), palette: ThemePresets.palettes[themeKey]!, key: themeKey),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: w!),
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
      await pump(tester, const CopticDateStrip(location: '/mass-schedule'), features: on, now: cairo(2026, 11, 4, 19));
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

    testWidgets('narrow screen (320px) layout renders without overflow even with long live label', (tester) async {
      final on = FeatureSettings.fromMap({
        'liveEnabled': true,
        'liveUrl': 'https://www.youtube.com/live/abc',
        'liveLabelAr': 'بث مباشر خاص بنهضة عيد الشهيد العظيم مارجرجس الروماني مع نخبة من الآباء الكهنة والخدام',
        'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
      });
      await pump(
        tester,
        const CopticDateStrip(location: '/mass-schedule'),
        features: on,
        now: cairo(2026, 11, 4, 19),
        physicalSize: const Size(320, 600),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('copticDateStrip')), findsOneWidget);
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
    });

    testWidgets('renders cleanly under 200% accessibility text scale', (tester) async {
      final on = FeatureSettings.fromMap({
        'liveEnabled': true,
        'liveUrl': 'https://www.youtube.com/live/abc',
        'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(on),
          featuresReadyProvider.overrideWithValue(true),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 4, 19))),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(body: CopticDateStrip(location: '/mass-schedule')),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('copticDateStrip')), findsOneWidget);
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
    });
  });

  group('top utility bar on the occasion palette (ADR-043 / ADR-044)', () {
    final live = FeatureSettings.fromMap({
      'liveEnabled': true,
      'liveUrl': 'https://www.youtube.com/live/abc',
      'liveEndsAt': DateTime.utc(2026, 11, 4, 19),
    });

    testWidgets('bar, date text and badge take the theme roles on Golden hour and Holy Week', (tester) async {
      for (final key in ['goldenHour', 'holyWeek']) {
        await pump(tester, const CopticDateStrip(location: '/mass-schedule'),
            features: live, now: cairo(2026, 11, 4, 19), themeKey: key);
        final ctx = tester.element(find.byKey(const Key('copticDateStrip')));
        final pal = ctx.pal;
        final deco = tester.widget<Container>(find.byKey(const Key('copticDateStrip'))).decoration! as BoxDecoration;
        expect((deco.gradient! as LinearGradient).colors, [pal.bar, pal.barDeep], reason: key);
        final label = tester.widget<Text>(find.byKey(const Key('copticDateLabel')));
        expect(label.style!.color, pal.onBar, reason: key);
        expect(contrastRatio(pal.onBar.toARGB32(), pal.bar.toARGB32()), greaterThanOrEqualTo(4.5), reason: key);
        final badge = tester.widget<Container>(
            find.descendant(of: find.byKey(const Key('topBarLiveBadge')), matching: find.byType(Container)).first);
        expect((badge.decoration! as BoxDecoration).color, pal.live, reason: key);
        expect(contrastRatio(pal.onLive.toARGB32(), pal.live.toARGB32()), greaterThanOrEqualTo(4.5), reason: key);
      }
      // Holy Week is a dark bar (charcoal), not the Golden-hour maroon.
      await pump(tester, const CopticDateStrip(location: '/'), now: cairo(2026, 11, 4, 10), themeKey: 'holyWeek');
      final hw = tester.element(find.byKey(const Key('copticDateStrip'))).pal;
      expect(hw.bar.computeLuminance(), lessThan(0.05));
    });

    testWidgets('the date keeps the free width next to the badge (Sentry review on PR #35)', (tester) async {
      await pump(tester, const CopticDateStrip(location: '/mass-schedule'),
          features: live, now: cairo(2026, 11, 4, 19), physicalSize: const Size(390, 800));
      final bar = tester.getSize(find.byKey(const Key('copticDateStrip'))).width;
      final badge = tester.getSize(find.byKey(const Key('topBarLiveBadge'))).width;
      expect(badge, lessThanOrEqualTo(150));
      final dateArea = tester.getSize(find.ancestor(of: find.byKey(const Key('copticDateLabel')), matching: find.byType(Expanded)).first);
      expect(dateArea.width, closeTo(bar - 24 - 8 - badge, 1));
      expect(dateArea.width, greaterThan(bar / 2));
    });

    testWidgets('200 % text: the bar grows instead of clipping, capped at 1.6x', (tester) async {
      await pump(tester, const CopticDateStrip(location: '/mass-schedule'),
          features: live, now: cairo(2026, 11, 4, 19), physicalSize: const Size(320, 800), textScale: 2);
      expect(tester.takeException(), isNull);
      final h = tester.getSize(find.byKey(const Key('copticDateStrip'))).height;
      expect(h, greaterThan(32));
      expect(h, 44);
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
      addTearDown(tester.view.reset);
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

    testWidgets('preserves horizontal safe area insets on landscape cutouts', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
          home: const MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.symmetric(horizontal: 44)),
            child: AppShell(location: '/', child: Text('home content')),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('live: banner on Home, badge on the other pages (ADR-044, owner decision)', () {
    Map<String, Object?> liveMap([Map<String, Object?> extra = const {}]) => {
          'liveEnabled': true,
          'liveUrl': 'https://www.youtube.com/live/abc',
          'liveEndsAt': cairo(2026, 11, 4, 21).toUtc(),
          ...extra,
        };

    Future<void> pumpShell(WidgetTester tester, String location, FeatureSettings f) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          featuresProvider.overrideWithValue(f),
          featuresReadyProvider.overrideWithValue(true),
          nowProvider.overrideWith((ref) => Stream.value(cairo(2026, 11, 4, 19))),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AppShell(location: location, child: const Text('page')),
        ),
      ));
      await tester.pump();
    }

    List<String> mockLauncher(WidgetTester tester) {
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments;
        if (args is Map && args['url'] is String) launched.add(args['url'] as String);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      return launched;
    }

    test('liveBadgeOn: hidden on Home by default, shown elsewhere, both with the switch off', () {
      final now = cairo(2026, 11, 4, 19);
      final t = FeatureSettings.fromMap(liveMap()).today;
      expect(t.liveBadgeHideOnHome, isTrue);
      expect(t.liveBadgeOn(now, '/'), isFalse);
      expect(t.liveBadgeOn(now, '/mass-schedule'), isTrue);
      expect(t.liveBadgeOn(now, '/clinics/x'), isTrue);
      final both = FeatureSettings.fromMap(liveMap({'liveBadgeHideOnHome': false})).today;
      expect(both.liveBadgeOn(now, '/'), isTrue);
      // Not live: no badge anywhere.
      expect(t.liveBadgeOn(cairo(2026, 11, 4, 21, 1), '/about'), isFalse);
      // The admin key is read only, never written back by the sections editor.
      expect(FeatureSettings.fromMap(liveMap({'liveBadgeHideOnHome': false})).toMap().containsKey('liveBadgeHideOnHome'),
          isFalse);
    });

    testWidgets('Home: only the red banner (badge hidden while the banner shows)', (tester) async {
      await pumpShell(tester, '/', FeatureSettings.fromMap(liveMap()));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('liveStreamBanner')), findsOneWidget);
      expect(find.text('شاهد البث'), findsOneWidget);
      expect(find.byKey(const Key('topBarLiveBadge')), findsNothing);
      // The Coptic date still shows in the bar (copticStrip = all).
      expect(find.byKey(const Key('copticDateStrip')), findsOneWidget);
    });

    testWidgets('Home with the date strip off: no empty bar is left behind', (tester) async {
      await pumpShell(tester, '/', FeatureSettings.fromMap(liveMap({'copticStrip': 'off'})));
      expect(find.byKey(const Key('copticDateStrip')), findsNothing);
      expect(find.byKey(const Key('topBarLiveBadge')), findsNothing);
      expect(find.byKey(const Key('liveStreamBanner')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('sealTabHome'))).dy, 0.0);
    });

    testWidgets('other pages: the badge shows in the top bar', (tester) async {
      for (final loc in ['/mass-schedule', '/about']) {
        await pumpShell(tester, loc, FeatureSettings.fromMap(liveMap()));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget, reason: loc);
      }
      // Home-only strip: on other pages the bar still appears for the badge alone.
      await pumpShell(tester, '/mass-schedule', FeatureSettings.fromMap(liveMap({'copticStrip': 'home'})));
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
      expect(find.byKey(const Key('copticDateLabel')), findsNothing);
    });

    testWidgets('the badge opens the stream: tap, keyboard (Tab + Enter) and screen readers', (tester) async {
      await pumpShell(tester, '/mass-schedule', FeatureSettings.fromMap(liveMap()));
      final launched = mockLauncher(tester);
      await tester.tap(find.byKey(const Key('topBarLiveBadge')));
      await tester.pump();
      expect(launched, ['https://www.youtube.com/live/abc']);

      // Keyboard: the badge takes focus and Enter activates it.
      final badgeFocus = Focus.of(tester.element(find.descendant(
          of: find.byKey(const Key('topBarLiveBadge')), matching: find.byType(Container)).first));
      badgeFocus.requestFocus();
      await tester.pump();
      expect(badgeFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(launched, ['https://www.youtube.com/live/abc', 'https://www.youtube.com/live/abc']);

      // Screen readers: a button named «مباشر — شاهد البث» with a tap action.
      final sem = find.bySemanticsLabel('مباشر — شاهد البث');
      expect(sem, findsOneWidget);
      final data = tester.getSemantics(sem).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('switch off: Home shows both the banner and the badge', (tester) async {
      await pumpShell(tester, '/', FeatureSettings.fromMap(liveMap({'liveBadgeHideOnHome': false})));
      expect(find.byKey(const Key('liveStreamBanner')), findsOneWidget);
      expect(find.byKey(const Key('topBarLiveBadge')), findsOneWidget);
    });

    testWidgets('not live: neither banner nor badge', (tester) async {
      await pumpShell(tester, '/about', FeatureSettings.defaults);
      expect(find.byKey(const Key('liveStreamBanner')), findsNothing);
      expect(find.byKey(const Key('topBarLiveBadge')), findsNothing);
    });
  });
}
