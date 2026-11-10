/// Domain models for Katameros daily readings (ADR-058 / PR B §3.5).
///
/// Pure Dart model representing the day's readings loaded from static Hosting
/// JSON `/data/readings/<YYYY-MM-DD>.json`. Tolerant parser handles missing
/// sections or unexpected reading kinds gracefully.
class DayReadings {
  final String date;
  final String coptic;
  final String titleAr;
  final String titleEn;
  final List<ReadingsSection> sections;
  final String source;
  final String bibleAr;
  final String bibleEn;

  const DayReadings({
    required this.date,
    required this.coptic,
    required this.titleAr,
    required this.titleEn,
    required this.sections,
    required this.source,
    required this.bibleAr,
    required this.bibleEn,
  });

  /// The Liturgy Gospel reading if present (used for daily notification summary:
  /// «قراءات اليوم — {feast}» / «إنجيل القداس: {ref}»).
  ReadingItem? get liturgyGospel {
    for (final sec in sections) {
      if (sec.key == 'liturgy') {
        for (final r in sec.readings) {
          if (r.kind == 'gospel') return r;
        }
      }
    }
    // Fallback: search any gospel
    for (final sec in sections) {
      for (final r in sec.readings) {
        if (r.kind == 'gospel') return r;
      }
    }
    return null;
  }

  /// Title for display in current locale.
  String title(bool isAr) {
    if (isAr) return titleAr.isNotEmpty ? titleAr : titleEn;
    return titleEn.isNotEmpty ? titleEn : titleAr;
  }

  factory DayReadings.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final List<ReadingsSection> sectionsList = [];
    if (rawSections is List) {
      for (final s in rawSections) {
        if (s is Map<String, dynamic>) {
          sectionsList.add(ReadingsSection.fromJson(s));
        } else if (s is Map) {
          sectionsList.add(ReadingsSection.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }

    return DayReadings(
      date: json['date'] as String? ?? '',
      coptic: json['coptic'] as String? ?? '',
      titleAr: json['titleAr'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      sections: List.unmodifiable(sectionsList),
      source: json['source'] as String? ?? 'api.katameros.app',
      bibleAr: json['bibleAr'] as String? ?? 'Van Dyck',
      bibleEn: json['bibleEn'] as String? ?? 'refs-only',
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'coptic': coptic,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'sections': sections.map((s) => s.toJson()).toList(),
        'source': source,
        'bibleAr': bibleAr,
        'bibleEn': bibleEn,
      };
}

class ReadingsSection {
  final String key; // vespers, matins, liturgy, or other
  final String titleAr;
  final String titleEn;
  final List<ReadingItem> readings;

  const ReadingsSection({
    required this.key,
    required this.titleAr,
    required this.titleEn,
    required this.readings,
  });

  String title(bool isAr) {
    if (isAr) return titleAr.isNotEmpty ? titleAr : titleEn;
    return titleEn.isNotEmpty ? titleEn : titleAr;
  }

  factory ReadingsSection.fromJson(Map<String, dynamic> json) {
    final rawReadings = json['readings'];
    final List<ReadingItem> items = [];
    if (rawReadings is List) {
      for (final r in rawReadings) {
        if (r is Map<String, dynamic>) {
          items.add(ReadingItem.fromJson(r));
        } else if (r is Map) {
          items.add(ReadingItem.fromJson(Map<String, dynamic>.from(r)));
        }
      }
    }

    return ReadingsSection(
      key: json['key'] as String? ?? 'other',
      titleAr: json['titleAr'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      readings: List.unmodifiable(items),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'readings': readings.map((r) => r.toJson()).toList(),
      };
}

class ReadingItem {
  final String kind; // psalm, gospel, pauline, catholic, acts, synaxarium, other
  final String titleAr;
  final String titleEn;
  final String refAr;
  final String refEn;
  final String introAr;
  final String introEn;
  final String textAr;
  final String textEn;
  final String conclusionAr;
  final String conclusionEn;

  const ReadingItem({
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    required this.refAr,
    required this.refEn,
    required this.introAr,
    required this.introEn,
    required this.textAr,
    required this.textEn,
    required this.conclusionAr,
    required this.conclusionEn,
  });

  String title(bool isAr) {
    if (isAr) return titleAr.isNotEmpty ? titleAr : titleEn;
    return titleEn.isNotEmpty ? titleEn : titleAr;
  }

  String reference(bool isAr) {
    if (isAr) return refAr.isNotEmpty ? refAr : refEn;
    return refEn.isNotEmpty ? refEn : refAr;
  }

  String intro(bool isAr) {
    if (isAr) return introAr;
    return introEn.isNotEmpty ? introEn : introAr;
  }

  String text(bool isAr) {
    if (isAr) return textAr;
    return textEn.isNotEmpty ? textEn : textAr;
  }

  String conclusion(bool isAr) {
    if (isAr) return conclusionAr;
    return conclusionEn.isNotEmpty ? conclusionEn : conclusionAr;
  }

  factory ReadingItem.fromJson(Map<String, dynamic> json) {
    return ReadingItem(
      kind: json['kind'] as String? ?? 'other',
      titleAr: json['titleAr'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      refAr: json['refAr'] as String? ?? '',
      refEn: json['refEn'] as String? ?? '',
      introAr: json['introAr'] as String? ?? '',
      introEn: json['introEn'] as String? ?? '',
      textAr: json['textAr'] as String? ?? '',
      textEn: json['textEn'] as String? ?? '',
      conclusionAr: json['conclusionAr'] as String? ?? '',
      conclusionEn: json['conclusionEn'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'refAr': refAr,
        'refEn': refEn,
        'introAr': introAr,
        'introEn': introEn,
        'textAr': textAr,
        'textEn': textEn,
        'conclusionAr': conclusionAr,
        'conclusionEn': conclusionEn,
      };
}
