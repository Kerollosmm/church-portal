import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/today.dart';

/// Loads `/data/today.json` (ADR-040): the day's Katameros commemoration
/// published on Hosting by the scheduled workflow. Cost per visitor: no
/// Firestore read, at most ONE small same-origin GET (~3 KB) per day — the
/// file is kept on the device (shared_preferences: localStorage on web) and
/// re-fetched only when the stored copy has no entry for the needed date.
/// Any failure returns the stored copy or [SynaxariumData.empty]; the home
/// page then shows the computed feast list.
class SynaxariumSource {
  SynaxariumSource({http.Client? client, Future<SharedPreferences> Function()? prefs})
      : _client = client, // ignore: prefer_initializing_formals
        _prefs = prefs ?? SharedPreferences.getInstance;

  final http.Client? _client;
  final Future<SharedPreferences> Function() _prefs;

  static const storeKey = 'today.json';

  /// The live site (Android has no relative origin).
  static const liveUrl = 'https://maximos-domadios-church.web.app/data/today.json';

  static Uri get url => kIsWeb ? Uri.base.resolve('/data/today.json') : Uri.parse(liveUrl);

  /// The commemoration data covering [date] when possible.
  Future<SynaxariumData> load(DateTime date) async {
    SharedPreferences? prefs;
    SynaxariumData cached = SynaxariumData.empty;
    try {
      prefs = await _prefs();
      final raw = prefs.getString(storeKey);
      if (raw != null) cached = parse(raw);
    } catch (e) {
      debugPrint('today.json cache unavailable: $e');
    }
    if (cached.dayOf(date) != null) return cached;
    try {
      final client = _client ?? http.Client();
      try {
        var res = await client.get(url).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200 && url != Uri.parse(liveUrl)) {
          res = await client.get(Uri.parse(liveUrl)).timeout(const Duration(seconds: 10));
        }
        if (res.statusCode != 200) return cached;
        final body = utf8.decode(res.bodyBytes);
        final fresh = parse(body);
        if (fresh.days.isEmpty) return cached;
        try {
          await prefs?.setString(storeKey, body);
        } catch (_) {}
        return fresh;
      } finally {
        if (_client == null) client.close();
      }
    } catch (e) {
      debugPrint('today.json fetch failed: $e');
      return cached;
    }
  }

  /// Tolerant parse (malformed = empty).
  static SynaxariumData parse(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? SynaxariumData.fromMap(v) : SynaxariumData.empty;
    } catch (_) {
      return SynaxariumData.empty;
    }
  }
}
