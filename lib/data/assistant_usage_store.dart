import 'package:shared_preferences/shared_preferences.dart';

import '../domain/assistant_quota.dart';

/// [AssistantUsageStore] on shared_preferences: localStorage on web,
/// SharedPreferences on Android (ADR-031). Clearing site / app data resets
/// both the device id and the count — a fair-use limit, not security.
class PrefsUsageStore implements AssistantUsageStore {
  PrefsUsageStore(this._prefs) : deviceId = _ensureId(_prefs);

  static const idKey = 'assistant.deviceId', dayKey = 'assistant.day', countKey = 'assistant.count';

  final SharedPreferences _prefs;
  @override
  final String deviceId;

  static String _ensureId(SharedPreferences p) {
    final id = p.getString(idKey);
    if (id != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return id;
    final fresh = newDeviceId();
    p.setString(idKey, fresh);
    return fresh;
  }

  @override
  DailyUsage read() => DailyUsage(_prefs.getString(dayKey) ?? '', _prefs.getInt(countKey) ?? 0);

  @override
  void write(DailyUsage usage) {
    _prefs.setString(dayKey, usage.day);
    _prefs.setInt(countKey, usage.count);
  }

  static Future<AssistantUsageStore> load() async {
    try {
      return PrefsUsageStore(await SharedPreferences.getInstance());
    } catch (_) {
      // Storage blocked (private mode etc.): count for this visit only.
      return MemoryUsageStore();
    }
  }
}
