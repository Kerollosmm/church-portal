// ADR-052: the church milestones («محطات الكنيسة») on the About page, after
// the history & altars, with the same card as Home "Our story"; switch
// settings/features.aboutMilestones (default on) and the milestones section.
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/widgets/milestone_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _Locale extends LocaleNotifier {
  final Locale locale;
  _Locale(this.locale);
  @override
  Locale build() => locale;
}

const _seedIds = ['since-1980', 'deacons-2022', 'hegumens-2022', 'pope-visit'];

Future<GoRouter> _pump(WidgetTester tester,
    {String at = '/about',
    Map<String, bool> sections = const {},
    Map<String, dynamic> features = const {},
    String lang = 'en'}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final f = raw['settings']['features'] as Map;
  (f['sections'] as Map).addAll(sections);
  (raw['settings']['church'] as Map)['altars'] = [
    {'nameAr': 'مذبح القديسين مكسيموس ودوماديوس', 'nameEn': 'Altar of Sts Maximus & Domadius', 'kind': 'main'},
    {'nameAr': 'مذبح الأنبا موسى الأسود', 'nameEn': 'Altar of Anba Moussa the Black', 'kind': 'side'},
  ];
  f.addAll(features);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(SeedData(raw))),
    nowProvider.overrideWith((ref) => Stream.value(CairoTime.at(2026, 11, 6, 12 * 60).toUtc())),
    localeProvider.overrideWith(() => _Locale(Locale(lang))),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Locale(lang)),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  if (at != '/') {
    router.go(at);
    await tester.pumpAndSettle();
  }
  return router;
}

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('About page milestones (ADR-052)', () {
    testWidgets('shown by default after the history & altars, before the saints, in Home order', (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('about-milestones')), findsOneWidget);
      expect(find.text('Church milestones'), findsOneWidget);
      for (final id in _seedIds) {
        expect(find.byKey(ValueKey('aboutCard-$id')), findsOneWidget, reason: id);
      }
      expect(find.byType(MilestoneCard), findsNWidgets(_seedIds.length));
      // Ordered as on Home (by `order`).
      final ys = [for (final id in _seedIds) tester.getTopLeft(find.byKey(ValueKey('aboutCard-$id'))).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThanOrEqualTo(ys[i - 1]), reason: _seedIds[i]);
      }
      final title = tester.getTopLeft(find.byKey(const ValueKey('about-milestones'))).dy;
      expect(tester.getTopLeft(find.text('Altars')).dy, lessThan(title));
      expect(tester.getTopLeft(find.text('Patron saints')).dy, greaterThan(ys.last));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic title «محطات الكنيسة»', (tester) async {
      await _pump(tester, lang: 'ar');
      expect(find.text('محطات الكنيسة'), findsOneWidget);
      expect(find.byType(MilestoneCard), findsNWidgets(_seedIds.length));
    });

    testWidgets('hidden when aboutMilestones is off (Home keeps its block)', (tester) async {
      final router = await _pump(tester, features: const {'aboutMilestones': false});
      expect(find.byKey(const ValueKey('about-milestones')), findsNothing);
      expect(find.byType(MilestoneCard), findsNothing);
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeMilestone-pope-visit')), findsOneWidget);
    });

    testWidgets('hidden when the milestones section is off (Home block too)', (tester) async {
      final router = await _pump(tester, sections: const {'milestones': false});
      expect(find.byKey(const ValueKey('about-milestones')), findsNothing);
      expect(find.byType(MilestoneCard), findsNothing);
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.byType(MilestoneCard), findsNothing);
    });

    testWidgets('Home "Our story" unchanged: same cards, own home-blocks switch', (tester) async {
      await _pump(tester, at: '/');
      expect(find.text('Our story'), findsWidgets);
      for (final id in _seedIds) {
        expect(find.byKey(ValueKey('homeMilestone-$id')), findsOneWidget, reason: id);
      }
      // Home block hidden by the admin: About still lists the milestones.
      final again = await _pump(tester, features: const {'homeHidden': ['milestones']});
      expect(find.byType(MilestoneCard), findsNWidgets(_seedIds.length));
      again.go('/');
      await tester.pumpAndSettle();
      expect(find.byType(MilestoneCard), findsNothing);
    });
  });

  group('settings/features.aboutMilestones', () {
    test('default on; parsed; only a bool counts', () {
      expect(FeatureSettings.defaults.aboutMilestones, isTrue);
      expect(FeatureSettings.defaults.showAboutMilestones, isTrue);
      expect(FeatureSettings.fromMap(const {'aboutMilestones': false}).aboutMilestones, isFalse);
      expect(FeatureSettings.fromMap(const {'aboutMilestones': 'no'}).aboutMilestones, isTrue);
      expect(const FeatureSettings(sections: {'milestones': false}).showAboutMilestones, isFalse);
      expect(const FeatureSettings().copyWith(aboutMilestones: false).aboutMilestones, isFalse);
      final off = const FeatureSettings(aboutMilestones: false);
      expect(off.effectiveAt(DateTime.utc(2030)).aboutMilestones, isFalse);
    });

    test('saved only when off or already stored; rules allow a bool', () {
      final on = featuresSaveWrites(const FeatureSettings(), const {}).first;
      expect(on.containsKey('aboutMilestones'), isFalse, reason: 'rules that predate the key keep accepting saves');
      final off = featuresSaveWrites(const FeatureSettings(aboutMilestones: false), const {}).first;
      expect(off['aboutMilestones'], isFalse);
      final back = featuresSaveWrites(const FeatureSettings(), const {'aboutMilestones': false}).first;
      expect(back['aboutMilestones'], isTrue);
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules.substring(rules.indexOf('function validFeatures(')), contains("'aboutMilestones'"));
      expect(rules, contains("d.get('aboutMilestones', true) is bool"));
    });
  });

  testWidgets('admin: the switch under the milestones section saves aboutMilestones; disabled while the section is off',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FeatureSettings? saved;
    Widget app(FeatureSettings initial) => MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: FeaturesEditor(key: ObjectKey(initial), initial: initial, onSave: (f) async => saved = f)),
        );
    await tester.pumpWidget(app(FeatureSettings.defaults));
    await tester.pumpAndSettle();
    final sw = find.byKey(const ValueKey('features-aboutMilestones'));
    expect(find.text('Also on the About page'), findsOneWidget);
    // Right under the milestones section switch.
    expect(tester.getTopLeft(sw).dy, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('section-milestones'))).dy));
    expect(tester.getTopLeft(sw).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('section-saints'))).dy));
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    await tester.tap(find.byKey(const Key('features-save')));
    await tester.pumpAndSettle();
    expect(saved!.aboutMilestones, isFalse);

    await tester.pumpWidget(app(const FeatureSettings(sections: {'milestones': false})));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('features-aboutMilestones'))).onChanged, isNull);
  });
}
