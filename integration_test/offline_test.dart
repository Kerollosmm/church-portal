// Emulator integration test for PR 6F-2 offline-first reads and queued contact writes.
//
// Local run instructions (requires Java 11+ and Firebase CLI):
//   1. Start the Firestore emulator and seed it:
//        npx firebase emulators:exec --only firestore --project demo-church-portal \
//          "FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/seed_firestore.js && \
//           flutter test integration_test/offline_test.dart -d linux"
//      (Or on Android emulator, pass --dart-define=FIRESTORE_EMULATOR_HOST=10.0.2.2)

import 'package:church_portal/core/theme.dart';
import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/firebase_bootstrap.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/firebase_options.dart';
import 'package:church_portal/state/providers.dart';
import 'package:church_portal/ui/pages/contact_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

const _emulatorHost = String.fromEnvironment('FIRESTORE_EMULATOR_HOST', defaultValue: '127.0.0.1');
const _emulatorPort = int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8080);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseFirestore db;
  late SeedData seed;
  var offline = false;

  setUpAll(() async {
    seed = await SeedData.load();
    if (Firebase.apps.isEmpty) {
      final options = DefaultFirebaseOptions.currentPlatformOrNull;
      if (options != null) {
        await Firebase.initializeApp(options: options);
      } else {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'demo-key',
            appId: '1:000000000000:web:demo',
            messagingSenderId: '000000000000',
            projectId: 'demo-church-portal',
          ),
        );
      }
    }
    db = FirebaseFirestore.instance;
    db.useFirestoreEmulator(_emulatorHost, _emulatorPort);
    db.settings = firestoreSettings(isWeb: false);
  });

  tearDown(() async {
    offline = false;
    await db.enableNetwork();
  });

  testWidgets('cached reads settle immediately offline and contact submission queues then syncs on enableNetwork',
      (tester) async {
    final repo = FirestoreRepository(db, seed, isOffline: () => offline);

    // 1. Warm Firestore persistence cache while network is enabled.
    await db.enableNetwork();
    final warmSettings = await repo.settings().first;
    final warmLiturgies = await repo.liturgies().first;
    final warmPages = await repo.pages().first;
    expect(warmSettings.nameAr, isNotEmpty);
    expect(warmLiturgies, isNotNull);
    expect(warmPages, isNotNull);

    // 2. Disable network -> cached reads resolve immediately without 8 s stalls.
    offline = true;
    await db.disableNetwork();

    final sw = Stopwatch()..start();
    final offlineSettings = await repo.settings().first;
    final offlineLiturgies = await repo.liturgies().first;
    final offlinePages = await repo.pages().first;
    sw.stop();

    expect(offlineSettings.nameAr, warmSettings.nameAr);
    expect(offlineLiturgies.length, warmLiturgies.length);
    expect(offlinePages.length, warmPages.length);
    expect(sw.elapsedMilliseconds, lessThan(2000));

    // 3. Submit contact form while offline -> queuedOffline, resend disabled while hasPendingWrites.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseStatusProvider.overrideWithValue(const FirebaseStatus(available: true)),
          repositoryProvider.overrideWithValue(repo),
          connectivityProvider.overrideWith((_) => Stream.value(false)),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildTheme(const Locale('ar')),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: SingleChildScrollView(child: ContactForm())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.descendant(of: find.byType(ContactForm), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'مينا مكسيموس');
    await tester.enterText(fields.at(1), '01012345678');
    await tester.enterText(fields.at(2), 'mina@example.com');
    await tester.enterText(fields.at(3), 'رسالة تجريبية للتحقق من الحفظ بدون إنترنت');
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(ContactForm), matching: find.byType(CheckboxListTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contactSendButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contactQueuedStatus')), findsOneWidget);
    expect(find.text('هيتبعت أول ما النت يرجع'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('contactSendButton'))).onPressed, isNull);

    // 4. Re-enable network -> queued batch syncs and clears pending state.
    offline = false;
    await db.enableNetwork();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('تم إرسال رسالتك. شكرًا لك، سنتواصل معك قريبًا.'), findsOneWidget);
  });
}
