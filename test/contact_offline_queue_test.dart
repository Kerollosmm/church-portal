import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/firebase_bootstrap.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/router.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _QueuedContactRepo extends SeedRepository {
  Completer<void>? nextCommit;
  bool queueNext = true;
  int submitCount = 0;

  _QueuedContactRepo(super.seed);

  @override
  Future<ContactSubmitResult> submitContact(Map<String, dynamic> payload, {required String lang}) async {
    submitCount++;
    if (!queueNext) return ContactSubmitResult.sent;
    final completer = nextCommit ?? Completer<void>();
    nextCommit = completer;
    return ContactSubmitResult.queuedOffline(pendingCommit: completer.future);
  }
}

SeedData _loadSeed() {
  final raw = jsonDecode(File('assets/seed/seed.json').readAsStringSync()) as Map<String, dynamic>;
  return SeedData(raw);
}

Future<void> _fillValidContactForm(WidgetTester tester, {required String message}) async {
  final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), 'مينا عاطف');
  await tester.enterText(fields.at(1), '01012345678');
  await tester.enterText(fields.at(2), 'mina@example.com');
  await tester.enterText(fields.at(3), message);
  await tester.pumpAndSettle();

  final consent = find.descendant(of: find.byType(ContactForm), matching: find.byType(CheckboxListTile));
  await tester.tap(consent);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetContactRateLimiterForTest);

  testWidgets('offline queued submission shows notice, disables resend, and clears on ack', (tester) async {
    final seed = _loadSeed();
    final repo = _QueuedContactRepo(seed);
    final commit = Completer<void>();
    repo.nextCommit = commit;

    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
          repositoryProvider.overrideWithValue(repo),
          featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
          settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
          dailyVersesProvider.overrideWith((_) async => const []),
          connectivityProvider.overrideWith((_) => Stream.value(false)),
        ],
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          final router = ref.watch(routerProvider);
          return MaterialApp.router(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: router,
          );
        }),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/contact');
    await tester.pumpAndSettle();

    await _fillValidContactForm(tester, message: 'رسالة اختبار أثناء انقطاع الاتصال');
    await tester.tap(find.byKey(const Key('contactSendButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contactQueuedStatus')), findsOneWidget);
    expect(find.text('هيتبعت أول ما النت يرجع'), findsOneWidget);

    // Resend must stay disabled while hasPendingWrites is true.
    final btnDuringPending = tester.widget<FilledButton>(find.byKey(const Key('contactSendButton')));
    expect(btnDuringPending.onPressed, isNull);
    expect(container.read(contactQueueProvider).hasPendingWrites, isTrue);

    // Server ack completes pending write -> fields clear and success notice shows.
    commit.complete();
    await tester.pumpAndSettle();

    expect(container.read(contactQueueProvider).hasPendingWrites, isFalse);
    expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
    expect(find.text('رسالة اختبار أثناء انقطاع الاتصال'), findsNothing);
  });

  testWidgets('queued write rejected on sync surfaces persistent failure notice and preserves draft', (tester) async {
    final seed = _loadSeed();
    final repo = _QueuedContactRepo(seed);
    final commit = Completer<void>();
    repo.nextCommit = commit;

    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
          repositoryProvider.overrideWithValue(repo),
          featuresStreamProvider.overrideWith((_) => Stream.value(seed.features)),
          settingsProvider.overrideWith((_) => Stream.value(seed.settings)),
          dailyVersesProvider.overrideWith((_) async => const []),
          connectivityProvider.overrideWith((_) => Stream.value(false)),
        ],
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          final router = ref.watch(routerProvider);
          return MaterialApp.router(
            locale: const Locale('ar'),
            theme: buildTheme(const Locale('ar')),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: router,
          );
        }),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/contact');
    await tester.pumpAndSettle();

    const msgText = 'رسالة هامة لا يجب أن تضيع عند رفض الخادم';
    await _fillValidContactForm(tester, message: msgText);
    await tester.tap(find.byKey(const Key('contactSendButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contactQueuedStatus')), findsOneWidget);

    // Simulate navigating away before server rejects on reconnect.
    container.read(routerProvider).go('/');
    await tester.pumpAndSettle();

    // Server rejects the queued batch (e.g. meta/contact_rate throttle / rules).
    commit.completeError(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Caller throttled by meta/contact_rate',
      ),
    );
    await tester.pumpAndSettle();

    // Return to /contact: failure notice is shown and draft text is preserved!
    container.read(routerProvider).go('/contact');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contactQueuedError')), findsOneWidget);
    expect(find.text('تعذّر إرسال الرسالة المحفوظة عند عودة الاتصال. يمكنك مراجعتها وإعادة الإرسال.'), findsOneWidget);
    expect(find.text('مينا عاطف'), findsOneWidget);
    expect(find.text('01012345678'), findsOneWidget);
    expect(find.text('mina@example.com'), findsOneWidget);
    expect(find.text(msgText), findsOneWidget);

    // Resend button is re-enabled and works when user resends.
    final btnAfterReject = tester.widget<FilledButton>(find.byKey(const Key('contactSendButton')));
    expect(btnAfterReject.onPressed, isNotNull);

    repo.queueNext = false;
    await tester.tap(find.byKey(const Key('contactSendButton')));
    await tester.pumpAndSettle();

    expect(repo.submitCount, 2);
    expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
  });
}
