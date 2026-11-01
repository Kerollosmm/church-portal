import 'package:web/web.dart' as web;

// localStorage throws (SecurityError) when storage is blocked, e.g. some
// privacy modes or third-party contexts: treat that as "nothing saved".
String? readLanguage(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeLanguage(String key, String code) {
  try {
    web.window.localStorage.setItem(key, code);
  } catch (_) {}
}
