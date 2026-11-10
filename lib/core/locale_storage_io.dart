import 'package:shared_preferences/shared_preferences.dart';

String? _cachedLanguage;

/// Preloads the saved language from SharedPreferences into an in-memory cache
/// so that synchronous reads in [readLanguage] can return immediately.
Future<void> initLanguageStore() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _cachedLanguage = prefs.getString('church_portal_lang');
  } catch (_) {}
}

String? readLanguage(String key) => _cachedLanguage;

void writeLanguage(String key, String code) {
  _cachedLanguage = code;
  SharedPreferences.getInstance().then((p) => p.setString(key, code)).catchError((_) => false);
}
