import 'dart:convert';

import 'package:church_portal/core/install_env.dart';
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/cairo_time.dart';
import 'package:church_portal/domain/custom_content.dart';
import 'package:church_portal/domain/features.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/domain/share.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/mass_schedule_page.dart';
import 'package:church_portal/ui/pages/readings_page.dart';
import 'package:church_portal/ui/widgets/cards.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEnv implements InstallEnv {
  @override
  String get userAgent => 'Mozilla/5.0';
  @override
  String get platform => 'Linux';
  @override
  int get maxTouchPoints => 0;
  @override
  bool get isStandalone => false;
  @override
  bool get hasDeferredPrompt => false;
  @override
  bool get installedEventReceived => false;
  @override
  void clearInstalledSessionFlag() {}
  @override
  Future<bool> promptInstall() async => false;
  @override
  Map<String, dynamic>? readJson(String key) => null;
  @override
  void writeJson(String key, Map<String, dynamic> data) {}
  @override
  void remove(String key) {}
  @override
  void Function() listenInstallChanges(void Function() onChange) => () {};
}

const _sampleReadings = {
  'dateIso': '2026-11-08',
  'copticDateAr': '٢٩ بابة ١٧٤٣',
  'copticDateEn': '29 Baba 1743',
  'titleAr': 'أحد التكريس',
  'titleEn': 'Consecration Sunday',
  'sections': [
    {
      'key': 'gospel',
      'titleAr': 'الإنجيل',
      'titleEn': 'Gospel',
      'readings': [
        {
          'titleAr': 'فصل من بشارة معلمنا يوحنا',
          'titleEn': 'John 15',
          'refAr': 'يو ١٥ : ١ - ٥',
          'refEn': 'John 15:1-5',
          'introAr': '',
          'introEn': '',
          'textAr': 'أنا الكرمة الحقيقية وأبي الكرام.',
          'textEn': 'I am the true vine.',
          'conclusionAr': '',
          'conclusionEn': '',
        },
      ],
    },
  ],
  'source': 'api.katameros.app',
  'bibleAr': 'Van Dyck',
  'bibleEn': 'refs-only',
};

void main() {
  setUpAll(CairoTime.ensureInitialized);

  group('whatsappShareUri', () {
    test('produces clean https://wa.me/ URL with canonical path and zero tracking params', () {
      final uri = whatsappShareUri(title: 'القداس القادم', path: '/mass-schedule');
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/');
      final text = uri.queryParameters['text'];
      expect(text, isNotNull);
      expect(text, contains('القداس القادم'));
      expect(text, contains('https://maximos-domadios-church.web.app/mass-schedule'));
      expect(text, isNot(contains('src=')));
      expect(text, isNot(contains('utm_')));
    });

    test('normalizes missing leading slash and trailing origin slash', () {
      final uri = whatsappShareUri(
        title: '',
        path: 'readings/2026-11-08?tab=katameros',
        origin: 'https://maximos-domadios-church.web.app/',
      );
      expect(uri.queryParameters['text'], 'https://maximos-domadios-church.web.app/readings/2026-11-08?tab=katameros');
    });
  });

  group('WhatsApp share buttons', () {
    List<String> captureLaunched(WidgetTester tester) {
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

    testWidgets('NextMassCard shares /mass-schedule without overflow at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final launched = captureLaunched(tester);
      final now = CairoTime.at(2026, 11, 22, 6 * 60);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
            liturgiesProvider.overrideWithValue(
              const AsyncData([
                Liturgy(
                  id: 'm1',
                  type: 'mass',
                  nameAr: 'القداس الأول',
                  nameEn: 'First Liturgy',
                  weekday: 7,
                  start: '07:00',
                  end: '09:00',
                ),
              ]),
            ),
            seasonsProvider.overrideWithValue(const AsyncData([])),
            nowProvider.overrideWithValue(AsyncData(now)),
            settingsProvider.overrideWithValue(
              const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A')),
            ),
            featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: const Scaffold(body: SingleChildScrollView(child: NextMassCard())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('nextMassWhatsappShare'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(launched, hasLength(1));
      final launchedUri = Uri.parse(launched.single);
      expect(launchedUri.host, 'wa.me');
      expect(launchedUri.queryParameters['text'], contains('https://maximos-domadios-church.web.app/mass-schedule'));
      expect(launchedUri.queryParameters['text'], isNot(contains('src=')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('MassSchedulePage shares /mass-schedule without overflow at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final launched = captureLaunched(tester);
      final now = CairoTime.at(2026, 11, 22, 6 * 60);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(SeedRepository(SeedData(const {}))),
            liturgiesProvider.overrideWithValue(
              const AsyncData([
                Liturgy(
                  id: 'm1',
                  type: 'mass',
                  nameAr: 'القداس الأول',
                  nameEn: 'First Liturgy',
                  weekday: 7,
                  start: '07:00',
                  end: '09:00',
                ),
              ]),
            ),
            seasonsProvider.overrideWithValue(const AsyncData([])),
            nowProvider.overrideWithValue(AsyncData(now)),
            settingsProvider.overrideWithValue(
              const AsyncData(ChurchSettings(nameAr: 'كنيسة', nameEn: 'Church', addressAr: 'أ', addressEn: 'A')),
            ),
            featuresStreamProvider.overrideWithValue(const AsyncData(FeatureSettings.defaults)),
            customPagesProvider.overrideWithValue(const AsyncData(<CustomPage>[])),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: const Scaffold(body: MassSchedulePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('scheduleWhatsappShare'));
      expect(btn, findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pump();

      expect(launched, hasLength(1));
      final launchedUri = Uri.parse(launched.single);
      expect(launchedUri.host, 'wa.me');
      expect(launchedUri.queryParameters['text'], contains('https://maximos-domadios-church.web.app/mass-schedule'));
      expect(launchedUri.queryParameters['text'], isNot(contains('utm_')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ReadingsPage shares /readings/:date without overflow at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'church_portal_readings_2026-11-08': jsonEncode(_sampleReadings),
      });
      final launched = captureLaunched(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            installEnvProvider.overrideWithValue(_FakeEnv()),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(const Locale('ar')),
            home: const Scaffold(body: ReadingsPage(dateIso: '2026-11-08')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('readingsWhatsappShare'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();

      expect(launched, hasLength(1));
      final launchedUri = Uri.parse(launched.single);
      expect(launchedUri.host, 'wa.me');
      expect(
        launchedUri.queryParameters['text'],
        contains('https://maximos-domadios-church.web.app/readings/2026-11-08?tab=katameros'),
      );
      expect(launchedUri.queryParameters['text'], isNot(contains('src=')));
      expect(tester.takeException(), isNull);
    });
  });
}
