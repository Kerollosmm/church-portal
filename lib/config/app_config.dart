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
  static bool isUsableSiteKey(String key) => key.trim().isNotEmpty && !key.startsWith('PLACEHOLDER');

  /// Where uploaded images are stored: `firestore` (default — inline base64
  /// in `media/{id}`, works on the Spark plan) or `storage` (Cloud Storage for
  /// Firebase, needs the Blaze plan; see StorageMediaRepository).
  static const String mediaBackend = String.fromEnvironment('MEDIA_BACKEND', defaultValue: 'firestore');

  /// Hidden admin route.
  static const String adminPath = '/admin';
}
