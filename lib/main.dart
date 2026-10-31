import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/admin_repository.dart';
import 'data/content_repository.dart';
import 'data/firebase_bootstrap.dart';
import 'data/seed_data.dart';
import 'domain/cairo_time.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // clean URLs (/mass-schedule) — Hosting rewrites to index.html
  GoogleFonts.config.allowRuntimeFetching = true;
  CairoTime.ensureInitialized();

  final results = await Future.wait([SeedData.load(), bootstrapFirebase()]);
  final seed = results[0] as SeedData;
  final status = results[1] as FirebaseStatus;

  final ContentRepository repo =
      status.available ? FirestoreRepository(FirebaseFirestore.instance, seed) : SeedRepository(seed);
  final AdminRepository? admin =
      status.available ? AdminRepository(FirebaseFirestore.instance, FirebaseAuth.instance) : null;

  runApp(ProviderScope(
    overrides: [
      firebaseStatusProvider.overrideWithValue(status),
      repositoryProvider.overrideWithValue(repo),
      adminRepositoryProvider.overrideWithValue(admin),
    ],
    child: const ChurchPortalApp(),
  ));
}
