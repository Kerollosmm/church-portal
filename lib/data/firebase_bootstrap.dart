import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';
import 'app_check_providers.dart';

class FirebaseStatus {
  final bool available;
  final bool appCheckActive;
  final String? error;
  const FirebaseStatus({required this.available, this.appCheckActive = false, this.error});
  static const unavailable = FirebaseStatus(available: false);
}

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

  final plan = selectAppCheckPlan(
    isWeb: kIsWeb,
    debug: kDebugMode || AppConfig.forceAppCheckDebug,
    siteKey: AppConfig.recaptchaSiteKey,
    debugToken: AppConfig.appCheckDebugToken,
  );
  return FirebaseStatus(available: true, appCheckActive: plan.activate);
}

Future<bool>? _appCheckFuture;

/// Idempotent lazy activator for App Check (enforced for Firebase AI Logic; ADR-029).
/// Called on `/ask` warm-up/generate so public visitors on `/` never incur reCAPTCHA
/// Enterprise overhead, storage access prompts, or 403 errors.
Future<bool> ensureAppCheckActivated() => _appCheckFuture ??= _activateAppCheck();

@visibleForTesting
void resetAppCheckActivationForTest() {
  _appCheckFuture = null;
}

/// App Check (enforced for Firebase AI Logic; ADR-029). Providers are chosen
/// by [selectAppCheckPlan]: reCAPTCHA Enterprise on web release builds
/// (skipped while RECAPTCHA_SITE_KEY is missing), Play Integrity on Android
/// release, App Attest on Apple release, debug providers in debug builds or
/// with APPCHECK_DEBUG=true.
Future<bool> _activateAppCheck() async {
  final plan = selectAppCheckPlan(
    isWeb: kIsWeb,
    debug: kDebugMode || AppConfig.forceAppCheckDebug,
    siteKey: AppConfig.recaptchaSiteKey,
    debugToken: AppConfig.appCheckDebugToken,
  );
  if (!plan.activate) {
    debugPrint('App Check not activated (${plan.label}): set RECAPTCHA_SITE_KEY (see README).');
    return false;
  }
  try {
    await FirebaseAppCheck.instance
        .activate(providerWeb: plan.web, providerAndroid: plan.android, providerApple: plan.apple)
        .timeout(const Duration(seconds: 8));
    return true;
  } on TimeoutException catch (e) {
    debugPrint('App Check activation timed out: $e');
    return false;
  } catch (e) {
    debugPrint('App Check activation failed: $e');
    return false;
  }
}
