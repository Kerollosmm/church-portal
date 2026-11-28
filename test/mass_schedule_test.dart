import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/ics_download.dart' show debugOnIcsDownload;
import 'package:church_portal/ui/widgets/remind_me.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    CairoTime.ensureInitialized();
    await RemindMeButton.preloadSheetForTest();
  });

  baseOverrides() => [
        repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
        liturgiesProvider.overrideWithValue(const AsyncData(<Liturgy>[
          Liturgy(
            id: 'l1',
            type: 'mass',
            nameAr: 'قداس الأحد',
            nameEn: 'Sunday Mass',
            weekday: 7,
            start: '07:00',
            end: '09:30',
          ),
        ])),
        seasonsProvider.overrideWithValue(const AsyncData(<Season>[])),
        nowProvider.overrideWithValue(AsyncData(CairoTime.at(2026, 11, 22, 6 * 60))),
        settingsProvider.overrideWithValue(
            const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A'))),
        featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
        customPagesProvider.overrideWithValue(const AsyncData(<CustomPage>[])),
      ];

  testWidgets(
      'NextMassCard shows Full schedule by default outside GoRouter and on /, and hides it when disabled or on /mass-schedule',
      (tester) async {
    // 1. Outside GoRouter -> shows link by default without throwing; explicit false hides it.
    for (final showLink in [true, false]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: NextMassCard(showFullScheduleLink: showLink)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('الجدول الكامل'), showLink ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }

    // 2. Inside GoRouter at '/' -> shows link; at '/mass-schedule' (both MassSchedulePage & bare NextMassCard) -> hides link.
    for (final path in ['/', '/mass-schedule']) {
      for (final width in [320.0, 400.0, 1400.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final router = GoRouter(
          initialLocation: path,
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: NextMassCard())),
            GoRoute(path: '/mass-schedule', builder: (_, _) => const Scaffold(body: MassSchedulePage())),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: MaterialApp.router(
              locale: width == 320.0 ? const Locale('en') : const Locale('ar'),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expectedLabel = width == 320.0 ? 'Full schedule' : 'الجدول الكامل';
        expect(
          find.text(expectedLabel),
          path == '/' ? findsOneWidget : findsNothing,
          reason: 'path=$path width=$width',
        );
        expect(tester.takeException(), isNull);
      }
    }

    // 3. Bare NextMassCard() inside GoRouter at /mass-schedule also hides the link via GoRouter.maybeOf.
    final directRouter = GoRouter(
      initialLocation: '/mass-schedule',
      routes: [
        GoRoute(path: '/mass-schedule', builder: (_, _) => const Scaffold(body: NextMassCard())),
      ],
    );
    addTearDown(directRouter.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp.router(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: directRouter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الجدول الكامل'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regular schedule day-tab ChoiceChips wrap cleanly without clipping at 360 px (AR & EN)', (tester) async {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: MassSchedulePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'locale=${locale.languageCode}');
      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(5));
      for (var i = 0; i < 5; i++) {
        final rect = tester.getRect(chips.at(i));
        expect(rect.left, greaterThanOrEqualTo(0.0), reason: 'chip $i clipped on left ($locale)');
        expect(rect.right, lessThanOrEqualTo(360.0), reason: 'chip $i clipped on right ($locale)');
      }
      final otherLabel = locale.languageCode == 'ar' ? 'باقي الأيام' : 'Other days';
      expect(find.text(otherLabel), findsOneWidget);
      await tester.tap(find.text(otherLabel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('MassSchedulePage per-service Add to calendar exports weekly RRULE or dated single event (.ics on web, Google Calendar on native)',
      (tester) async {
    final downloaded = <({String content, String filename})>[];
    debugOnIcsDownload = (content, filename) => downloaded.add((content: content, filename: filename));
    addTearDown(() => debugOnIcsDownload = null);

    final launched = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments;
      if (args is Map && args['url'] is String) launched.add(args['url'] as String);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => debugCalendarIsWeb = null);

    final nowCairo = CairoTime.now();
    final weekly = Liturgy(
      id: 'weekly-mass',
      type: 'mass',
      nameAr: 'قداس أسبوعي',
      nameEn: 'Weekly Mass',
      weekday: nowCairo.weekday,
      start: '08:00',
      end: '10:00',
      placeAr: 'الكنيسة الكبرى',
      placeEn: 'Main church',
    );
    final dated = Liturgy(
      id: 'dated-feast',
      type: 'mass',
      nameAr: 'قداس عيد خاص',
      nameEn: 'Special Feast Mass',
      date: DateTime(nowCairo.year, nowCairo.month, nowCairo.day).add(const Duration(days: 2)),
      start: '09:00',
      end: '11:30',
      placeAr: 'المذبح الرئيسي',
      placeEn: 'Main altar',
    );

    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
          liturgiesProvider.overrideWithValue(AsyncData([weekly, dated])),
          seasonsProvider.overrideWithValue(const AsyncData(<Season>[])),
          nowProvider.overrideWithValue(AsyncData(CairoTime.at(nowCairo.year, nowCairo.month, nowCairo.day, 6 * 60))),
          settingsProvider.overrideWithValue(
              const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A'))),
          featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
          customPagesProvider.overrideWithValue(const AsyncData(<CustomPage>[])),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: MassSchedulePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final weeklyBtn = find.byKey(const ValueKey('liturgyCalendar-weekly-mass'));
    final datedBtn = find.byKey(const ValueKey('liturgyCalendar-dated-feast'));
    expect(weeklyBtn, findsOneWidget);
    expect(datedBtn, findsOneWidget);

    // Web: weekly emits RRULE + TZID=Africa/Cairo; dated emits single UTC event without RRULE.
    debugCalendarIsWeb = true;
    await tester.ensureVisible(weeklyBtn);
    await tester.pumpAndSettle();
    await tester.tap(weeklyBtn);
    await tester.pumpAndSettle();
    expect(downloaded, hasLength(1));
    expect(downloaded.last.filename, 'liturgy_weekly-mass.ics');
    expect(downloaded.last.content, contains('RRULE:FREQ=WEEKLY;BYDAY='));
    expect(downloaded.last.content, contains('DTSTART;TZID=Africa/Cairo:'));

    await tester.ensureVisible(datedBtn);
    await tester.pumpAndSettle();
    await tester.tap(datedBtn);
    await tester.pumpAndSettle();
    expect(downloaded, hasLength(2));
    expect(downloaded.last.filename, 'liturgy_dated-feast.ics');
    expect(downloaded.last.content, isNot(contains('RRULE:')));
    expect(downloaded.last.content, contains('DTSTART:'));
    expect(launched, isEmpty);

    // Native Android: weekly includes recur; dated omits recur.
    debugCalendarIsWeb = false;
    await tester.ensureVisible(weeklyBtn);
    await tester.pumpAndSettle();
    await tester.tap(weeklyBtn);
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(Uri.parse(launched.last).queryParameters['recur'], startsWith('RRULE:FREQ=WEEKLY;BYDAY='));

    await tester.ensureVisible(datedBtn);
    await tester.pumpAndSettle();
    await tester.tap(datedBtn);
    await tester.pumpAndSettle();
    expect(launched, hasLength(2));
    expect(Uri.parse(launched.last).queryParameters['recur'], isNull);
    expect(Uri.parse(launched.last).queryParameters['ctz'], 'Africa/Cairo');
  });
}
