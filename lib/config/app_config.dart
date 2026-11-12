import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import '../domain/error_privacy.dart';

/// App-wide configuration constants.
///
/// Values can be overridden at build time, e.g.
///   flutter build web --release \
///     --dart-define=RECAPTCHA_SITE_KEY=6Lc...your-key
class AppConfig {
  AppConfig._();

  /// Default model of the "Ask the church" assistant (Firebase AI Logic,
  /// Gemini Developer API, free tier on the Spark plan). ADR-029: the
  /// cheapest stable Flash-Lite the Firebase AI Logic model list supports
  /// (Gemma is not offered by the cloud API; Gemini 2.x is shut down or
  /// closed to new projects). Admins can choose another one in /admin →
  /// Assistant (`settings/assistant.model`); this build-time default is the
  /// safe fallback (also used when the chosen model is rejected).
  static const String geminiModel = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.1-flash-lite');

  /// reCAPTCHA **Enterprise** SITE key of the web app (Firebase console →
  /// App Check → Apps → Web, provider "reCAPTCHA Enterprise"). CI passes the
  /// repository variable RECAPTCHA_SITE_KEY for live builds. PLACEHOLDER
  /// until set: App Check is enforced for Firebase AI Logic, so the web
  /// assistant only works with this key (or a registered debug token in
  /// debug builds).
  static const String recaptchaSiteKey =
      String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: 'PLACEHOLDER_RECAPTCHA_SITE_KEY');

  /// Optional App Check debug token (register it in Firebase console >
  /// App Check > Manage debug tokens). Used in debug builds, or in any build
  /// when APPCHECK_DEBUG=true. Empty = the SDK generates one and prints it to
  /// the browser console / logcat.
  static const String appCheckDebugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');
  static const bool forceAppCheckDebug = bool.fromEnvironment('APPCHECK_DEBUG');

  static bool get hasRecaptchaKey => isUsableSiteKey(recaptchaSiteKey);

  /// A real key (not empty, not the PLACEHOLDER default).
  static bool isUsableSiteKey(String key) {
    final k = key.trim();
    return k.isNotEmpty && !k.startsWith('PLACEHOLDER');
  }

  /// Origin the Android app reads static Hosting files from (readings,
  /// today.json). `--dart-define=SITE_ORIGIN=…` points a test APK at the dev
  /// channel; the web build always reads its own origin.
  static const String siteOriginDefine =
      String.fromEnvironment('SITE_ORIGIN', defaultValue: 'https://maximos-domadios-church.web.app');

  /// Base for static data files: the page's own origin on web (dev channel,
  /// PR previews, production), [siteOriginDefine] on Android.
  static String get dataOrigin => kIsWeb ? Uri.base.origin : siteOriginDefine;

  /// Where uploaded images are stored: `firestore` (default — inline base64
  /// in `media/{id}`, works on the Spark plan) or `storage` (Cloud Storage for
  /// Firebase, needs the Blaze plan; see StorageMediaRepository).
  static const String mediaBackend = String.fromEnvironment('MEDIA_BACKEND', defaultValue: 'firestore');

  /// Sentry error tracking (ADR-034). `--dart-define=SENTRY_DSN=…` overrides
  /// the DSN (an empty value switches reporting off); without it release
  /// builds use [sentryDefaultDsn] and debug / profile builds report nothing.
  /// A DSN is public by design (it only lets clients send events).
  static const String sentryDefaultDsn =
      'https://36d587001696d31ad588ebd080dec610@o4512369647812608.ingest.de.sentry.io/4512369961205840';
  static const bool hasSentryDsnDefine = bool.hasEnvironment('SENTRY_DSN');
  static const String sentryDsnDefine = String.fromEnvironment('SENTRY_DSN');
  static String? get sentryDsn => resolveSentryDsn(
      hasDefine: hasSentryDsnDefine, define: sentryDsnDefine, release: kReleaseMode, fallback: sentryDefaultDsn);

  /// `production` (main deploy), `preview` (PR previews), `debug` locally.
  static const String sentryEnvironmentDefine = String.fromEnvironment('SENTRY_ENVIRONMENT');
  static String get sentryEnvironment => resolveSentryEnvironment(define: sentryEnvironmentDefine, release: kReleaseMode);

  /// `church-portal@<APP_VERSION>+<GIT_SHA short>` (CI passes both); null →
  /// the SDK's own `name@version+build`.
  static const String appVersion = String.fromEnvironment('APP_VERSION');
  static const String gitSha = String.fromEnvironment('GIT_SHA');
  static String? get sentryRelease => buildSentryRelease(appVersion, gitSha);

  /// Public Web Push key (Firebase Console → Project settings → Cloud Messaging
  /// → Web Push certificates → Key pair). Repository variable
  /// `WEB_PUSH_VAPID_KEY`, passed as `--dart-define=WEB_PUSH_VAPID_KEY`. Used
  /// only when `settings/features.pushVapidKey` is empty. The private key must
  /// never be put here: it would be compiled into the public web bundle.
  static const String webPushVapidKey = String.fromEnvironment('WEB_PUSH_VAPID_KEY');

  /// Hidden admin route.
  static const String adminPath = '/admin';
}
