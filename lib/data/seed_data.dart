import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/models.dart';

/// Typed view over assets/seed/seed.json (bundled fallback content).
class SeedData {
  final Map<String, dynamic> raw;
  SeedData(this.raw);

  static Future<SeedData> load() async {
    try {
      final text = await rootBundle.loadString('assets/seed/seed.json');
      return SeedData(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
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

  ChurchSettings get settings => ChurchSettings.fromMap(collection('settings')['church'] ?? const {});
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
