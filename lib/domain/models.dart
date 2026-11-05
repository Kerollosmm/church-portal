// Pure-Dart domain models. No Flutter / Firebase imports here so the
// business logic stays unit-testable. The data layer normalises Firestore
// values (Timestamp -> DateTime) before calling the `fromMap` factories.

import 'features.dart';
import 'media.dart';
import 'pending_text.dart';
import 'program.dart';

export 'media.dart' show MediaImage;
export 'program.dart' show ProgramInfo, ProgramOption, ProgramOptions;

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

/// One admin-defined "title: value" row on an item's detail page.
class CustomField {
  final String titleAr, titleEn, valueAr, valueEn;
  const CustomField({this.titleAr = '', this.titleEn = '', this.valueAr = '', this.valueEn = ''});

  bool get isEmpty =>
      titleAr.trim().isEmpty && titleEn.trim().isEmpty && valueAr.trim().isEmpty && valueEn.trim().isEmpty;

  factory CustomField.fromMap(Map<String, dynamic> m) => CustomField(
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        valueAr: _s(m['valueAr']),
        valueEn: _s(m['valueEn']),
      );

  Map<String, dynamic> toMap() => {'titleAr': titleAr, 'titleEn': titleEn, 'valueAr': valueAr, 'valueEn': valueEn};
}

/// Optional item detail page shared by meetings, activities, clinics,
/// facilities, priests, milestones and saints (not liturgies, seasons or
/// alerts). Every field is optional. Detail pages are opt-OUT (PR #14): a
/// missing `detailsEnabled` means the page is on; only an explicit `false`
/// (an admin switching it off) removes it. Images / contacts / socials are
/// shown wherever the item already shows them.
class ItemDetails {
  final bool detailsEnabled, showDetailImages, showContacts, showSocials;
  final String detailsAr, detailsEn;

  /// Non-empty rows only, at most [MediaLimits.maxExtraFields].
  final List<CustomField> extraFields;

  /// Usable images only, at most [MediaLimits.maxGalleryItems]. Inline bytes
  /// (`media/{id}`) are fetched only when the detail page opens.
  final List<MediaImage> gallery;

  /// Primary phone: `contactPhone`, or the collection's existing phone field
  /// (clinics: `bookingPhone`, facilities: `phone`).
  final String contactPhone;

  /// WhatsApp number (chat) and WhatsApp group / channel URL.
  final String whatsapp, whatsappUrl;
  final String facebookUrl, youtubeUrl, instagramUrl;

  /// External / registration button: `externalUrl` (activities: their
  /// existing `link`) with an optional custom label.
  final String externalUrl, externalLabelAr, externalLabelEn;

  /// How to contact / register.
  final String contactNoteAr, contactNoteEn;

  const ItemDetails({
    this.detailsEnabled = true,
    this.showDetailImages = true,
    this.showContacts = true,
    this.showSocials = true,
    this.detailsAr = '',
    this.detailsEn = '',
    this.extraFields = const [],
    this.gallery = const [],
    this.contactPhone = '',
    this.whatsapp = '',
    this.whatsappUrl = '',
    this.facebookUrl = '',
    this.youtubeUrl = '',
    this.instagramUrl = '',
    this.externalUrl = '',
    this.externalLabelAr = '',
    this.externalLabelEn = '',
    this.contactNoteAr = '',
    this.contactNoteEn = '',
  });

  /// No admin-entered details: the page still shows the item's own info.
  static const none = ItemDetails();

  /// [phoneKey] / [urlKey] name the document field holding the primary phone
  /// and the external link (so a collection never gets a duplicate input).
  factory ItemDetails.fromMap(Map<String, dynamic> m,
      {String phoneKey = 'contactPhone', String urlKey = 'externalUrl'}) {
    final rawFields = m['extraFields'];
    final rawGallery = m['gallery'];
    return ItemDetails(
      detailsEnabled: _b(m['detailsEnabled'], true),
      showDetailImages: _b(m['showDetailImages'], true),
      showContacts: _b(m['showContacts'], true),
      showSocials: _b(m['showSocials'], true),
      detailsAr: _s(m['detailsAr']),
      detailsEn: _s(m['detailsEn']),
      extraFields: rawFields is List
          ? rawFields
              .whereType<Map>()
              .map((e) => CustomField.fromMap(Map<String, dynamic>.from(e)))
              .where((f) => !f.isEmpty)
              .take(MediaLimits.maxExtraFields)
              .toList()
          : const [],
      gallery: rawGallery is List
          ? rawGallery.map(MediaImage.fromMap).whereType<MediaImage>().take(MediaLimits.maxGalleryItems).toList()
          : const [],
      contactPhone: _s(m[phoneKey]),
      whatsapp: _s(m['whatsapp']),
      whatsappUrl: _s(m['whatsappUrl']),
      facebookUrl: _s(m['facebookUrl']),
      youtubeUrl: _s(m['youtubeUrl']),
      instagramUrl: _s(m['instagramUrl']),
      externalUrl: _s(m[urlKey]),
      externalLabelAr: _s(m['externalLabelAr']),
      externalLabelEn: _s(m['externalLabelEn']),
      contactNoteAr: _s(m['contactNoteAr']),
      contactNoteEn: _s(m['contactNoteEn']),
    );
  }
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

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
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
    this.imageStyle = '',
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
        imageStyle: _s(m['imageStyle']),
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

  /// ADR-051: civil Cairo dates ('YYYY-MM-DD') on which an ADDITIVE season
  /// still replaces the regular services that start inside its window (the
  /// feast night of a revival or a fast). Ignored when [replacesRegular].
  final List<String> replaceDates;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;

  /// Optional programme details (speaker, topic, choir, venue, audience, PDF
  /// link; ADR-041).
  final ProgramInfo program;
  const Season({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.startsAt,
    this.endsAt,
    this.active = true,
    this.replacesRegular = true,
    this.replaceDates = const [],
    this.image,
    this.imageStyle = '',
    this.program = ProgramInfo.none,
  });

  static final _ymdRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// A real calendar date 'YYYY-MM-DD' (2027-02-31 is refused; CodeRabbit on PR #44).
  static bool _isCalendarDate(String s) {
    final m = _ymdRe.firstMatch(s);
    if (m == null) return false;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final dt = DateTime.utc(y, mo, d);
    return dt.year == y && dt.month == mo && dt.day == d;
  }

  /// Does the season replace the regular services on the Cairo calendar day
  /// [day] (y/m/d read as is)? Always for a full-override season; for an
  /// additive one only on its [replaceDates] (ADR-051).
  bool replacesOn(DateTime day) {
    if (replacesRegular) return true;
    if (replaceDates.isEmpty) return false;
    String two(int v) => v.toString().padLeft(2, '0');
    return replaceDates.contains('${day.year}-${two(day.month)}-${two(day.day)}');
  }
  factory Season.fromMap(String id, Map<String, dynamic> m) => Season(
        id: id,
        key: _s(m['key']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        startsAt: parseDate(m['startsAt']),
        endsAt: parseDate(m['endsAt']),
        active: _b(m['active']),
        replacesRegular: m['replacesRegular'] is bool ? m['replacesRegular'] as bool : true,
        replaceDates: m['replaceDates'] is List
            ? [
                for (final d in m['replaceDates'] as List)
                  if (d is String && _isCalendarDate(d.trim())) d.trim(),
              ]
            : const [],
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        program: ProgramInfo.fromMap(m),
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

  /// Optional programme details (speaker, topic, choir, venue, audience, PDF
  /// link; ADR-041).
  final ProgramInfo program;

  /// A seasonal feast liturgy that replaces EVERY regular mass of its day in
  /// an additive season (admin checkbox «يحل محل قداسات اليوم المعتادة»;
  /// ADR-050). Off (the default), a seasonal mass hides only the regular
  /// masses that overlap it in time.
  final bool replacesDay;
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
    this.program = ProgramInfo.none,
    this.replacesDay = false,
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
        program: ProgramInfo.fromMap(m),
        replacesDay: _b(m['replacesDay']),
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
  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;

  /// Optional programme details (speaker, topic, choir, venue, audience, PDF
  /// link; ADR-041).
  final ProgramInfo program;
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
    this.image,
    this.imageStyle = '',
    this.details = ItemDetails.none,
    this.program = ProgramInfo.none,
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
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m),
        program: ProgramInfo.fromMap(m),
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
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;

  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
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
    this.imageStyle = '',
    this.sample = false,
    this.details = ItemDetails.none,
  });
  factory Activity.fromMap(String id, Map<String, dynamic> m) => Activity(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        category: _s(m['category']),
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        descAr: stripPendingPlaceholders(_s(m['descAr'])),
        descEn: stripPendingPlaceholders(_s(m['descEn'])),
        scheduleAr: _s(m['scheduleAr']),
        scheduleEn: _s(m['scheduleEn']),
        ageRange: _s(m['ageRange']),
        contactPhone: _s(m['contactPhone']),
        link: _s(m['link']),
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        sample: _b(m['sample']),
        details: ItemDetails.fromMap(m, urlKey: 'link'),
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
  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;
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
    this.image,
    this.imageStyle = '',
    this.details = ItemDetails.none,
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
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m, phoneKey: 'bookingPhone'),
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
  /// Optional picture (null = keep the icon / initials placeholder).
  final MediaImage? image;

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;
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
    this.image,
    this.imageStyle = '',
    this.details = ItemDetails.none,
  });
  factory Facility.fromMap(String id, Map<String, dynamic> m) => Facility(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        order: _ni(m['order']) ?? 0,
        id: id,
        type: _s(m['type']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        descAr: stripPendingPlaceholders(_s(m['descAr'])),
        descEn: stripPendingPlaceholders(_s(m['descEn'])),
        phone: _s(m['phone']),
        hoursAr: _s(m['hoursAr']),
        hoursEn: _s(m['hoursEn']),
        sample: _b(m['sample']),
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m, phoneKey: 'phone'),
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

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;
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
    this.imageStyle = '',
    this.details = ItemDetails.none,
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
        bioAr: stripPendingPlaceholders(_s(m['bioAr'])),
        bioEn: stripPendingPlaceholders(_s(m['bioEn'])),
        order: _ni(m['order']) ?? 0,
        sample: _b(m['sample']),
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m),
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

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;
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
    this.imageStyle = '',
    this.details = ItemDetails.none,
  });
  factory Milestone.fromMap(String id, Map<String, dynamic> m) => Milestone(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        descAr: stripPendingPlaceholders(_s(m['descAr'])),
        descEn: stripPendingPlaceholders(_s(m['descEn'])),
        year: _ni(m['year']),
        icon: _s(m['icon']),
        order: _ni(m['order']) ?? 0,
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m),
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

  /// How [image] is displayed on the card (ImageStyles); '' = section default.
  final String imageStyle;
  /// Detail page settings (on unless an admin switches it off).
  final ItemDetails details;
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
    this.imageStyle = '',
    this.details = ItemDetails.none,
  });
  factory Saint.fromMap(String id, Map<String, dynamic> m) => Saint(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        id: id,
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        bioAr: stripPendingPlaceholders(_s(m['bioAr'])),
        bioEn: stripPendingPlaceholders(_s(m['bioEn'])),
        feastCopticAr: _s(m['feastCopticAr']),
        feastCopticEn: _s(m['feastCopticEn']),
        feastGregorian: _s(m['feastGregorian']),
        feastGregorianAr: _s(m['feastGregorianAr']),
        order: _ni(m['order']) ?? 0,
        image: MediaImage.fromMap(m['image']),
        imageStyle: _s(m['imageStyle']),
        details: ItemDetails.fromMap(m),
      );
}
