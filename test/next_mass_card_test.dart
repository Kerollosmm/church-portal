import 'dart:async';

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/remind_me.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(CairoTime.ensureInitialized);

  final sampleSeed = SeedData(const {
    'liturgies': [
      {
        'id': 'seed-l1',
        'type': 'mass',
        'nameAr': 'قداس البذرة الوهمي',
        'nameEn': 'Fake Seed Mass',
        'weekday': 7,
        'start': '08:00',
        'end': '10:00',
      },
    ],
  });

  // Match whichever weekday CairoTime.now() is on so MassSchedulePage's initial
  // tab always contains this liturgy without relying on wall-clock day.
  Liturgy todayLiturgy() {
    final nowCairo = CairoTime.now();
    return Liturgy(
      id: 'live-l1',
      type: 'mass',
      nameAr: 'قداس اليوم الحي',
      nameEn: 'Live Today Mass',
      weekday: nowCairo.weekday,
      start: '07:00',
      end: '09:30',
    );
  }

  List<dynamic> baseOverrides({
    required dynamic liturgiesOverride,
    required dynamic seasonsOverride,
  }) =>
      [
        repositoryProvider.overrideWithValue(SeedRepository(sampleSeed)),
        liturgiesOverride,
        seasonsOverride,
        nowProvider.overrideWithValue(AsyncData(CairoTime.at(2026, 11, 22, 6 * 60))),
        settingsProvider.overrideWithValue(
            const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A'))),
        featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
        customPagesProvider.overrideWithValue(const AsyncData(<CustomPage>[])),
      ];

  Widget wrap(Widget child, List<dynamic> overrides, {Locale locale = const Locale('ar')}) => ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('NextMassCard renders liturgy without blocking when seasonsProvider never emits', (tester) async {
    final lit = todayLiturgy();
    for (final (width, locale, expectedName) in [
      (320.0, const Locale('ar'), 'قداس اليوم الحي'),
      (1400.0, const Locale('en'), 'Live Today Mass'),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(
        const SingleChildScrollView(child: NextMassCard()),
        baseOverrides(
          liturgiesOverride: liturgiesProvider.overrideWithValue(AsyncData([lit])),
          seasonsOverride: seasonsProvider.overrideWith((_) => const Stream<List<Season>>.empty()),
        ),
        locale: locale,
      ));
      await tester.pump();

      expect(find.textContaining(expectedName), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('MassSchedulePage weekly view renders schedule without blocking when seasonsProvider never emits',
      (tester) async {
    final lit = todayLiturgy();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      const MassSchedulePage(),
      baseOverrides(
        liturgiesOverride: liturgiesProvider.overrideWithValue(AsyncData([lit])),
        seasonsOverride: seasonsProvider.overrideWith((_) => const Stream<List<Season>>.empty()),
      ),
    ));
    await tester.pump();

    expect(find.byType(SkeletonList), findsNothing);
    expect(find.byType(LiturgyCard), findsOneWidget);
    expect(find.text('قداس اليوم الحي'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NextMassCard and MassSchedulePage show ErrorState + retry (never seed) on liturgies timeout',
      (tester) async {
    final lit = todayLiturgy();
    var attempts = 0;
    var shouldFail = true;
    final ctl = StreamController<List<Liturgy>>.broadcast();
    addTearDown(ctl.close);

    final overrides = baseOverrides(
      liturgiesOverride: liturgiesProvider.overrideWith((_) {
        attempts++;
        if (shouldFail) {
          return Stream<List<Liturgy>>.error(TimeoutException('timed out'));
        }
        return ctl.stream;
      }),
      seasonsOverride: seasonsProvider.overrideWith((_) => const Stream<List<Season>>.empty()),
    );

    await tester.pumpWidget(wrap(const MassSchedulePage(), overrides));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ErrorState), findsNWidgets(2));
    expect(find.text('إعادة المحاولة'), findsNWidgets(2));
    expect(find.textContaining('قداس البذرة الوهمي'), findsNothing);

    shouldFail = false;
    final beforeTap = attempts;
    await tester.ensureVisible(find.text('إعادة المحاولة').first);
    await tester.tap(find.text('إعادة المحاولة').first);
    await tester.pump();
    expect(attempts, beforeTap + 1);

    ctl.add([lit]);
    await tester.pumpAndSettle();
    expect(find.text('قداس اليوم الحي'), findsWidgets);
    expect(find.byType(ErrorState), findsNothing);
  });

  testWidgets('MassSchedulePage surfaces seasons error notice on weekly view, ErrorState on card and seasonal view',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lit = todayLiturgy();
    await tester.pumpWidget(wrap(
      const MassSchedulePage(),
      baseOverrides(
        liturgiesOverride: liturgiesProvider.overrideWithValue(AsyncData([lit])),
        seasonsOverride: seasonsProvider.overrideWith((_) => Stream<List<Season>>.error(TimeoutException('seasons'))),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Weekly schedule stays unblocked while surfacing seasons unavailability notice; NextMassCard waits/errors safely.
    expect(find.byType(LiturgyCard), findsOneWidget);
    expect(find.byKey(const Key('seasonsErrorNotice')), findsOneWidget);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Toggle seasonal switch ON -> shows ErrorState + retry instead of fake empty state.
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.byType(ErrorState), findsNWidgets(2));
    expect(find.byKey(const Key('noCurrentSeasons')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LiturgyCard computes RemindMeButton.startsAt from nowProvider', (tester) async {
    const sundayMass = Liturgy(
      id: 'sun-1',
      type: 'mass',
      nameAr: 'قداس الأحد',
      nameEn: 'Sunday Mass',
      weekday: 7,
      start: '08:00',
      end: '10:00',
    );
    final clock = StreamController<DateTime>.broadcast();
    addTearDown(clock.close);

    final overrides = [
      repositoryProvider.overrideWithValue(SeedRepository(sampleSeed)),
      nowProvider.overrideWith((_) => clock.stream),
      settingsProvider.overrideWithValue(
          const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A'))),
      featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
    ];

    await tester.pumpWidget(wrap(const LiturgyCard(liturgy: sundayMass), overrides));
    clock.add(CairoTime.at(2026, 11, 22, 7 * 60)); // Sunday 07:00 Cairo -> today 08:00
    await tester.pump();
    await tester.pump();

    var btn = tester.widget<RemindMeButton>(find.byType(RemindMeButton));
    expect(btn.startsAt, CairoTime.at(2026, 11, 22, 8 * 60));

    // Minute ticker moves past 08:00 -> rolls forward to next Sunday 2026-11-29 08:00.
    clock.add(CairoTime.at(2026, 11, 22, 9 * 60));
    await tester.pump();
    await tester.pump();

    btn = tester.widget<RemindMeButton>(find.byType(RemindMeButton));
    expect(btn.startsAt, CairoTime.at(2026, 11, 29, 8 * 60));
  });
}
