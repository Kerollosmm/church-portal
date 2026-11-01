// Pure-Dart domain models. No Flutter / Firebase imports here so the
// business logic stays unit-testable. The data layer normalises Firestore
// values (Timestamp -> DateTime) before calling the `fromMap` factories.

import 'features.dart';
import 'media.dart';

export 'media.dart' show MediaImage;

DateTime? parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
  return null;
}

String _s(Object? v) => v == null ? '' : v.toString();
String? _ns(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int? _ni(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _nd(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

bool _b(Object? v, [bool def = false]) => v is bool ? v : def;

/// Minutes since midnight parsed from "HH:mm". Returns null if invalid.
int? parseHm(String? hm) {
  if (hm == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

class PhoneEntry {
  final String labelAr;
  final String labelEn;
  final String number;
  final bool isMobile;
  const PhoneEntry({required this.labelAr, required this.labelEn, required this.number, this.isMobile = false});
  factory PhoneEntry.fromMap(Map<String, dynamic> m) => PhoneEntry(
        labelAr: _s(m['labelAr'] ?? m['label']),
        labelEn: _s(m['labelEn'] ?? m['label']),
        number: _s(m['number']),
        isMobile: _b(m['isMobile']),
      );
  Map<String, dynamic> toMap() => {'labelAr': labelAr, 'labelEn': labelEn, 'number': number, 'isMobile': isMobile};
}

class Altar {
  final String nameAr;
  final String nameEn;
  final String kind; // main | second | annex
  const Altar({required this.nameAr, required this.nameEn, required this.kind});
  factory Altar.fromMap(Map<String, dynamic> m) =>
      Altar(nameAr: _s(m['nameAr']), nameEn: _s(m['nameEn']), kind: _s(m['kind']));
}

class ChurchSettings {
  final String nameAr, nameEn, addressAr, addressEn;
  final String transportAr, transportEn;
  final double? lat, lng;
  final String mapsUrl, mapsQuery;
  final List<PhoneEntry> phones;
  final String whatsapp, whatsappChannel, facebook, youtube, instagram;
  final String verseAr, verseEn, verseRef, verseRefAr;
  final String heroImageUrl;
  final String historyAr, historyEn;
  final String bishopAr, bishopEn;
  final List<Altar> altars;
  final bool assistantEnabled;
  final bool sample;

  const ChurchSettings({
    required this.nameAr,
    required this.nameEn,
    required this.addressAr,
    required this.addressEn,
    this.transportAr = '',
    this.transportEn = '',
    this.lat,
    this.lng,
    this.mapsUrl = '',
    this.mapsQuery = '',
    this.phones = const [],
    this.whatsapp = '',
    this.whatsappChannel = '',
    this.facebook = '',
    this.youtube = '',
    this.instagram = '',
    this.verseAr = '',
    this.verseEn = '',
    this.verseRef = '',
    this.verseRefAr = '',
    this.heroImageUrl = '',
    this.historyAr = '',
    this.historyEn = '',
    this.bishopAr = '',
    this.bishopEn = '',
    this.altars = const [],
    this.assistantEnabled = false,
    this.sample = false,
  });

  factory ChurchSettings.fromMap(Map<String, dynamic> m) => ChurchSettings(
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        addressAr: _s(m['addressAr']),
        addressEn: _s(m['addressEn']),
        transportAr: _s(m['transportAr']),
        transportEn: _s(m['transportEn']),
        lat: _nd(m['lat']),
        lng: _nd(m['lng']),
        mapsUrl: _s(m['mapsUrl']),
        mapsQuery: _s(m['mapsQuery']),
        phones: ((m['phones'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PhoneEntry.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        whatsapp: _s(m['whatsapp']),
        whatsappChannel: _s(m['whatsappChannel']),
        facebook: _s(m['facebook']),
        youtube: _s(m['youtube']),
        instagram: _s(m['instagram']),
        verseAr: _s(m['verseAr']),
        verseEn: _s(m['verseEn']),
        verseRef: _s(m['verseRef']),
        verseRefAr: _s(m['verseRefAr']),
        heroImageUrl: _s(m['heroImageUrl']),
        historyAr: _s(m['historyAr']),
        historyEn: _s(m['historyEn']),
        bishopAr: _s(m['bishopAr']),
        bishopEn: _s(m['bishopEn']),
        altars: ((m['altars'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Altar.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        assistantEnabled: _b(m['assistantEnabled']),
        sample: _b(m['sample']),
      );
}

class Alert implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  @override
  final int order;
  final String id;
  final String titleAr, titleEn, bodyAr, bodyEn;
  final bool active;
  final DateTime? startsAt, endsAt;
  final int priority;
  final String? link;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Alert({
    this.visible = true,
    this.order = 0,
    required this.id,
    required this.titleAr,
    required this.titleEn,
    this.bodyAr = '',
    this.bodyEn = '',
    this.active = true,
    this.startsAt,
    this.endsAt,
    this.priority = 0,
    this.link,
    this.image,
  });
  factory Alert.fromMap(String id, Map<String, dynamic> m) => Alert(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        bodyAr: _s(m['bodyAr']),
        bodyEn: _s(m['bodyEn']),
        active: _b(m['active']),
        startsAt: parseDate(m['startsAt']),
        endsAt: parseDate(m['endsAt']),
        priority: _ni(m['priority']) ?? 0,
        link: _ns(m['link']),
        image: MediaImage.fromMap(m['image']),
      );
}

class Season {
  final String id;
  final String key;
  final String nameAr, nameEn;
  final DateTime? startsAt, endsAt;
  final bool active;

  /// true (Holy Week, Pascha, Nativity): its services REPLACE the regular
  /// schedule on the days they cover. false (evening revivals): ADDITIVE, the
  /// regular morning masses continue. Missing in Firestore = true, so older
  /// documents behave exactly as before.
  final bool replacesRegular;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Season({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.startsAt,
    this.endsAt,
    this.active = true,
    this.replacesRegular = true,
    this.image,
  });
  factory Season.fromMap(String id, Map<String, dynamic> m) => Season(
        id: id,
        key: _s(m['key']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        startsAt: parseDate(m['startsAt']),
        endsAt: parseDate(m['endsAt']),
        active: _b(m['active']),
        replacesRegular: m['replacesRegular'] is bool ? m['replacesRegular'] as bool : true,
        image: MediaImage.fromMap(m['image']),
      );
}

class Liturgy implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  final String id;
  final String type; // mass | vespers | praise | other
  final String nameAr, nameEn;
  final int? weekday; // ISO 1=Mon .. 7=Sun
  final DateTime? date; // one-off (calendar date in Cairo)
  final String start, end; // HH:mm
  final String placeAr, placeEn, audienceAr, audienceEn;
  final String? seasonKey;
  @override
  final int order;

  /// Placeholder time not yet confirmed by the church.
  final bool sample;
  const Liturgy({
    this.visible = true,
    required this.id,
    required this.type,
    required this.nameAr,
    required this.nameEn,
    this.weekday,
    this.date,
    required this.start,
    required this.end,
    this.placeAr = '',
    this.placeEn = '',
    this.audienceAr = '',
    this.audienceEn = '',
    this.seasonKey,
    this.order = 0,
    this.sample = false,
  });
  factory Liturgy.fromMap(String id, Map<String, dynamic> m) => Liturgy(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        type: _s(m['type']).isEmpty ? 'mass' : _s(m['type']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        weekday: _ni(m['weekday']),
        date: parseDate(m['date']),
        start: _s(m['start']),
        end: _s(m['end']),
        placeAr: _s(m['placeAr']),
        placeEn: _s(m['placeEn']),
        audienceAr: _s(m['audienceAr']),
        audienceEn: _s(m['audienceEn']),
        seasonKey: _ns(m['seasonKey']),
        order: _ni(m['order']) ?? 0,
        sample: _b(m['sample']),
      );
  int? get startMinutes => parseHm(start);
  int? get endMinutes => parseHm(end);
}

class Meeting implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  @override
  final int order;
  final String id, stage, nameAr, nameEn;
  final int? weekday;
  final String start, end, hallAr, hallEn;
  final String facebookUrl, whatsappUrl, notes;
  final bool sample;
  const Meeting({
    this.visible = true,
    this.order = 0,
    required this.id,
    required this.stage,
    required this.nameAr,
    required this.nameEn,
    this.weekday,
    this.start = '',
    this.end = '',
    this.hallAr = '',
    this.hallEn = '',
    this.facebookUrl = '',
    this.whatsappUrl = '',
    this.notes = '',
    this.sample = false,
  });
  factory Meeting.fromMap(String id, Map<String, dynamic> m) => Meeting(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        stage: _s(m['stage']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        weekday: _ni(m['weekday']),
        start: _s(m['start']),
        end: _s(m['end']),
        hallAr: _s(m['hallAr']),
        hallEn: _s(m['hallEn']),
        facebookUrl: _s(m['facebookUrl']),
        whatsappUrl: _s(m['whatsappUrl']),
        notes: _s(m['notes']),
        sample: _b(m['sample']),
      );
}

class Activity implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  @override
  final int order;
  final String id, category, titleAr, titleEn, descAr, descEn, scheduleAr, scheduleEn, ageRange, contactPhone;

  /// Optional external page (Facebook page, YouTube playlist...).
  final String link;
  final bool sample;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Activity({
    this.visible = true,
    this.order = 0,
    required this.id,
    required this.category,
    required this.titleAr,
    required this.titleEn,
    this.descAr = '',
    this.descEn = '',
    this.scheduleAr = '',
    this.scheduleEn = '',
    this.ageRange = '',
    this.contactPhone = '',
    this.link = '',
    this.image,
    this.sample = false,
  });
  factory Activity.fromMap(String id, Map<String, dynamic> m) => Activity(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        category: _s(m['category']),
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        descAr: _s(m['descAr']),
        descEn: _s(m['descEn']),
        scheduleAr: _s(m['scheduleAr']),
        scheduleEn: _s(m['scheduleEn']),
        ageRange: _s(m['ageRange']),
        contactPhone: _s(m['contactPhone']),
        link: _s(m['link']),
        image: MediaImage.fromMap(m['image']),
        sample: _b(m['sample']),
      );
}

class Clinic implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  @override
  final int order;
  final String id, specialty, specialtyAr, specialtyEn, doctorName, degreeAr, degreeEn;
  final List<int> days;
  final String start, end, bookingPhone, whatsapp;
  final bool active;
  final bool sample;
  const Clinic({
    this.visible = true,
    this.order = 0,
    required this.id,
    required this.specialty,
    required this.specialtyAr,
    required this.specialtyEn,
    required this.doctorName,
    this.degreeAr = '',
    this.degreeEn = '',
    this.days = const [],
    this.start = '',
    this.end = '',
    this.bookingPhone = '',
    this.whatsapp = '',
    this.active = true,
    this.sample = false,
  });
  factory Clinic.fromMap(String id, Map<String, dynamic> m) => Clinic(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        specialty: _s(m['specialty']),
        specialtyAr: _s(m['specialtyAr']),
        specialtyEn: _s(m['specialtyEn']),
        doctorName: _s(m['doctorName']),
        degreeAr: _s(m['degreeAr']),
        degreeEn: _s(m['degreeEn']),
        days: ((m['days'] as List?) ?? const []).map(_ni).whereType<int>().toList(),
        start: _s(m['start']),
        end: _s(m['end']),
        bookingPhone: _s(m['bookingPhone']),
        whatsapp: _s(m['whatsapp']),
        active: m['active'] is bool ? m['active'] as bool : true,
        sample: _b(m['sample']),
      );
}

class Facility implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  @override
  final int order;
  final String id, type, nameAr, nameEn, descAr, descEn, phone, hoursAr, hoursEn;
  final bool sample;
  const Facility({
    this.visible = true,
    this.order = 0,
    required this.id,
    required this.type,
    required this.nameAr,
    required this.nameEn,
    this.descAr = '',
    this.descEn = '',
    this.phone = '',
    this.hoursAr = '',
    this.hoursEn = '',
    this.sample = false,
  });
  factory Facility.fromMap(String id, Map<String, dynamic> m) => Facility(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        type: _s(m['type']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        descAr: _s(m['descAr']),
        descEn: _s(m['descEn']),
        phone: _s(m['phone']),
        hoursAr: _s(m['hoursAr']),
        hoursEn: _s(m['hoursEn']),
        sample: _b(m['sample']),
      );
}

class Priest implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  final String id, name, nameEn, photoUrl, rank, status, bioAr, bioEn;
  final String ordinationDate, hegumenDate, departedDate;
  @override
  final int order;
  final bool sample;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Priest({
    this.visible = true,
    required this.id,
    required this.name,
    this.nameEn = '',
    this.photoUrl = '',
    this.rank = 'priest',
    this.ordinationDate = '',
    this.hegumenDate = '',
    this.departedDate = '',
    this.status = 'serving',
    this.bioAr = '',
    this.bioEn = '',
    this.order = 0,
    this.sample = false,
    this.image,
  });
  factory Priest.fromMap(String id, Map<String, dynamic> m) => Priest(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        name: _s(m['name']),
        nameEn: _s(m['nameEn']),
        photoUrl: _s(m['photoUrl']),
        rank: _s(m['rank']).isEmpty ? 'priest' : _s(m['rank']),
        ordinationDate: _s(m['ordinationDate']),
        hegumenDate: _s(m['hegumenDate']),
        departedDate: _s(m['departedDate']),
        status: _s(m['status']).isEmpty ? 'serving' : _s(m['status']),
        bioAr: _s(m['bioAr']),
        bioEn: _s(m['bioEn']),
        order: _ni(m['order']) ?? 0,
        sample: _b(m['sample']),
        image: MediaImage.fromMap(m['image']),
      );
  bool get departed => status == 'departed';

  /// [image], else the legacy `photoUrl` when it is an https URL.
  MediaImage? get displayImage => image ?? (isValidImageUrl(photoUrl) ? MediaImage.url(photoUrl) : null);
}

class Milestone implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  final String id, titleAr, titleEn, descAr, descEn, icon;
  final int? year;
  @override
  final int order;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Milestone({
    this.visible = true,
    required this.id,
    required this.titleAr,
    required this.titleEn,
    this.descAr = '',
    this.descEn = '',
    this.year,
    this.icon = '',
    this.order = 0,
    this.image,
  });
  factory Milestone.fromMap(String id, Map<String, dynamic> m) => Milestone(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        descAr: _s(m['descAr']),
        descEn: _s(m['descEn']),
        year: _ni(m['year']),
        icon: _s(m['icon']),
        order: _ni(m['order']) ?? 0,
        image: MediaImage.fromMap(m['image']),
      );
}

class Saint implements Hideable {

  /// Shown on the public site (false = hidden by an admin, not deleted).
  @override
  final bool visible;
  final String id, nameAr, nameEn, bioAr, bioEn, feastCopticAr, feastCopticEn, feastGregorian, feastGregorianAr;
  @override
  final int order;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;
  const Saint({
    this.visible = true,
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.bioAr = '',
    this.bioEn = '',
    this.feastCopticAr = '',
    this.feastCopticEn = '',
    this.feastGregorian = '',
    this.feastGregorianAr = '',
    this.order = 0,
    this.image,
  });
  factory Saint.fromMap(String id, Map<String, dynamic> m) => Saint(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        bioAr: _s(m['bioAr']),
        bioEn: _s(m['bioEn']),
        feastCopticAr: _s(m['feastCopticAr']),
        feastCopticEn: _s(m['feastCopticEn']),
        feastGregorian: _s(m['feastGregorian']),
        feastGregorianAr: _s(m['feastGregorianAr']),
        order: _ni(m['order']) ?? 0,
        image: MediaImage.fromMap(m['image']),
      );
}
