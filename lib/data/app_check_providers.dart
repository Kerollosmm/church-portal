import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// The App Check providers and lazy activation for `/ask` (ADR-029 / ADR-037).
/// Pure selection logic ([selectAppCheckPlan]) is unit-tested in
/// `test/assistant_test.dart`; keeping activation here keeps `firebase_app_check`
/// out of `main.dart.js`.
class AppCheckPlan {
  /// Web provider; null on a web release build without a usable site key
  /// (then App Check is not activated at all and the assistant stays hidden).
  final WebProvider? web;
  final AndroidAppCheckProvider android;
  final AppleAppCheckProvider apple;

  /// False when App Check must not be activated (web release without key).
  final bool activate;

  /// Short description for logs and docs.
  final String label;

  const AppCheckPlan({
    required this.web,
    required this.android,
    required this.apple,
    required this.activate,
    required this.label,
  });
}

/// Chooses the providers:
///  * debug builds (or `--dart-define=APPCHECK_DEBUG=true`): the debug
///    providers on every platform (register the token printed in the browser
///    console / logcat, or pass APPCHECK_DEBUG_TOKEN, under App Check →
///    Manage debug tokens);
///  * web release: **reCAPTCHA Enterprise** with [siteKey] (the key is an
///    Enterprise key — a v3 provider would be rejected); no usable key → not
///    activated;
///  * Android release: Play Integrity (the app's SHA-256 must be registered
///    in App Check);
///  * Apple release: App Attest with DeviceCheck fallback.
AppCheckPlan selectAppCheckPlan({
  required bool isWeb,
  required bool debug,
  required String siteKey,
  String debugToken = '',
}) {
  final token = debugToken.trim().isEmpty ? null : debugToken.trim();
  final android = debug ? AndroidDebugProvider(debugToken: token) : const AndroidPlayIntegrityProvider();
  final apple = debug ? AppleDebugProvider(debugToken: token) : const AppleAppAttestWithDeviceCheckFallbackProvider();
  if (!isWeb) {
    return AppCheckPlan(
      web: null,
      android: android,
      apple: apple,
      activate: true,
      label: debug ? 'debug' : 'play-integrity / app-attest',
    );
  }
  if (debug) {
    return AppCheckPlan(
        web: WebDebugProvider(debugToken: token), android: android, apple: apple, activate: true, label: 'web-debug');
  }
  if (!AppConfig.isUsableSiteKey(siteKey)) {
    return AppCheckPlan(web: null, android: android, apple: apple, activate: false, label: 'web: no site key');
  }
  return AppCheckPlan(
    web: ReCaptchaEnterpriseProvider(siteKey.trim()),
    android: android,
    apple: apple,
    activate: true,
    label: 'recaptcha-enterprise',
  );
}

Future<bool>? _appCheckActivation;

/// Activates App Check once (later calls share the first result). Called by
/// the assistant before it mints a token or calls the model.
Future<bool> ensureAppCheckActivated() => _appCheckActivation ??= _activateAppCheck();

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
