import 'dart:async';

import 'package:church_portal/core/connectivity_env.dart';
import 'package:church_portal/core/connectivity_env_io.dart' as conn_io;
import 'package:church_portal/core/theme.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/widgets/offline_banner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeConnectivity implements Connectivity {
  List<ConnectivityResult> nextCheck = const [ConnectivityResult.wifi];
  int checkCalls = 0;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCalls++;
    return nextCheck;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _RacingConnectivityEnv extends ConnectivityEnv {
  final bool initialOnline;
  final Completer<bool> checkCompleter = Completer<bool>();
  final _controller = StreamController<bool>.broadcast();

  _RacingConnectivityEnv({this.initialOnline = true});

  @override
  bool get isOnline => initialOnline;

  @override
  Future<bool> checkOnline() => checkCompleter.future;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  void emit(bool next) => _controller.add(next);

  Future<void> dispose() => _controller.close();
}

void main() {
  group('isConnectivityOnline', () {
    test('returns false only when no network interface is present', () {
      expect(conn_io.isConnectivityOnline(const []), isFalse);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.none]), isFalse);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.none, ConnectivityResult.none]), isFalse);
    });

    test('returns true when any real network interface is present', () {
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.wifi]), isTrue);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.mobile]), isTrue);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.ethernet]), isTrue);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.vpn]), isTrue);
      expect(conn_io.isConnectivityOnline(const [ConnectivityResult.none, ConnectivityResult.wifi]), isTrue);
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

    testWidgets('defaults to hidden while connectivityProvider is loading', (tester) async {
      final controller = StreamController<bool>();
      addTearDown(controller.close);
      await tester.pumpWidget(wrap(stream: controller.stream));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('offlineBanner')), findsNothing);
    });
  });

  group('connectivity_env_io resume & connectivityProvider ordering', () {
    testWidgets('initConnectivityEnv re-checks connectivity on app resume and emits changes', (tester) async {
      final fake = _FakeConnectivity();
      addTearDown(() async {
        await conn_io.resetConnectivityEnvForTest();
        await fake.dispose();
      });

      final emitted = <bool>[];
      final sub = conn_io.getOnOnlineChanged().listen(emitted.add);
      addTearDown(sub.cancel);

      await conn_io.initConnectivityEnv(connectivity: fake);
      expect(conn_io.isOnline, isTrue);
      expect(fake.checkCalls, 1);

      fake.nextCheck = const [ConnectivityResult.none];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(fake.checkCalls, 2);
      expect(conn_io.isOnline, isFalse);
      expect(emitted, [false]);
      expect(await conn_io.checkOnline(), isFalse);
    });

    test('connectivityProvider subscribes before initial check and does not let stale check overwrite newer event',
        () async {
      final env = _RacingConnectivityEnv(initialOnline: true);
      addTearDown(env.dispose);

      final container = ProviderContainer(
        overrides: [connectivityEnvProvider.overrideWithValue(env)],
      );
      addTearDown(container.dispose);

      final seen = <bool>[];
      container.listen<AsyncValue<bool>>(connectivityProvider, (_, next) {
        if (next.hasValue) seen.add(next.value!);
      }, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true]);

      // Emit offline while initial checkOnline() is still pending.
      env.emit(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(connectivityProvider).value, isFalse);
      expect(seen, [true, false]);

      // Stale initial check resolves true -> must NOT overwrite the newer false event.
      env.checkCompleter.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(connectivityProvider).value, isFalse);
      expect(seen, [true, false]);
    });
  });
}
