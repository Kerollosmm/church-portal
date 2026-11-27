import 'dart:async';

import 'package:church_portal/core/connectivity_env_io.dart' show isConnectivityOnline;
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/offline_banner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('isConnectivityOnline', () {
    test('returns false only when no network interface is present', () {
      expect(isConnectivityOnline(const []), isFalse);
      expect(isConnectivityOnline(const [ConnectivityResult.none]), isFalse);
      expect(isConnectivityOnline(const [ConnectivityResult.none, ConnectivityResult.none]), isFalse);
    });

    test('returns true when any real network interface is present', () {
      expect(isConnectivityOnline(const [ConnectivityResult.wifi]), isTrue);
      expect(isConnectivityOnline(const [ConnectivityResult.mobile]), isTrue);
      expect(isConnectivityOnline(const [ConnectivityResult.ethernet]), isTrue);
      expect(isConnectivityOnline(const [ConnectivityResult.vpn]), isTrue);
      expect(isConnectivityOnline(const [ConnectivityResult.none, ConnectivityResult.wifi]), isTrue);
    });
  });

  group('OfflineBanner widget', () {
    Widget wrap({
      required Stream<bool> stream,
      Locale locale = const Locale('ar'),
      String? customMessage,
      double width = 400,
      double textScale = 1.0,
    }) {
      return ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((_) => stream),
        ],
        child: MaterialApp(
          locale: locale,
          theme: buildTheme(locale),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  OfflineBanner(message: customMessage),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('hides when connectivityProvider emits true and shows when false', (tester) async {
      final controller = StreamController<bool>();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(stream: controller.stream));
      controller.add(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offlineBanner')), findsNothing);

      controller.add(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offlineBanner')), findsOneWidget);
      expect(find.text('لا يوجد اتصال بالإنترنت — يتم عرض البيانات المحفوظة'), findsOneWidget);

      controller.add(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offlineBanner')), findsNothing);
    });

    testWidgets('renders English copy in LTR and custom admin message cleanly at 320/400/1400 px', (tester) async {
      for (final width in [320.0, 400.0, 1400.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpWidget(wrap(
          stream: Stream.value(false),
          locale: const Locale('en'),
          width: width,
          textScale: width == 320.0 ? 2.0 : 1.0,
        ));
        await tester.pump();
        expect(find.byKey(const Key('offlineBanner')), findsOneWidget);
        expect(find.text('You are offline — showing saved data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.binding.setSurfaceSize(const Size(320, 800));
      await tester.pumpWidget(wrap(
        stream: Stream.value(false),
        locale: const Locale('ar'),
        customMessage: 'لا يوجد اتصال بالإنترنت — التعديل والحفظ متوقفان مؤقتًا',
        width: 320,
      ));
      await tester.pump();
      expect(find.text('لا يوجد اتصال بالإنترنت — التعديل والحفظ متوقفان مؤقتًا'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('renders SizedBox.shrink without throwing when ProviderScope is absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Locale('en')),
          home: const Scaffold(body: OfflineBanner()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('offlineBanner')), findsNothing);
    });
  });
}
