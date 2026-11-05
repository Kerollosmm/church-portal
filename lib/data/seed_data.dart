import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../domain/features.dart';
import '../domain/models.dart';

/// Typed view over assets/seed/seed.json (bundled fallback content).
class SeedData {
  final Map<String, dynamic> raw;
  SeedData(this.raw);

  static Future<SeedData> load() async {
    try {
      final text = await rootBundle.loadString('assets/seed/seed.json');
      return SeedData(jsonDecode(text) as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('Bundled seed data could not be loaded: $e\n$st');
      return SeedData(const {});
    }
  }

  Map<String, Map<String, dynamic>> collection(String name) {
    final c = raw[name];
    if (c is! Map) return const {};
    return c.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
  }

  List<T> _list<T>(String name, T Function(String, Map<String, dynamic>) f) =>
      collection(name).entries.map((e) => f(e.key, e.value)).toList();

  /// Parsed once, so every read returns the SAME object: the repository and
  /// providers tell the bundled copy from a stored doc with `identical`
  /// (`confirms`, `errorReportingSwitch`, `featuresLive`). As getters they
  /// built a new object per read and that test never matched (ADR-046).
  late final ChurchSettings settings = ChurchSettings.fromMap(collection('settings')['church'] ?? const {});
  ///
  /// The features copy is always its own object, never the shared
  /// [FeatureSettings.defaults] (a seed without features, or one that failed
  /// to load): an empty stored doc parses to that shared constant and must
  /// not be taken for the bundled copy (CodeRabbit on PR #39).
  late final FeatureSettings features = _own(FeatureSettings.fromMap(collection('settings')['features']));

  static FeatureSettings _own(FeatureSettings f) =>
      // A new instance on purpose (not the const), see [features].
      // ignore: prefer_const_constructors
      identical(f, FeatureSettings.defaults) ? FeatureSettings() : f;
  List<Alert> get alerts => _list('alerts', Alert.fromMap);
  List<Season> get seasons => _list('seasons', Season.fromMap);
  List<Liturgy> get liturgies => _list('liturgies', Liturgy.fromMap);
  List<Meeting> get meetings => _list('meetings', Meeting.fromMap);
  List<Activity> get activities => _list('activities', Activity.fromMap);
  List<Clinic> get clinics => _list('clinics', Clinic.fromMap);
  List<Facility> get facilities => _list('facilities', Facility.fromMap);
  List<Priest> get priests => _list('priests', Priest.fromMap)..sort((a, b) => a.order.compareTo(b.order));
  List<Milestone> get milestones => _list('milestones', Milestone.fromMap)..sort((a, b) => a.order.compareTo(b.order));
  List<Saint> get saints => _list('saints', Saint.fromMap)..sort((a, b) => a.order.compareTo(b.order));
}
