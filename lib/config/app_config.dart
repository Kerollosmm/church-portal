/// App-wide configuration constants.
///
/// Values can be overridden at build time, e.g.
///   flutter build web --release \
///     --dart-define=RECAPTCHA_SITE_KEY=6Lc...your-key
class AppConfig {
  AppConfig._();

  /// Gemini model used by the "Ask the church" assistant (Firebase AI Logic,
  /// Gemini Developer API). 2.5 Flash-Lite is closed to new projects.
  static const String geminiModel = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

  /// reCAPTCHA v3 SITE key registered for the web app in
  /// Firebase console > App Check > Apps > Web.
  /// PLACEHOLDER until you register one. App Check is enforced for
  /// Firebase AI Logic, so the assistant only works on the web once this is
  /// set (or with a registered debug token in debug builds).
  static const String recaptchaV3SiteKey =
      String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: 'PLACEHOLDER_RECAPTCHA_V3_SITE_KEY');

  /// Optional App Check debug token (register it in Firebase console >
  /// App Check > Manage debug tokens). Used in debug builds, or in any build
  /// when APPCHECK_DEBUG=true. Empty = the SDK generates one and prints it to
  /// the browser console / logcat.
  static const String appCheckDebugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');
  static const bool forceAppCheckDebug = bool.fromEnvironment('APPCHECK_DEBUG');

  static bool get hasRecaptchaKey => !recaptchaV3SiteKey.startsWith('PLACEHOLDER') && recaptchaV3SiteKey.isNotEmpty;

  /// Where uploaded images are stored: `firestore` (default — inline base64
  /// in `media/{id}`, works on the Spark plan) or `storage` (Cloud Storage for
  /// Firebase, needs the Blaze plan; see StorageMediaRepository).
  static const String mediaBackend = String.fromEnvironment('MEDIA_BACKEND', defaultValue: 'firestore');

  /// Hidden admin route.
  static const String adminPath = '/admin';
}
