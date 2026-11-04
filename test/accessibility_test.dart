import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/app.dart';
import 'package:church_portal/core/launch.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/admin_repository.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/media_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/admin/admin_page.dart';
import 'package:church_portal/ui/admin/admin_schema.dart';
import 'package:church_portal/ui/admin/admin_screens.dart';
import 'package:church_portal/ui/admin/admin_validators.dart';
import 'package:church_portal/ui/admin/collection_list.dart';
import 'package:church_portal/ui/admin/doc_editor.dart';
import 'package:church_portal/ui/admin/features_editor.dart';
import 'package:church_portal/ui/pages/assistant_page.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:church_portal/ui/widgets/common.dart';
import 'package:church_portal/ui/widgets/golden.dart';
import 'package:church_portal/ui/widgets/map_embed.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// WCAG contrast maths (relative luminance, WCAG 2.x definition).
// ---------------------------------------------------------------------------

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] with its alpha composited over the opaque [bg].
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Primaries of the presets on the Golden hour scene (the accent-only
/// presets). Occasion presets with their own scene (Holy Week, the
/// Resurrection…) are covered by test/occasion_theme_test.dart.
final _goldenScene = [
  for (final p in ThemePresets.palettes.values)
    if (p.background == ThemePresets.goldenHourPalette.background) p.primary,
];

const _publicRoutes = [
  '/',
  '/about',
  '/mass-schedule',
  '/church-education',
  '/church-activities',
  '/clinics',
  '/public-services',
  '/contact',
  '/ask',
];

/// Seed with every section on, plus an alert pointing at an in-app route and
/// a departed father with a repose date (fixtures for BUG-08 / BUG-09).
Map<String, dynamic> _raw({Map<String, bool> sections = const {}, String theme = 'burgundy'}) {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  final features = Map<String, dynamic>.from(raw['settings']['features'] as Map);
  features['sections'] = {...(features['sections'] as Map), 'clinics': true, ...sections};
  features['theme'] = theme;
  raw['settings']['features'] = features;
  return raw;
}

SeedData _seed({Map<String, bool> sections = const {}, String theme = 'burgundy', bool fixtures = false}) {
  final raw = _raw(sections: sections, theme: theme);
  if (fixtures) {
    final alerts = raw['alerts'] as Map<String, dynamic>;
    final base = Map<String, dynamic>.from(alerts['follow-announcements'] as Map);
    raw['alerts'] = {
      'internal-clinics': {
        ...base,
        'titleAr': 'تنبيه العيادات',
        'titleEn': 'Clinics notice',
        'bodyAr': '',
        'bodyEn': '',
        'link': '/clinics',
      },
    };
    (raw['priests'] as Map<String, dynamic>)['test-departed'] = {
      'name': 'القمص تجربة',
      'nameEn': 'Fr. Test',
      'rank': 'hegumen',
      'status': 'departed',
      'departedDate': '1990-05-01',
      'order': 1010,
    };
    // A serving priest with a stale repose date (status changed in /admin).
    (raw['priests'] as Map<String, dynamic>)['test-serving'] = {
      'name': 'القس تجربة',
      'nameEn': 'Fr. Serving',
      'rank': 'priest',
      'status': 'serving',
      'departedDate': '1991-02-02',
      'order': 990,
    };
  }
  return SeedData(raw);
}

class _FixedLocale extends LocaleNotifier {
  final Locale locale;
  _FixedLocale(this.locale);
  @override
  Locale build() => locale;
}

final _now = CairoTime.at(2026, 11, 1, 12 * 60).toUtc(); // Sunday 1 Nov 2026, 12:00 Cairo

Future<(GoRouter, ProviderContainer)> _pumpApp(
  WidgetTester tester, {
  SeedData? seed,
  Size size = const Size(320, 800),
  double textScale = 1.0,
  Locale? locale = const Locale('en'),
  Color primary = AppColors.burgundy,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(SeedRepository(seed ?? _seed())),
    nowProvider.overrideWith((ref) => Stream.value(_now)),
    if (locale != null) localeProvider.overrideWith(() => _FixedLocale(locale)),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final l = ref.watch(localeProvider);
        return MaterialApp.router(
          locale: l,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(l, primary: primary),
          routerConfig: router,
        );
      },
    ),
  ));
  await tester.pumpAndSettle();
  return (router, container);
}

String _location(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

/// Simulates the platform reporting a URL (browser Back/Forward, deep link).
Future<void> _platformPush(WidgetTester tester, String location) async {
  final message = const JSONMethodCodec()
      .encodeMethodCall(MethodCall('pushRouteInformation', {'location': location, 'state': null}));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// In-memory admin backend for the screens' stream / save behaviour.
class _FakeBackend extends AdminBackend {
  final watched = <String>[];
  final Map<String, StreamController<AdminDoc?>> _docs = {};
  final Map<String, Map<String, dynamic>> _data = {};
  List<String>? reordered;
  int? reorderedBase;

  _FakeBackend({Map<String, Map<String, dynamic>> docs = const {}}) {
    _data.addAll({for (final e in docs.entries) e.key: {...e.value}});
  }

  @override
  String get actor => 'admin@example.org';

  @override
  Stream<List<AdminDoc>> watch(String collection) {
    watched.add(collection);
    return Stream.value(const []);
  }

  @override
  Stream<AdminDoc?> watchDoc(String path) {
    watched.add(path);
    final c = _docs[path] = StreamController<AdminDoc?>();
    c.add(_data[path] == null ? null : AdminDoc(path.split('/').last, _data[path]!));
    return c.stream;
  }

  @override
  Future<void> saveDoc(String path, Map<String, dynamic> data) async {
    final next = _data[path] = {
      ...?_data[path],
      ...data,
      'updatedAt': DateTime.utc(2026, 11, 1, 10, (_data.length + data.length) % 60),
      'updatedBy': actor,
    };
    _docs[path]?.add(AdminDoc(path.split('/').last, next));
  }

  /// The stored document at [path] (saveDoc replaces each written top-level
  /// field, like AdminRepository's mergeFields).
  Map<String, dynamic>? stored(String path) => _data[path];

  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async => id ?? 'new';
  @override
  Future<void> update(String collection, String id, Map<String, dynamic> data) async {}
  @override
  Future<void> delete(String collection, String id) async {}
  @override
  Future<void> reorder(String collection, List<String> ids, {int base = 0}) async {
    reordered = ids;
    reorderedBase = base;
  }

  @override
  Future<void> setAdmin(String uid, {required String email, required String role}) async {}
  @override
  Future<void> removeAdmin(String uid) async {}
}

Widget _adminApp(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('WCAG AA colour contrast (>= 4.5:1 for text)', () {
    const white = Color(0xFFFFFFFF);

    test('gold text and icons on light surfaces use goldText', () {
      expect(contrast(AppColors.goldText, white), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.goldText, AppColors.cream), greaterThanOrEqualTo(4.5));
      // Decorative gold alone fails, which is why it is not used for text.
      expect(contrast(AppColors.gold, white), lessThan(4.5));
    });

    test('white text on the WhatsApp / Facebook buttons', () {
      expect(contrast(white, whatsappGreen), greaterThanOrEqualTo(4.5));
      expect(contrast(white, facebookBlue), greaterThanOrEqualTo(4.5));
    });

    test('ink and muted body text on cards and the page background', () {
      for (final bg in [white, AppColors.cream, AppColors.parchment]) {
        expect(contrast(AppColors.ink, bg), greaterThanOrEqualTo(4.5));
      }
      // Muted secondary text sits on white cards and the cream background.
      for (final bg in [white, AppColors.cream]) {
        expect(contrast(AppColors.muted, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('every theme preset: primary text on light, white/goldLight on primary, footer text', () {
      for (final e in ThemePresets.all.entries.where((e) => _goldenScene.contains(e.value))) {
        final primary = Color(e.value);
        final dark = Color.lerp(primary, Colors.black, 0.30)!;
        expect(contrast(primary, white), greaterThanOrEqualTo(4.5), reason: '${e.key} on white');
        expect(contrast(primary, AppColors.cream), greaterThanOrEqualTo(4.5), reason: '${e.key} on cream');
        expect(contrast(white, primary), greaterThanOrEqualTo(4.5), reason: 'white on ${e.key}');
        expect(contrast(AppColors.goldLight, primary), greaterThanOrEqualTo(4.5), reason: 'goldLight on ${e.key}');
        // Footer: offline notice (white70), copyright (white54), links (white70).
        expect(contrast(over(Colors.white70, dark), dark), greaterThanOrEqualTo(4.5), reason: 'white70 ${e.key}');
        expect(contrast(over(Colors.white54, dark), dark), greaterThanOrEqualTo(4.5), reason: 'white54 ${e.key}');
        expect(contrast(AppColors.goldLight, dark), greaterThanOrEqualTo(4.5), reason: 'address ${e.key}');
      }
    });

    test('Golden hour: text over imagery sits on panels / scrims that keep AA', () {
      // Translucent panel worst case: composited over the darkest sepia of the art.
      const darkestArt = Color(0xFF4B2E17);
      final panelOverArt = over(AppColors.panel, darkestArt);
      expect(contrast(panelOverArt, AppColors.panelOverDark), lessThan(1.1), reason: 'documented token is accurate');
      for (final bg in [AppColors.cream, AppColors.vellum, AppColors.parchment, panelOverArt]) {
        expect(contrast(AppColors.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink on $bg');
        expect(contrast(AppColors.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
        expect(contrast(AppColors.goldText, bg), greaterThanOrEqualTo(4.5), reason: 'goldText on $bg');
        expect(contrast(AppColors.script, bg), greaterThanOrEqualTo(4.5), reason: 'script on $bg');
        for (final p in _goldenScene) {
          expect(contrast(Color(p), bg), greaterThanOrEqualTo(4.5), reason: 'preset $p on $bg');
        }
      }
      // Sepia story panel (lighter end of its gradient is the worst case for light text; ink is dark).
      for (final bg in const [Color(0xFFE6CFA9), Color(0xFFDDC197)]) {
        expect(contrast(AppColors.ink, bg), greaterThanOrEqualTo(4.5));
      }
      // Title ribbon: cream text on its solid middle.
      expect(contrast(TitleRibbon.textColor, TitleRibbon.fill), greaterThanOrEqualTo(4.5));
      // Hero / header scrim: the centre (0.84 cream) over the darkest art.
      final scrim = over(AppColors.cream.withValues(alpha: 0.84), darkestArt);
      for (final p in _goldenScene) {
        expect(contrast(Color(p), scrim), greaterThanOrEqualTo(4.5), reason: 'title $p on hero scrim');
      }
      expect(contrast(AppColors.script, scrim), greaterThanOrEqualTo(4.5), reason: 'accent on hero scrim');
      // Seal tab / drawer header / badges: light text and icons on every preset.
      for (final p in _goldenScene) {
        final dark = Color.lerp(Color(p), Colors.black, 0.30)!;
        expect(contrast(const Color(0xFFFFF1D6), Color(p)), greaterThanOrEqualTo(4.5));
        expect(contrast(AppColors.goldLight, dark), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('320 px at 200% text: no RenderFlex overflow on any public route', () {
    for (final lang in const ['ar', 'en']) {
      testWidgets('all public routes ($lang)', (tester) async {
        final (router, _) =
            await _pumpApp(tester, seed: _seed(fixtures: true), textScale: 2.0, locale: Locale(lang));
        final failures = <String>[];
        for (final route in _publicRoutes) {
          router.go(route);
          await tester.pumpAndSettle();
          final e = tester.takeException();
          if (e != null) failures.add('$route ($lang): $e');
        }
        expect(failures, isEmpty);
      });
    }

    testWidgets('education timeline at 320 px / 100% wraps instead of overflowing (BUG-11)', (tester) async {
      final (router, _) = await _pumpApp(tester, locale: const Locale('ar'));
      router.go('/church-education');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ThemePresets reach every public widget', () {
    testWidgets('navy preset: no burgundy left on public pages', (tester) async {
      final navy = Color(ThemePresets.all['navy']!);
      final (router, _) = await _pumpApp(tester,
          seed: _seed(theme: 'navy', fixtures: true), size: const Size(1200, 4000), primary: navy);
      final banned = {AppColors.burgundy, AppColors.burgundyDark, AppColors.burgundyLight};
      for (final route in _publicRoutes) {
        router.go(route);
        await tester.pumpAndSettle();
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(banned.contains(t.style?.color), isFalse, reason: '$route text "${t.data}"');
        }
        for (final i in tester.widgetList<Icon>(find.byType(Icon))) {
          expect(banned.contains(i.color), isFalse, reason: '$route icon ${i.icon}');
        }
        for (final c in tester.widgetList<Container>(find.byType(Container))) {
          expect(banned.contains(c.color), isFalse, reason: '$route container');
          final d = c.decoration;
          if (d is BoxDecoration) {
            expect(banned.contains(d.color), isFalse, reason: '$route decoration');
            for (final g in d.gradient?.colors ?? const <Color>[]) {
              expect(banned.contains(g), isFalse, reason: '$route gradient');
            }
          }
        }
      }
      // Golden hour: the footer is a warm panel (preset-independent ground).
      final panel = tester.widget<Container>(find.byKey(const Key('footerPanel')));
      expect((panel.decoration as BoxDecoration).color, OccasionColors.golden.panel);
    });

    testWidgets('ChurchPortalApp maps settings/features.theme to the theme', (tester) async {
      // Tall enough to build the footer below the (taller) Coptic-identity sections.
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navy = Color(ThemePresets.all['navy']!);
      final container = ProviderContainer(overrides: [
        repositoryProvider.overrideWithValue(SeedRepository(_seed(theme: 'navy'))),
        nowProvider.overrideWith((ref) => Stream.value(_now)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ChurchPortalApp()));
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/about');
      await tester.pumpAndSettle();
      final title = find.descendant(of: find.byType(SectionTitle), matching: find.byType(Text)).first;
      expect(Theme.of(tester.element(title)).colorScheme.primary, navy);
      expect(tester.widget<Text>(title).style?.color, navy);
      final panel = tester.widget<Container>(find.byKey(const Key('footerPanel')));
      expect((panel.decoration as BoxDecoration).color, OccasionColors.golden.panel);
    });
  });

  group('screen-reader semantics & touch targets', () {
    testWidgets('mobile subpages have a Back-to-Home button; home does not', (tester) async {
      final (router, _) = await _pumpApp(tester, size: const Size(400, 800));
      expect(find.byKey(const Key('backHome')), findsNothing);
      router.go('/about');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to home'), findsOneWidget);
      await tester.tap(find.byKey(const Key('backHome')));
      await tester.pumpAndSettle();
      expect(_location(router), anyOf('/', '/?lang=en'));
    });

    testWidgets('compact app-bar buttons are at least 48x48 dp', (tester) async {
      await _pumpApp(tester, size: const Size(400, 800));
      // Mass times is the only highlight button; the bar has no Clinics
      // shortcut (owner request, 4 Nov 2026), even with clinics switched on.
      expect(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Clinics')), findsNothing);
      for (final label in ['Mass times', 'Menu']) {
        final button = find.ancestor(of: find.byTooltip(label), matching: find.byType(IconButton)).first;
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('subpage at 360 px / 149 % text: Back arrow and a readable title', (tester) async {
      final (router, _) = await _pumpApp(tester, size: const Size(360, 800), textScale: 1.49);
      router.go('/about');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backHome')), findsOneWidget);
      expect(find.byTooltip('Mass times'), findsNothing); // moved to the drawer
      final title = find.descendant(of: find.byType(AppBar), matching: find.text('St. Maximus & Domadius Church'));
      expect(tester.getSize(title).width, greaterThanOrEqualTo(100));
    });

    testWidgets('below 360 px the highlight buttons move to the drawer', (tester) async {
      await _pumpApp(tester, size: const Size(320, 800));
      expect(find.byTooltip('Mass times'), findsNothing);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(Drawer), matching: find.text('Mass times')), findsOneWidget);
    });

    testWidgets('clinic actions name their clinic; "available today" is one labelled switch', (tester) async {
      final handle = tester.ensureSemantics();
      final (router, _) = await _pumpApp(tester, size: const Size(1200, 3000));
      router.go('/clinics');
      await tester.pumpAndSettle();
      // Seeded clinics have no booking number yet: "Call church office — <clinic>".
      expect(find.bySemanticsLabel(RegExp('^Call church office — .+')), findsWidgets);
      final sw = find.byKey(const Key('availableTodaySwitch'));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(find.descendant(of: sw, matching: find.text('Available today')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
      expect(tester.getSize(sw).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('phone rows name the line in their tooltips', (tester) async {
      await _pumpApp(tester, size: const Size(1200, 3000));
      expect(find.byTooltip(RegExp('^Call — .+')), findsWidgets);
    });

    bool isLiveRegion(Widget w) => w is Semantics && w.properties.liveRegion == true;

    testWidgets('the contact form status is a live region', (tester) async {
      final (router, _) = await _pumpApp(tester, size: const Size(1200, 4000));
      router.go('/contact');
      await tester.pumpAndSettle();
      final form = find.byType(ContactForm);
      final fields = find.descendant(of: form, matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Mina Adel');
      await tester.enterText(fields.at(1), '01012345678');
      await tester.enterText(fields.at(3), 'When is the next youth meeting?');
      await tester.tap(find.descendant(of: form, matching: find.byType(CheckboxListTile))); // PDPL consent
      await tester.pump();
      await tester.tap(find.descendant(of: form, matching: find.byIcon(Icons.send_rounded)));
      await tester.pumpAndSettle();
      // The bundled-data repository cannot send: an error status appears.
      final status = find.descendant(of: form, matching: find.byIcon(Icons.error_outline));
      expect(status, findsOneWidget);
      expect(find.ancestor(of: status, matching: find.byWidgetPredicate(isLiveRegion)), findsOneWidget);
    });

    testWidgets('assistant: labelled send button and a live-region spinner while busy', (tester) async {
      SharedPreferences.setMockInitialValues({}); // the device's daily counter (ADR-031)
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(SeedRepository(_seed())),
          nowProvider.overrideWith((ref) => Stream.value(_now)),
          assistantVisibleProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: AssistantPage()),
        ),
      ));
      await tester.pumpAndSettle();
      final send = find.byTooltip('Send');
      expect(send, findsOneWidget);
      await tester.enterText(find.byType(TextField), 'When is the next liturgy?');
      await tester.tap(send);
      await tester.pump();
      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      final live = find.ancestor(of: spinner, matching: find.byWidgetPredicate(isLiveRegion));
      expect(live, findsOneWidget);
      expect(tester.widget<Semantics>(live).properties.label, 'Sending…');
      await tester.pumpAndSettle(); // no Firebase here: the turn ends with an error message
    });

    testWidgets('ActionChipButton exposes its semantic label as a button', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_adminApp(ActionChipButton(
        icon: Icons.call,
        label: 'Call',
        color: AppColors.burgundy,
        semanticLabel: 'Call — Dental clinic',
        onTap: () => taps++,
      )));
      expect(find.bySemanticsLabel('Call — Dental clinic'), findsOneWidget);
      await tester.tap(find.text('Call'));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('SkeletonBox is static when the OS asks for reduced motion', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(textDirection: TextDirection.ltr, child: SkeletonBox(height: 20, width: 80)),
      ));
      // A running animation would make pumpAndSettle time out.
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(SkeletonBox), matching: find.byType(AnimatedBuilder)), findsNothing);
    });
  });

  group('content fixes', () {
    testWidgets('departed fathers show their repose date (BUG-08)', (tester) async {
      final (router, _) = await _pumpApp(tester, seed: _seed(fixtures: true), size: const Size(1200, 4000));
      router.go('/about');
      await tester.pumpAndSettle();
      expect(find.textContaining('Departed: '), findsWidgets);
      expect(find.textContaining(RegExp('Departed: .*1990')), findsOneWidget);
      expect(find.textContaining(RegExp('Departed: .*1991')), findsNothing); // serving: no repose date
    });

    testWidgets('alert links to a switched-off section are hidden (BUG-09)', (tester) async {
      Finder learnMore() => find.descendant(of: find.byType(AlertBanner), matching: find.text('Learn more'));
      await _pumpApp(tester, seed: _seed(fixtures: true), size: const Size(1200, 3000));
      expect(learnMore(), findsOneWidget);
      await _pumpApp(tester,
          seed: _seed(fixtures: true, sections: const {'clinics': false}), size: const Size(1200, 3000));
      expect(learnMore(), findsNothing);
    });

    testWidgets('secondary time line uses its own script direction (BUG-10)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: TimeRangeText('06:30', '08:30')),
        ),
      );
      final secondary = find.text('06:30 AM – 08:30 AM');
      expect(secondary, findsOneWidget);
      final d = tester.widget<Directionality>(
        find.ancestor(of: secondary, matching: find.byType(Directionality)).first,
      );
      expect(d.textDirection, TextDirection.ltr);
    });

    testWidgets('English times use Latin digits only (live check, ADR-038)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: TimeRangeText('06:30', '08:30')),
        ),
      );
      final texts = tester
          .widgetList<Text>(find.descendant(of: find.byType(TimeRangeText), matching: find.byType(Text)))
          .map((t) => t.data!)
          .toList();
      expect(texts, ['06:30 AM – 08:30 AM']);
      expect(texts.join(), isNot(matches(RegExp('[\u0660-\u0669]'))));
    });

    testWidgets('education shows "Today" on meetings held today (FR-E-03)', (tester) async {
      final raw = _raw();
      final today = (raw['meetings'] as Map).values.where((m) => m['weekday'] == 7 && m['visible'] != false).length;
      final (router, _) = await _pumpApp(tester, size: const Size(1200, 6000));
      router.go('/church-education');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Pill, 'Today'), findsNWidgets(today));
    });

    testWidgets('ChurchMap passes the UI language to the map (BUG-16)', (tester) async {
      final s = SeedData(_raw()).settings;
      expect(mapsEmbedUrl(s), contains('hl=ar'));
      for (final lang in ['ar', 'en']) {
        String? url;
        await tester.pumpWidget(MaterialApp(
          locale: Locale(lang),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChurchMap(settings: s, mapView: (context, embedUrl, fallback) {
                url = embedUrl;
                return fallback;
              }),
            ),
          ),
        ));
        expect(url, contains('hl=$lang'));
      }
    });

    testWidgets('the next-mass season pill lists every active season (no 2-line cut)', (tester) async {
      final source = File('lib/ui/widgets/cards.dart').readAsStringSync();
      expect(source, contains('maxLines: null, // every active season name must stay readable'));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox(width: 120, child: Pill('a b c d e f g h i j k l m n o p', maxLines: null))),
      ));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    });
  });

  group('?lang= sync in both directions (BUG-07)', () {
    test('resolveLangSync rules', () {
      Uri u(String s) => Uri.parse(s);
      // Toggle: the URL follows the language.
      expect(resolveLangSync(u('/clinics'), english: true, userToggled: true).redirect, '/clinics?lang=en');
      expect(resolveLangSync(u('/clinics?lang=en'), english: false, userToggled: true).redirect, '/clinics');
      // Explicit lang in the URL: the language follows it, URL kept.
      final deep = resolveLangSync(u('/clinics?lang=en'), english: false);
      expect((deep.english, deep.redirect), (true, null));
      final ar = resolveLangSync(u('/clinics?lang=ar'), english: true);
      expect((ar.english, ar.redirect), (false, '/clinics'));
      // No lang while English: in-app link keeps English, Back means Arabic.
      expect(resolveLangSync(u('/about'), english: true).redirect, '/about?lang=en');
      final back = resolveLangSync(u('/about'), english: true, fromPlatform: true);
      expect((back.english, back.redirect), (false, null));
      // Already in sync.
      final ok = resolveLangSync(u('/about?specialty=x'), english: false);
      expect((ok.english, ok.redirect), (null, null));
    });

    testWidgets('deep link, toggle, in-app links and Back keep URL and language in step', (tester) async {
      final (router, container) = await _pumpApp(tester, size: const Size(1200, 2400), locale: null);
      String lang() => container.read(localeProvider).languageCode;
      expect(lang(), 'ar');

      // Shared / in-app link with ?lang=en switches to English (URL kept).
      router.go('/clinics?lang=en');
      await tester.pumpAndSettle();
      expect((lang(), _location(router)), ('en', '/clinics?lang=en'));

      // In-app navigation keeps English.
      router.go('/about');
      await tester.pumpAndSettle();
      expect((lang(), _location(router)), ('en', '/about?lang=en'));

      // The ع toggle rewrites the URL.
      await tester.tap(find.byTooltip('العربية'));
      await tester.pumpAndSettle();
      expect((lang(), _location(router)), ('ar', '/about'));

      // Browser Back to the English URL brings English back (not stripped).
      await _platformPush(tester, '/about?lang=en');
      expect((lang(), _location(router)), ('en', '/about?lang=en'));

      // Browser Back to an Arabic (parameter-free) URL switches to Arabic.
      await _platformPush(tester, '/clinics');
      expect((lang(), _location(router)), ('ar', '/clinics'));
    });
  });

  group('admin (BUG-12, BUG-13, BUG-18, WCAG 2.5.7)', () {
    test('departed fathers are numbered from 1000', () {
      expect(reorderBase(collectionById('departedPriests')!), 1000);
      expect(reorderBase(collectionById('priests')!), 0);
    });

    test('isEchoOfEditor: own save vs. someone else\'s edit', () {
      final shown = {'nameEn': 'A', 'bishopEn': 'X', 'updatedAt': DateTime(2026)};
      final editor = {'nameEn': 'B', 'bishopEn': 'X'};
      expect(isEchoOfEditor(shown, {'nameEn': 'B', 'bishopEn': 'X', 'updatedAt': DateTime(2027)}, editor), isTrue);
      expect(isEchoOfEditor(shown, {'nameEn': 'A', 'bishopEn': 'Y', 'updatedAt': DateTime(2027)}, editor), isFalse);
      expect(isEchoOfEditor(null, {'nameEn': 'B'}, editor), isFalse);
    });

    testWidgets('saving church info keeps the form mounted (no scroll reset)', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final church = Map<String, dynamic>.from(_raw()['settings']['church'] as Map)
        ..['updatedAt'] = DateTime.utc(2026, 10, 1);
      final repo = _FakeBackend(docs: {'settings/church': church});
      await tester.pumpWidget(_adminApp(ChurchInfoScreen(repo: repo)));
      await tester.pumpAndSettle();
      final before = tester.state<DocEditorState>(find.byType(DocEditor));
      final scrollable = find.descendant(of: find.byType(DocEditor), matching: find.byType(Scrollable)).first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(DocEditor), matching: find.byType(TextField)).hitTestable().first, 'edited');
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(offset, greaterThan(0));
      expect(await before.save(), isTrue);
      await tester.pumpAndSettle();
      expect(tester.state<DocEditorState>(find.byType(DocEditor)), same(before));
      expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
      expect(before.dirty, isFalse);
    });

    testWidgets('saving features keeps the form mounted', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _FakeBackend(docs: {
        'settings/features': {...FeatureSettings.defaults.toMap(), 'updatedAt': DateTime.utc(2026, 10, 1)},
      });
      await tester.pumpWidget(_adminApp(FeaturesScreen(repo: repo)));
      await tester.pumpAndSettle();
      final before = tester.state<FeaturesEditorState>(find.byType(FeaturesEditor));
      await tester.tap(find.byKey(const ValueKey('theme-navy')));
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(tester.state<FeaturesEditorState>(find.byType(FeaturesEditor)), same(before));
    });

    testWidgets('saving page headers and the footer keeps the form mounted; a reset page is removed', (tester) async {
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final stored = FeatureSettings.defaults.copyWith(
        pageHeaders: {'ask': const PageCustom(titleEn: 'Ask us'), 'about': const PageCustom(titleAr: 'عنا')},
      );
      final repo = _FakeBackend(docs: {
        'settings/features': {...stored.toMap(), 'updatedAt': DateTime.utc(2026, 10, 1)},
      });
      await tester.pumpWidget(_adminApp(FeaturesScreen(repo: repo)));
      await tester.pumpAndSettle();
      final before = tester.state<FeaturesEditorState>(find.byType(FeaturesEditor));
      await tester.tap(find.byKey(const ValueKey('page-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pageReset-ask')));
      await tester.tap(find.byKey(const ValueKey('footer-showQuickLinks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(tester.state<FeaturesEditorState>(find.byType(FeaturesEditor)), same(before));
      expect(before.dirty, isFalse);
      final saved = repo.stored('settings/features')!;
      expect(saved['pageHeaders'], {'about': const PageCustom(titleAr: 'عنا').toMap()});
      expect((saved['footer'] as Map)['showQuickLinks'], isFalse);
    });

    testWidgets('home blocks can be reordered with single taps', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FeatureSettings? saved;
      await tester.pumpWidget(_adminApp(
        FeaturesEditor(initial: FeatureSettings.defaults, onSave: (f) async => saved = f),
      ));
      final order = FeatureSettings.defaults.homeOrder;
      final second = order[1];
      final up = tester.widget<IconButton>(find.byKey(ValueKey('home-${order.first}-up')));
      expect(up.onPressed, isNull);
      await tester.tap(find.byKey(ValueKey('home-$second-up')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('features-save')));
      await tester.pumpAndSettle();
      expect(saved!.homeOrder.first, second);
    });

    testWidgets('overview and church info re-subscribe when the backend changes', (tester) async {
      final a = _FakeBackend(), b = _FakeBackend();
      await tester.pumpWidget(_adminApp(OverviewScreen(repo: a, role: 'owner', onOpen: (_) {})));
      await tester.pump();
      expect(b.watched, isEmpty);
      await tester.pumpWidget(_adminApp(OverviewScreen(repo: b, role: 'owner', onOpen: (_) {})));
      await tester.pump();
      expect(b.watched, containsAll(['settings/features', 'contact_messages']));

      Map<String, Map<String, dynamic>> church(String by) => {
            'settings/church': {
              ...Map<String, dynamic>.from(_raw()['settings']['church'] as Map),
              'updatedAt': DateTime.utc(2026, 10, 1),
              'updatedBy': by,
            },
          };
      final c = _FakeBackend(docs: church('old-church@x.test')), d = _FakeBackend(docs: church('new-church@x.test'));
      await tester.pumpWidget(_adminApp(ChurchInfoScreen(repo: c)));
      await tester.pumpAndSettle();
      expect(find.textContaining('old-church@x.test'), findsOneWidget);
      await tester.pumpWidget(_adminApp(ChurchInfoScreen(repo: d)));
      await tester.pumpAndSettle();
      expect(d.watched, contains('settings/church'));
      // The new backend's document is rendered, not the old backend's last snapshot.
      expect(find.textContaining('new-church@x.test'), findsOneWidget);
      expect(find.textContaining('old-church@x.test'), findsNothing);
    });

    test('open on site keeps the dashboard language', () {
      final def = collectionById('clinics')!;
      expect(publicPathFor(def, english: false), '/clinics');
      expect(publicPathFor(def, english: true), '/clinics?lang=en');
    });

    testWidgets('collection list at 320 px: move buttons on their own row, title keeps its width', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _ListBackend([
        AdminDoc('a', {'name': 'Fr. Abraam Example', 'status': 'serving', 'order': 10, 'visible': true}),
        AdminDoc('b', {'name': 'Fr. Bishoy Example', 'status': 'serving', 'order': 20, 'visible': true}),
      ]);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('priests')!)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final title = find.text('Fr. Abraam Example');
      // Same room as before the move buttons existed (only hide + delete trail).
      expect(tester.getSize(title).width, greaterThanOrEqualTo(100));
      final up = find.byKey(const ValueKey('moveDown-a'));
      expect(tester.getTopLeft(up).dy, greaterThanOrEqualTo(tester.getBottomLeft(title).dy));
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(repo.reordered, ['b', 'a']);
      expect(repo.reorderedBase, 0);
    });

    testWidgets('collection list: move up/down buttons and "open on site"', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _ListBackend([
        AdminDoc('a', {'name': 'Fr. A', 'status': 'departed', 'order': 1010}),
        AdminDoc('b', {'name': 'Fr. B', 'status': 'departed', 'order': 1020}),
      ]);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('departedPriests')!)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-openOnSite')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('moveUp-a'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('moveUp-b')));
      await tester.pumpAndSettle();
      expect(repo.reordered, ['b', 'a']);
      expect(repo.reorderedBase, 1000);
    });

    testWidgets('deleting an item also deletes its inline cover and gallery media', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final media = _DeleteOnlyMedia();
      final repo = _ListBackend([
        AdminDoc('s', {
          'nameAr': 'St A',
          'order': 10,
          'image': {'source': 'inline', 'mediaId': 'cover1'},
          'gallery': [
            {'source': 'inline', 'mediaId': 'g1'},
            {'source': 'url', 'url': 'https://x.org/a.jpg'},
            {'source': 'inline', 'mediaId': 'g2'},
          ],
        }),
      ], mediaRepo: media);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['saints/s']);
      expect(media.deleted..sort(), ['cover1', 'g1', 'g2']);
    });

    testWidgets('search clear and admin Home buttons expose tooltips (en + ar)', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _ListBackend([AdminDoc('a', {'name': 'Fr. A', 'status': 'serving', 'order': 10})]);
      for (final (locale, clear) in [(const Locale('en'), 'Clear search'), (const Locale('ar'), 'مسح البحث')]) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(locale),
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: CollectionListScreen(repo: repo, def: collectionById('priests')!)),
        ));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('admin-search')), 'x');
        await tester.pumpAndSettle();
        expect(find.byTooltip(clear), findsOneWidget);
      }

      await tester.pumpWidget(ProviderScope(
        overrides: [adminRepositoryProvider.overrideWithValue(null)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const AdminPage(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to home'), findsOneWidget);
    });

    testWidgets('features and messages screens re-subscribe when the backend changes', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, Map<String, dynamic>> features(String by) => {
            'settings/features': {
              ...FeatureSettings.defaults.toMap(),
              'updatedAt': DateTime.utc(2026, 10, 1),
              'updatedBy': by,
            },
          };
      final a = _FakeBackend(docs: features('old-features@x.test')), b = _FakeBackend(docs: features('new-features@x.test'));
      await tester.pumpWidget(_adminApp(FeaturesScreen(repo: a)));
      await tester.pumpAndSettle();
      expect(find.textContaining('old-features@x.test'), findsOneWidget);
      expect(b.watched, isEmpty);
      await tester.pumpWidget(_adminApp(FeaturesScreen(repo: b)));
      await tester.pumpAndSettle();
      expect(b.watched, contains('settings/features'));
      // The new backend's document is what is rendered, not the old stream's.
      expect(find.textContaining('new-features@x.test'), findsOneWidget);
      expect(find.textContaining('old-features@x.test'), findsNothing);

      final c = _ListBackend([AdminDoc('m1', {'name': 'Old Sender', 'message': 'old', 'status': 'new'})]);
      final d = _ListBackend([AdminDoc('m2', {'name': 'New Sender', 'message': 'new', 'status': 'new'})]);
      await tester.pumpWidget(_adminApp(MessagesScreen(repo: c)));
      await tester.pumpAndSettle();
      expect(find.text('Old Sender'), findsOneWidget);
      await tester.pumpWidget(_adminApp(MessagesScreen(repo: d)));
      await tester.pumpAndSettle();
      expect(d.watched, contains('contact_messages'));
      expect(find.text('New Sender'), findsOneWidget);
      expect(find.text('Old Sender'), findsNothing);

      final e = _ListBackend([AdminDoc('e1', {'email': 'old-admin@x.test', 'role': 'editor'})]);
      final g = _ListBackend([AdminDoc('g1', {'email': 'new-admin@x.test', 'role': 'editor'})]);
      await tester.pumpWidget(_adminApp(AdminsScreen(repo: e, selfUid: 'u')));
      await tester.pumpAndSettle();
      expect(find.text('old-admin@x.test'), findsOneWidget);
      await tester.pumpWidget(_adminApp(AdminsScreen(repo: g, selfUid: 'u')));
      await tester.pumpAndSettle();
      expect(g.watched, contains('admins'));
      expect(find.text('new-admin@x.test'), findsOneWidget);
      expect(find.text('old-admin@x.test'), findsNothing);
    });
  });

  group('PR #12: collection rows, new-doc saves & stream switches', () {
    testWidgets('rows with a detail page carry a badge and open the item page; others stay as before', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _ListBackend([
        AdminDoc('on', {'nameAr': 'St On', 'order': 10, 'detailsEnabled': true}),
        AdminDoc('hidden', {'nameAr': 'St Hidden', 'order': 20, 'detailsEnabled': true, 'visible': false}),
        AdminDoc('off', {'nameAr': 'St Off', 'order': 30, 'detailsEnabled': false}),
        // Untouched item (no field): has a page since PR #14 (opt-out).
        AdminDoc('untouched', {'nameAr': 'St Untouched', 'order': 40}),
      ]);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      expect(find.text('Detail page'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('openItem-untouched')), findsOneWidget);
      expect(find.byKey(const ValueKey('openItem-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('openItem-hidden')), findsNothing, reason: 'hidden items have no public page');
      expect(find.byKey(const ValueKey('openItem-off')), findsNothing);
      expect(find.byTooltip('Open detail page on site'), findsNWidgets(2));
    });

    testWidgets('collections without detail pages never show the badge (CodeRabbit review)', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _ListBackend([
        AdminDoc('l1', {'nameAr': 'قداس', 'weekday': 7, 'start': '08:00', 'order': 10}),
      ]);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('liturgies')!)));
      await tester.pumpAndSettle();
      expect(find.text('Detail page'), findsNothing);
      expect(find.byKey(const ValueKey('openItem-l1')), findsNothing);
    });

    testWidgets('a detail-page row at 320 px x 200% text keeps its open-page button without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = _ListBackend([
        AdminDoc('on', {'nameAr': 'St On with a fairly long name', 'order': 10, 'detailsEnabled': true}),
      ]);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('openItem-on')), findsOneWidget);
    });

    testWidgets('a new item saved in several writes lands in one document', (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _SaveBackend();
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: repo, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-nameAr')), 'القديس');
      await tester.tap(find.byKey(const ValueKey('group-media')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('galleryUrlBtn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('imageUrlInput')), 'https://img.example.org/a.jpg');
      await tester.tap(find.byKey(const Key('imageUrlOk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(repo.saves.map((s) => s.$1), [null, 'new-1']);
      expect(repo.saves.last.$2.keys, ['gallery']);
    });

    testWidgets('collection, messages and admins lists drop the old backend while the new one loads', (tester) async {
      final a = _ListBackend([AdminDoc('a', {'nameAr': 'Old Saint', 'order': 10})]);
      final b = _PendingBackend();
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: a, def: collectionById('saints')!)));
      await tester.pumpAndSettle();
      expect(find.text('Old Saint'), findsOneWidget);
      await tester.pumpWidget(_adminApp(CollectionListScreen(repo: b, def: collectionById('saints')!)));
      await tester.pump();
      expect(find.text('Old Saint'), findsNothing);

      final c = _ListBackend([AdminDoc('m1', {'name': 'Old Sender', 'message': 'old', 'status': 'new'})]);
      await tester.pumpWidget(_adminApp(MessagesScreen(repo: c)));
      await tester.pumpAndSettle();
      expect(find.text('Old Sender'), findsOneWidget);
      await tester.pumpWidget(_adminApp(MessagesScreen(repo: _PendingBackend())));
      await tester.pump();
      expect(find.text('Old Sender'), findsNothing);

      final e = _ListBackend([AdminDoc('e1', {'email': 'old-admin@x.test', 'role': 'editor'})]);
      await tester.pumpWidget(_adminApp(AdminsScreen(repo: e, selfUid: 'u')));
      await tester.pumpAndSettle();
      expect(find.text('old-admin@x.test'), findsOneWidget);
      await tester.pumpWidget(_adminApp(AdminsScreen(repo: _PendingBackend(), selfUid: 'u')));
      await tester.pump();
      expect(find.text('old-admin@x.test'), findsNothing);
    });

    testWidgets('messages and admins at 320 px x 200% text reflow without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 3000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final msgs = _ListBackend([
        AdminDoc('m1', {
          'name': 'A sender with a fairly long name',
          'message': 'Hello there',
          'status': 'new',
          'phone': '01012345678',
          'createdAt': DateTime.utc(2026, 11, 1, 10),
        }),
      ]);
      await tester.pumpWidget(_adminApp(MessagesScreen(repo: msgs)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Delete'), findsOneWidget);
      final admins = _ListBackend([
        AdminDoc('e1', {'email': 'a.very.long.editor.address@example.org', 'role': 'editor'}),
      ]);
      await tester.pumpWidget(_adminApp(AdminsScreen(repo: admins, selfUid: 'u')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });
}

class _ListBackend extends _FakeBackend {
  final List<AdminDoc> docs;
  final MediaRepository? mediaRepo;
  final deletedIds = <String>[];
  _ListBackend(this.docs, {this.mediaRepo});
  @override
  MediaRepository? get media => mediaRepo;
  @override
  Future<void> delete(String collection, String id) async => deletedIds.add('$collection/$id');
  @override
  Stream<List<AdminDoc>> watch(String collection) {
    watched.add(collection);
    return Stream.value(docs);
  }
}

/// Records media deletions (the only call the delete handler makes).
class _DeleteOnlyMedia implements MediaRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String mediaId) async => deleted.add(mediaId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records collection saves; a create returns 'new-1'.
class _SaveBackend extends _ListBackend {
  final saves = <(String?, Map<String, dynamic>)>[];
  _SaveBackend() : super(const []);
  @override
  Future<String> save(String collection, String? id, Map<String, dynamic> data) async {
    saves.add((id, data));
    return id ?? 'new-1';
  }
}

/// A backend whose lists never arrive (still loading).
class _PendingBackend extends _FakeBackend {
  @override
  Stream<List<AdminDoc>> watch(String collection) {
    watched.add(collection);
    return StreamController<List<AdminDoc>>().stream;
  }
}
