import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/readings_page.dart';
import 'package:church_portal/ui/widgets/app_shell.dart';
import 'package:church_portal/ui/widgets/golden.dart';

class FakeInstallEnv implements InstallEnv {
  @override
  String userAgent;
  @override
  String platform;
  @override
  int maxTouchPoints;
  @override
  bool isStandalone;
  @override
  bool hasDeferredPrompt;
  @override
  bool installedEventReceived;
  final Map<String, dynamic> storage;

  FakeInstallEnv({
    this.userAgent = 'TestAgent',
    this.platform = 'Linux armv8l',
    this.maxTouchPoints = 5,
    this.isStandalone = false,
    this.hasDeferredPrompt = false,
    this.installedEventReceived = false,
    Map<String, dynamic>? storage,
  }) : storage = storage ?? {};

  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};

  @override
  void clearInstalledSessionFlag() {
    installedEventReceived = false;
  }

  @override
  Future<bool> promptInstall() async => true;

  @override
  Map<String, dynamic>? readJson(String key) => storage[key] as Map<String, dynamic>?;

  @override
  void writeJson(String key, Map<String, dynamic> data) {
    storage[key] = data;
  }

  @override
  void remove(String key) {
    storage.remove(key);
  }
}

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
          'introEn': 'A Psalm of David',
          'textAr':
              'يَارَبُّ، طَأْطِئْ سَمَاوَاتِكَ وَٱنْزِلْ، ٱلْمِسِ ٱلْجِبَالَ فَتُدَخِّنَ. أَبْرِقْ بُرُوقًا وَبَدِّدْهُمْ، أَرْسِلْ سِهَامَكَ وَأَزْعِجْهُمْ.',
          'textEn': 'Bow down Your heavens, O LORD, and come down.',
          'conclusionAr': 'هللويا',
          'conclusionEn': 'Alleluia',
        },
        {
          'kind': 'gospel',
          'titleAr': 'الإنجيل',
          'titleEn': 'Gospel',
          'refAr': 'لوقا 7:36-50',
          'refEn': 'Luke 7:36-50',
          'introAr': '',
          'introEn': '',
          'textAr': 'وَسَأَلَهُ وَاحِدٌ مِنَ ٱلْفَرِّيسِيِّينَ أَنْ يَأْكُلَ مَعَهُ، فَدَخَلَ بَيْتَ ٱلْفَرِّيسِيِّ وَٱتَّكَأَ.',
          'textEn': 'Then one of the Pharisees asked Him to eat with him.',
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
          'introEn': 'A chapter from the epistle of Paul',
          'textAr': 'إِذًا مَا هُوَ فَضْلُ ٱلْيَهُودِيِّ، أَوْ مَا هُوَ نَفْعُ ٱلْخِتَانِ؟ كَثِيرٌ عَلَى كُلِّ وَجْهٍ!',
          'textEn': 'What advantage then has the Jew, or what is the profit of circumcision?',
          'conclusionAr': 'نعمة الله الآب فلتحل معكم',
          'conclusionEn': 'The grace of God the Father be with you',
        },
        {
          'kind': 'gospel',
          'titleAr': 'الإنجيل',
          'titleEn': 'Gospel',
          'refAr': 'يوحنا 15:1-12',
          'refEn': 'John 15:1-12',
          'introAr': '',
          'introEn': '',
          'textAr':
              'أَنَا ٱلْكَرْمَةُ ٱلْحَقِيقِيَّةُ وَأَبِي ٱلْكَرَّامُ. كُلُّ غُصْنٍ فِيَّ لَا يَأْتِي بِثَمَرٍ يَنْزِعُهُ.',
          'textEn': 'I am the true vine, and My Father is the vinedresser.',
          'conclusionAr': 'والمجد لله دائماً',
          'conclusionEn': 'Glory to God forever',
        },
      ],
    },
  ],
  'source': 'api.katameros.app',
  'bibleAr': 'Van Dyck',
  'bibleEn': 'refs-only',
};

Widget buildTestWidget({
  required FakeInstallEnv installEnv,
  String dateIso = '2026-11-08',
  String? initialTab,
  Locale locale = const Locale('ar'),
}) {
  return ProviderScope(
    overrides: [
      installEnvProvider.overrideWithValue(installEnv),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(locale),
      home: Scaffold(
        body: ReadingsPage(
          dateIso: dateIso,
          initialTab: initialTab,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    CairoTime.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'church_portal_readings_2026-11-08': jsonEncode(sampleFixture),
      'church_portal_readings_2026-11-07': jsonEncode(sampleFixture),
      'church_portal_readings_2026-11-09': jsonEncode(sampleFixture),
    });
  });

  group('Arrow button navigation', () {
    testWidgets('prevDayButton and nextDayButton use proper directional icons and shift date',
        (tester) async {
      final env = FakeInstallEnv();
      await tester.pumpWidget(buildTestWidget(installEnv: env, dateIso: '2026-11-08'));
      await tester.pumpAndSettle();

      final prevBtn = find.byKey(const Key('prevDayButton'));
      final nextBtn = find.byKey(const Key('nextDayButton'));

      expect(prevBtn, findsOneWidget);
      expect(nextBtn, findsOneWidget);

      final prevIcon = tester.widget<Icon>(find.descendant(of: prevBtn, matching: find.byType(Icon)));
      final nextIcon = tester.widget<Icon>(find.descendant(of: nextBtn, matching: find.byType(Icon)));

      expect(prevIcon.icon, Icons.arrow_back_rounded);
      expect(nextIcon.icon, Icons.arrow_forward_rounded);
      expect(prevIcon.icon?.matchTextDirection, isTrue);
      expect(nextIcon.icon?.matchTextDirection, isTrue);

      // Verify date displayed initially
      expect(find.textContaining('2026-11-08'), findsOneWidget);

      // Tap prevDayButton -> shifts to 2026-11-07
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-11-07'), findsOneWidget);

      // Tap nextDayButton -> shifts back to 2026-11-08
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-11-08'), findsOneWidget);
    });
  });

  group('Font scaling', () {
    testWidgets('scales between 0.85 and 2.0 and persists to InstallEnv', (tester) async {
      final env = FakeInstallEnv();
      await tester.pumpWidget(buildTestWidget(installEnv: env, dateIso: '2026-11-08'));
      await tester.pumpAndSettle();

      final minusBtn = find.byKey(const Key('fontSizeMinus'));
      final plusBtn = find.byKey(const Key('fontSizePlus'));
      final resetBtn = find.byKey(const Key('fontSizeReset'));

      expect(minusBtn, findsOneWidget);
      expect(plusBtn, findsOneWidget);
      expect(resetBtn, findsOneWidget);

      // Default scale is 1.0 -> 100%
      expect(find.text('100%'), findsOneWidget);

      // Tap plus -> scale increases to 1.15
      await tester.tap(plusBtn);
      await tester.pumpAndSettle();
      expect(find.text('115%'), findsOneWidget);
      expect(env.storage[readingFontScaleStorageKey], {'scale': 1.15});
      expect(env.storage[readingPrefsStorageKey], {'scale': 1.15});

      // Tap reset -> resets to 100%
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(env.storage[readingFontScaleStorageKey], {'scale': 1.0});

      // Tap minus -> scale decreases to 0.85
      await tester.tap(minusBtn);
      await tester.pumpAndSettle();
      expect(find.text('85%'), findsOneWidget);
      expect(env.storage[readingFontScaleStorageKey], {'scale': 0.85});

      // At 0.85, minus is disabled
      final minusWidget = tester.widget<IconButton>(minusBtn);
      expect(minusWidget.onPressed, isNull);

      // Increase to max 2.0 (85% -> 100% -> 115% -> 130% -> 145% -> 160% -> 175% -> 190% -> 200%)
      for (var i = 0; i < 9; i++) {
        await tester.tap(plusBtn);
        await tester.pumpAndSettle();
      }
      expect(find.text('200%'), findsOneWidget);
      expect(env.storage[readingFontScaleStorageKey], {'scale': 2.0});

      // At 2.0, plus is disabled
      final plusWidget = tester.widget<IconButton>(plusBtn);
      expect(plusWidget.onPressed, isNull);
    });
  });

  group('Responsive layouts', () {
    for (final width in [320.0, 400.0, 1400.0]) {
      for (final isAr in [true, false]) {
        testWidgets('renders cleanly at width ${width.toInt()}px in ${isAr ? "Arabic (RTL)" : "English (LTR)"} at 2.0x scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final env = FakeInstallEnv(storage: {
            readingFontScaleStorageKey: {'scale': 2.0},
          });

          await tester.pumpWidget(buildTestWidget(
            installEnv: env,
            dateIso: '2026-11-08',
            locale: isAr ? const Locale('ar') : const Locale('en'),
          ));
          await tester.pumpAndSettle();

          // Zero overflow errors
          expect(tester.takeException(), isNull);

          // Verify commemoration banner and reading cards are rendered
          expect(find.byKey(const Key('commemoration_item')), findsOneWidget);
          expect(find.byKey(const Key('reading_vespers_0')), findsOneWidget);
        });
      }
    }
  });

  group('Adaptive scroll focus mode', () {
    testWidgets('scrolling down >= 40 dp past 60 px offset activates focus mode, scrolling up deactivates',
        (tester) async {
      final env = FakeInstallEnv();
      final container = ProviderContainer(
        overrides: [
          installEnvProvider.overrideWithValue(env),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: const Scaffold(
              body: ReadingsPage(dateIso: '2026-11-08'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially focus mode is false
      expect(container.read(readerFocusModeProvider), isFalse);

      // Drag down (scroll down = negative delta in drag)
      // Drag by 120 px down past 60 px offset
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(container.read(readerFocusModeProvider), isTrue);

      // Drag up by 60 px (scroll up = positive delta in drag)
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(container.read(readerFocusModeProvider), isFalse);
    });

    testWidgets('AppShell hides and restores chrome during focus mode and resets on route change',
        (tester) async {
      final env = FakeInstallEnv();
      final container = ProviderContainer(
        overrides: [
          installEnvProvider.overrideWithValue(env),
        ],
      );
      addTearDown(container.dispose);

      var location = '/readings/2026-11-08';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: StatefulBuilder(
              builder: (context, setState) {
                return AppShell(
                  location: location,
                  child: const SizedBox(height: 2000),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially in readings route, focus mode is false
      expect(container.read(readerFocusModeProvider), isFalse);
      expect(find.byKey(const Key('sealTabHome')), findsOneWidget);

      // Set focus mode to true
      container.read(readerFocusModeProvider.notifier).setFocus(true);
      await tester.pumpAndSettle();

      // SealTab opacity should be 0.0
      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const Key('sealTabHome')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(animatedOpacity.opacity, 0.0);

      // Set focus mode to false -> restores
      container.read(readerFocusModeProvider.notifier).setFocus(false);
      await tester.pumpAndSettle();

      final restoredOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const Key('sealTabHome')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(restoredOpacity.opacity, 1.0);

      // Activate focus mode again, then change route away from /readings
      container.read(readerFocusModeProvider.notifier).setFocus(true);
      await tester.pumpAndSettle();
      expect(container.read(readerFocusModeProvider), isTrue);

      // Change location to '/'
      location = '/';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: StatefulBuilder(
              builder: (context, setState) {
                return AppShell(
                  location: location,
                  child: const SizedBox(height: 2000),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Route change away from /readings resets focus mode to false
      expect(container.read(readerFocusModeProvider), isFalse);
    });
  });

  group('RepaintBoundary isolation', () {
    testWidgets('WarmBackdrop is wrapped in a RepaintBoundary', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Locale('ar')),
          home: const Scaffold(
            body: WarmBackdrop(),
          ),
        ),
      );
      await tester.pump();

      final backdropFinder = find.byKey(const Key('warmBackdrop'));
      expect(backdropFinder, findsOneWidget);

      final boundaryAncestor = find.ancestor(
        of: backdropFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaryAncestor, findsWidgets);
    });

    testWidgets('HeroVideo subtree uses RepaintBoundary', (tester) async {
      final fileContent = File('lib/ui/widgets/hero_video_io.dart').readAsStringSync();
      expect(fileContent, contains('RepaintBoundary'));
    });
  });
  group('320 px at 2.0x OS text scale + 2.0x reader scale (ADR-061)', () {
    for (final lang in const ['ar', 'en']) {
      testWidgets('Katameros tab at 320x640 with simultaneous 2.0x scales ($lang)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final env = FakeInstallEnv(storage: {
          readingFontScaleStorageKey: {'scale': 2.0},
        });

        await tester.pumpWidget(buildTestWidget(
          installEnv: env,
          dateIso: '2026-11-08',
          locale: Locale(lang),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Header controls scale factor is clamped <= 1.5
        final fontCtrl = tester.element(find.byKey(const Key('fontSizeControl')));
        final headerScaler = MediaQuery.textScalerOf(fontCtrl);
        expect(headerScaler.scale(16) / 16, lessThanOrEqualTo(1.5));

        // Scroll down to bring reading card into view in SliverList
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();

        // Reading card body textScaler is clamped to 2.5 (from 2.0 * 2.0 = 4.0)
        final itemTitle = lang == 'ar' ? 'المزمور' : 'Psalm';
        final cardElement = tester.element(find.text(itemTitle).first);
        expect(MediaQuery.textScalerOf(cardElement), const TextScaler.linear(2.5));
      });

      testWidgets('Verse tab at 320x640 with simultaneous 2.0x scales ($lang)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final env = FakeInstallEnv(storage: {
          readingFontScaleStorageKey: {'scale': 2.0},
        });

        await tester.pumpWidget(buildTestWidget(
          installEnv: env,
          dateIso: '2026-11-08',
          initialTab: 'verse',
          locale: Locale(lang),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Header controls scale factor is clamped <= 1.5
        final fontCtrl = tester.element(find.byKey(const Key('fontSizeControl')));
        final headerScaler = MediaQuery.textScalerOf(fontCtrl);
        expect(headerScaler.scale(16) / 16, lessThanOrEqualTo(1.5));

        // Verse tab body textScaler is clamped to 2.5
        final verseBody = tester.element(find.byType(SingleChildScrollView));
        expect(MediaQuery.textScalerOf(verseBody), const TextScaler.linear(2.5));
      });
    }
  });
}
