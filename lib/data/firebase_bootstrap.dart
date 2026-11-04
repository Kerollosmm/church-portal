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

  // App Check is activated lazily, on the first assistant use
  // ([ensureAppCheckActivated], ADR-037): it only protects Firebase AI Logic
  // (Firestore is not enforced — see docs/memory-bank/05-firebase.md), and
  // activating it here loaded reCAPTCHA Enterprise (~700 KiB of script, a
  // Google iframe and a token exchange) on every public page and held the
  // first frame until it answered. `appCheckActive` now says App Check is
  // configured for this build, which is what gates the assistant.
  return FirebaseStatus(available: true, appCheckActive: _appCheckPlan().activate);
}

Future<bool>? _appCheckActivation;

/// Activates App Check once (later calls share the first result). Called by
/// the assistant before it mints a token or calls the model.
Future<bool> ensureAppCheckActivated() => _appCheckActivation ??= _activateAppCheck();

AppCheckPlan _appCheckPlan() => selectAppCheckPlan(
      isWeb: kIsWeb,
      debug: kDebugMode || AppConfig.forceAppCheckDebug,
      siteKey: AppConfig.recaptchaSiteKey,
      debugToken: AppConfig.appCheckDebugToken,
    );

/// App Check (enforced for Firebase AI Logic; ADR-029). Providers are chosen
/// by [selectAppCheckPlan]: reCAPTCHA Enterprise on web release builds
/// (skipped while RECAPTCHA_SITE_KEY is missing), Play Integrity on Android
/// release, App Attest on Apple release, debug providers in debug builds or
/// with APPCHECK_DEBUG=true.
Future<bool> _activateAppCheck() async {
  final plan = _appCheckPlan();
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
