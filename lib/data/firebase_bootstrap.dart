import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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

  final appCheck = await _activateAppCheck();
  return FirebaseStatus(available: true, appCheckActive: appCheck);
}

/// App Check (enforced for Firebase AI Logic).
///  * Web release: reCAPTCHA v3 with AppConfig.recaptchaV3SiteKey.
///  * Debug builds / APPCHECK_DEBUG=true: debug provider (register the token
///    printed in the console under App Check > Manage debug tokens).
///  * Android release: Play Integrity. iOS: App Attest w/ DeviceCheck fallback.
/// Skipped on web release while the site key is still a placeholder.
Future<bool> _activateAppCheck() async {
  final debug = kDebugMode || AppConfig.forceAppCheckDebug;
  final token = AppConfig.appCheckDebugToken.isEmpty ? null : AppConfig.appCheckDebugToken;
  WebProvider? web;
  if (kIsWeb) {
    if (debug) {
      web = WebDebugProvider(debugToken: token);
    } else if (AppConfig.hasRecaptchaKey) {
      web = ReCaptchaV3Provider(AppConfig.recaptchaV3SiteKey);
    } else {
      debugPrint('App Check not activated: set RECAPTCHA_SITE_KEY (see README).');
      return false;
    }
  }
  try {
    await FirebaseAppCheck.instance
        .activate(
          providerWeb: web,
          providerAndroid: debug ? AndroidDebugProvider(debugToken: token) : const AndroidPlayIntegrityProvider(),
          providerApple: debug ? AppleDebugProvider(debugToken: token) : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        )
        .timeout(const Duration(seconds: 8));
    return true;
  } catch (e) {
    debugPrint('App Check activation failed: $e');
    return false;
  }
}
