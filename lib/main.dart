import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/install_env.dart';
import 'core/locale_storage.dart';
import 'core/push_env.dart';
import 'data/admin_repository.dart';
import 'data/content_repository.dart';
import 'data/error_reporting.dart';
import 'data/firebase_bootstrap.dart';
import 'data/media_repository.dart';
import 'data/seed_data.dart';
import 'domain/cairo_time.dart';
import 'data/local_notifications.dart';
import 'data/push_messaging.dart';
import 'router.dart';
import 'state/notify_providers.dart';
import 'package:workmanager/workmanager.dart';
import 'state/providers.dart';

/// Sentry error tracking (ADR-034) wraps the whole start-up when a DSN is
/// configured (release builds, or `--dart-define=SENTRY_DSN=…`); otherwise
/// the app simply starts.
Future<void> main() => ErrorReporting.run(_start);

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // clean URLs (/mass-schedule) — Hosting rewrites to index.html
  // Fonts are bundled (assets/fonts, SIL OFL 1.1): no runtime font fetch.
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('IBM Plex Sans Arabic', 'IBMPlexSansArabic'),
      ('Lalezar', 'Lalezar'),
      ('Aref Ruqaa', 'ArefRuqaa'),
    ]) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('assets/fonts/$file-OFL.txt'));
    }
  });
  CairoTime.ensureInitialized();

  final results = await Future.wait([
    SeedData.load(),
    bootstrapFirebase(),
    initLanguageStore(),
    initInstallStore(),
    initPushStore(),
  ]);
  final seed = results[0] as SeedData;
  final status = results[1] as FirebaseStatus;

  final ContentRepository repo =
      status.available ? FirestoreRepository(FirebaseFirestore.instance, seed) : SeedRepository(seed);
  final AdminRepository? admin =
      status.available ? AdminRepository(FirebaseFirestore.instance, FirebaseAuth.instance) : null;
  final MediaRepository? media = admin?.media;

  if (!kIsWeb) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final isLinux = defaultTargetPlatform == TargetPlatform.linux;

    if (isAndroid || isApple || isLinux) {
      final notifier = LocalNotifier();
      await notifier.initialize(
        onSelectNotification: (payload) {
          if (payload != null && payload.isNotEmpty) {
            navigateToNotification(payload);
          }
        },
      );
      final launchPayload = await notifier.getLaunchPayload();
      if (launchPayload != null && launchPayload.isNotEmpty) {
        navigateToNotification(launchPayload);
      }
      // Re-check OS permission now that flutter_local_notifications is initialized.
      await const PlatformPushEnv().refreshPermission();
    }

    if (isAndroid || defaultTargetPlatform == TargetPlatform.iOS) {
      await PushMessaging.initialize(
        onSelectRoute: (route) {
          navigateToNotification(route);
        },
      );
    }

    if (isAndroid) {
      Workmanager().initialize(
        notificationReplenishCallbackDispatcher,
      );
      Workmanager().registerPeriodicTask(
        'church_portal_replenish_task',
        'notificationReplenishment',
        frequency: const Duration(hours: 24),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  }

  runApp(ProviderScope(
    overrides: [
      firebaseStatusProvider.overrideWithValue(status),
      repositoryProvider.overrideWithValue(repo),
      adminRepositoryProvider.overrideWithValue(admin),
      mediaRepositoryProvider.overrideWithValue(media),
    ],
    child: const ChurchPortalApp(),
  ));
}
