// Android / IO implementation of the install-env storage (ADR-058 / PR B).
//
// The APK keeps the visitor's notification prefs (`church_portal_push`) and «ذكّرني» reminders
// (`church_portal_reminders`) in SharedPreferences. Reads stay synchronous (same contract as the
// web `localStorage` implementation): [initInstallStore] obtains the SharedPreferences instance
// before the first frame, and its getters are synchronous (it keeps the values in memory and
// updates them at once on every write; the disk write follows in the background).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences? _prefs;

/// Memory-only fallback when the plugin is unavailable (unit tests, or a start-up failure).
final Map<String, String> _memory = {};

/// Loads the stored JSON values before the first frame. Safe to call more than once; failures
/// (no plugin in tests) leave the store in memory-only mode.
Future<void> initInstallStore() async {
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (_) {}
}

String getUserAgent() => '';
String getPlatform() => '';
int getMaxTouchPoints() => 0;
bool getIsStandalone() => false;
bool getHasDeferredPrompt() => false;
bool getInstalledEventReceived() => false;
void clearInstalledSessionFlag() {}
Future<bool> promptInstall() => Future.value(false);

Map<String, dynamic>? readJson(String key) {
  String? raw;
  try {
    raw = _prefs != null ? _prefs!.getString(key) : _memory[key];
  } catch (_) {
    return null;
  }
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Throws when the value cannot be encoded; the disk write itself is asynchronous and a refusal
/// there keeps the in-memory value for this session.
void writeJson(String key, Map<String, dynamic> data) {
  final raw = jsonEncode(data);
  final prefs = _prefs;
  if (prefs == null) {
    _memory[key] = raw;
    return;
  }
  prefs.setString(key, raw).catchError((_) => false);
}

void removeStorageKey(String key) {
  _memory.remove(key);
  _prefs?.remove(key).catchError((_) => false);
}

void Function() listenInstallChanges(void Function() onChange) => () {};
