import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';

class FirebaseStatus {
  final bool available;
  final bool appCheckActive;
  final String? error;
  const FirebaseStatus({required this.available, this.appCheckActive = false, this.error});
  static const unavailable = FirebaseStatus(available: false);
}

/// Pure configuration check for whether App Check can activate on this build
/// (mirrors `selectAppCheckPlan(...).activate` without pulling `firebase_app_check`).
bool isAppCheckConfigured({
  required bool isWeb,
  required bool debug,
  required String siteKey,
}) =>
    !isWeb || debug || AppConfig.isUsableSiteKey(siteKey);

/// Initialises Firebase if this platform has a real configuration. Never
/// throws: on any failure the app keeps running on bundled seed data.
Future<FirebaseStatus> bootstrapFirebase() async {
  final options = DefaultFirebaseOptions.currentPlatformOrNull;
  if (options == null) {
    return const FirebaseStatus(available: false, error: 'Firebase not configured for this platform');
  }
  try {
    await Firebase.initializeApp(options: options).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Firebase init failed, using seed data: $e');
    return FirebaseStatus(available: false, error: '$e');
  }

  // Offline cache: content stays readable without network after first load.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 40 * 1024 * 1024,
    );
  } catch (e) {
    debugPrint('Firestore settings: $e');
  }

  // App Check is activated lazily, on the first assistant use
  // (`ensureAppCheckActivated` in `app_check_providers.dart`, ADR-037): it
  // only protects Firebase AI Logic (Firestore is not enforced — see
  // docs/memory-bank/05-firebase.md), and activating it here loaded
  // reCAPTCHA Enterprise (~700 KiB of script, a Google iframe and a token
  // exchange) on every public page and held the first frame until it
  // answered. `appCheckActive` now says App Check is configured for this
  // build, which is what gates the assistant.
  final active = isAppCheckConfigured(
    isWeb: kIsWeb,
    debug: kDebugMode || AppConfig.forceAppCheckDebug,
    siteKey: AppConfig.recaptchaSiteKey,
  );
  return FirebaseStatus(available: true, appCheckActive: active);
}
