// Per-device daily question limit for the assistant (ADR-031). Pure Dart.
//
// The counter lives on the device (shared_preferences: localStorage on web,
// SharedPreferences on Android) under a random device id, and resets at
// Africa/Cairo midnight. It is a fair-use limit, not a security boundary:
// clearing site / app data starts a new device id and a fresh count, and
// Firebase AI Logic is called straight from the client, so nothing on the
// server can gate the call without Cloud Functions.

import 'dart:math';

import 'cairo_time.dart';

/// The Cairo calendar day of [instant] as `yyyymmdd`.
String cairoDayKey(DateTime instant) {
  final c = CairoTime.fromInstant(instant);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${c.year}${two(c.month)}${two(c.day)}';
}

class DailyUsage {
  /// `yyyymmdd` (Cairo) the [count] belongs to; '' = never used.
  final String day;
  final int count;
  const DailyUsage(this.day, this.count);
  static const empty = DailyUsage('', 0);

  /// Questions already asked on [today] (0 when the stored day is older).
  int countOn(String today) => day == today ? count : 0;

  bool reached(String today, int limit) => countOn(today) >= limit;

  DailyUsage recorded(String today) => DailyUsage(today, countOn(today) + 1);

  @override
  bool operator ==(Object other) => other is DailyUsage && other.day == day && other.count == count;
  @override
  int get hashCode => Object.hash(day, count);
}

/// Where the device's usage is kept. Synchronous once loaded.
abstract class AssistantUsageStore {
  String get deviceId;
  DailyUsage read();
  void write(DailyUsage usage);
}

/// In-memory store (tests, and the fallback when storage is unavailable).
class MemoryUsageStore implements AssistantUsageStore {
  MemoryUsageStore({String? deviceId, DailyUsage usage = DailyUsage.empty})
      : deviceId = deviceId ?? newDeviceId(),
        _usage = usage; // ignore: prefer_initializing_formals
  @override
  final String deviceId;
  DailyUsage _usage;
  @override
  DailyUsage read() => _usage;
  @override
  void write(DailyUsage usage) => _usage = usage;
}

/// A random 128-bit id as 32 lowercase hex characters.
String newDeviceId([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Parses the admin's source domains ("st-takla.org, example.org" or one per
/// line): lower-case host names only, scheme / `www.` / paths stripped,
/// invalid entries dropped; empty → [fallback].
List<String> parseSourceDomains(String raw, {List<String> fallback = const ['st-takla.org']}) {
  final out = <String>[];
  for (var p in raw.toLowerCase().split(RegExp(r'[\s,;]+'))) {
    p = p.replaceFirst(RegExp(r'^[a-z]+://'), '').split('/').first.replaceFirst(RegExp(r'^www\.'), '');
    if (RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$').hasMatch(p) &&
        p.length <= 100 &&
        !out.contains(p)) {
      out.add(p);
    }
  }
  return out.isEmpty ? fallback : out;
}

/// A Google search restricted to [domains] for [question].
String sourceSearchUrl(List<String> domains, String question) {
  final sites = domains.map((d) => 'site:$d').join(' OR ');
  final q = question.trim().replaceAll(RegExp(r'\s+'), ' ');
  return Uri.https('www.google.com', '/search', {'q': '$sites $q'.trim()}).toString();
}
