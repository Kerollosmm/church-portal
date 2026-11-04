import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/content_repository.dart';
import 'data/error_reporting.dart';
import 'data/firebase_bootstrap.dart';
import 'data/seed_data.dart';
import 'domain/cairo_time.dart';
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

  final results = await Future.wait([SeedData.load(), bootstrapFirebase()]);
  final seed = results[0] as SeedData;
  final status = results[1] as FirebaseStatus;

  final ContentRepository repo =
      status.available ? FirestoreRepository(FirebaseFirestore.instance, seed) : SeedRepository(seed);

  runApp(ProviderScope(
    overrides: [
      firebaseStatusProvider.overrideWithValue(status),
      repositoryProvider.overrideWithValue(repo),
    ],
    child: const ChurchPortalApp(),
  ));
}
