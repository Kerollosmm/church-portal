import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../domain/readings.dart';

/// Manages fetching, caching, and pruning of Katameros daily readings.
///
/// Stores daily readings JSON under `church_portal_readings_<date>`.
/// Operates offline from the cache, fetches missing days from Firebase Hosting,
/// and prunes days older than yesterday.
class ReadingsStore {
  static const String prefix = 'church_portal_readings_';
  final http.Client _client;
  final String _baseUrl;
  final Map<String, DayReadings> _memoryCache = {};

  ReadingsStore({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = _trimSlash(baseUrl ?? AppConfig.dataOrigin);

  static String _trimSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Loads readings for [dateIso] (YYYY-MM-DD).
  ///
  /// First checks memory and local storage. If missing, attempts HTTP GET
  /// from `/data/readings/<date>.json`.
  Future<DayReadings?> getReadings(
    String dateIso, {
    bool forceFetch = false,
  }) async {
    if (!forceFetch && _memoryCache.containsKey(dateIso)) {
      return _memoryCache[dateIso];
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('$prefix$dateIso');

    if (!forceFetch && cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        final readings = DayReadings.fromJson(data);
        _memoryCache[dateIso] = readings;
        return readings;
      } catch (_) {
        // Corrupt cache -> continue to fetch
      }
    }

    // Fetch from hosting
    try {
      final url = Uri.parse('$_baseUrl/data/readings/$dateIso.json');
      final res = await _client.get(url, headers: {
        'Accept': 'application/json',
      });

      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final data = jsonDecode(body) as Map<String, dynamic>;
        final readings = DayReadings.fromJson(data);
        _memoryCache[dateIso] = readings;
        await prefs.setString('$prefix$dateIso', body);
        return readings;
      }
    } catch (_) {
      // Offline or network error
    }

    // If fetch failed but we had cached JSON, return it
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        final readings = DayReadings.fromJson(data);
        _memoryCache[dateIso] = readings;
        return readings;
      } catch (_) {}
    }

    return null;
  }

  /// Saves a readings payload directly into local cache (used by background task or seed).
  Future<void> saveToCache(DayReadings readings) async {
    _memoryCache[readings.date] = readings;
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(readings.toJson());
    await prefs.setString('$prefix${readings.date}', jsonStr);
  }

  /// Returns all dates currently cached in local storage.
  Future<List<String>> listCachedDates() async {
    final prefs = await SharedPreferences.getInstance();
    final dates = <String>[];
    for (final key in prefs.getKeys()) {
      if (key.startsWith(prefix)) {
        dates.add(key.substring(prefix.length));
      }
    }
    dates.sort();
    return dates;
  }

  /// Prunes cached days older than [yesterdayIso] (YYYY-MM-DD).
  Future<int> pruneOldReadings(String yesterdayIso) async {
    final prefs = await SharedPreferences.getInstance();
    var removed = 0;
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      final date = key.substring(prefix.length);
      if (date.compareTo(yesterdayIso) < 0) {
        await prefs.remove(key);
        _memoryCache.remove(date);
        removed++;
      }
    }
    return removed;
  }
}
