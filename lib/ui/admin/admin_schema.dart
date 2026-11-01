/// Field schemas for the admin editors (collections + the church-info doc).
library;

enum FieldType {
  text,
  multiline,
  integer,
  decimal,
  boolean,
  time,
  weekday,
  weekdays,
  dateTime,
  date,

  /// YYYY, YYYY-MM or YYYY-MM-DD (priests' ordination dates).
  looseDate,
  choice,
  url,
  phone,

  /// List of small maps edited as rows (phones, altars).
  objectList,

  /// Optional picture: `image` map {source, url | mediaId, alt, w, h}
  /// (upload from the device, paste an https link, or remove).
  image,
}

class FieldDef {
  final String key;
  final String labelAr;
  final String labelEn;
  final FieldType type;
  final bool required;
  final List<String> options; // for choice
  final bool nullableChoice;

  /// Choice value used when the stored document has none (match the
  /// reader's default in models.dart; null = first option).
  final String? defaultOption;

  /// Boolean value assumed when an EXISTING document lacks the field (match
  /// the reader's default in models.dart).
  final bool missingBool;

  /// Boolean value a NEW document starts with.
  final bool newBool;

  /// Max characters for text fields (0 = type default).
  final int maxLength;

  /// Inclusive numeric bounds for integer / decimal fields.
  final num? min, max;

  /// URL fields: also accept in-app paths such as /mass-schedule.
  final bool allowPath;

  /// Row fields for [FieldType.objectList].
  final List<FieldDef> subFields;

  /// Optional helper text under the field.
  final String hintAr, hintEn;

  /// Max rows for [FieldType.objectList] (matches firestore.rules).
  final int maxRows;

  const FieldDef(this.key, this.labelAr, this.labelEn, this.type,
      {this.required = false,
      this.options = const [],
      this.nullableChoice = false,
      this.defaultOption,
      this.missingBool = false,
      this.newBool = true,
      this.maxLength = 0,
      this.min,
      this.max,
      this.allowPath = false,
      this.subFields = const [],
      this.hintAr = '',
      this.hintEn = '',
      this.maxRows = 20});

  int get effectiveMaxLength => maxLength > 0
      ? maxLength
      : switch (type) {
          FieldType.multiline => 5000,
          FieldType.url => 500,
          FieldType.phone => 20,
          _ => 300,
        };
}

class CollectionDef {
  /// Admin screen id (unique). Usually the collection name.
  final String id;

  /// Firestore collection.
  final String name;
  final String labelAr;
  final String labelEn;
  final List<FieldDef> fields;
  final List<String> titleKeys;

  /// At least one of these fields must be set (e.g. weekday or one-off date).
  final List<String> requireAnyOf;

  /// Admin can drag to reorder (writes `order`).
  final bool orderable;

  /// Only documents where data[key] == value (e.g. departed priests).
  final MapEntry<String, String>? filter;

  /// Values a new document starts with (applied over field defaults).
  final Map<String, Object?> newDefaults;

  /// Icon name for the dashboard (see admin_page.dart `adminIcon`).
  final String icon;

  /// Public route showing this content (for "open on site" links).
  final String publicPath;

  const CollectionDef(this.name, this.labelAr, this.labelEn, this.fields, this.titleKeys,
      {String? id,
      this.requireAnyOf = const [],
      this.orderable = false,
      this.filter,
      this.newDefaults = const {},
      this.icon = 'list',
      this.publicPath = '/'})
      : id = id ?? name;

  bool matches(Map<String, dynamic> data) {
    final f = filter;
    if (f == null) return true;
    var v = data[f.key]?.toString();
    if (v == null || v.isEmpty) {
      // Absent = the reader's default (e.g. Priest.status defaults to serving).
      for (final fd in fields) {
        if (fd.key == f.key) v = fd.defaultOption;
      }
    }
    return v == f.value;
  }

  bool get hasVisible => fields.any((f) => f.key == 'visible');
  bool get hasSample => fields.any((f) => f.key == 'sample');
}

/// A single document edited as a form (church info).
class DocDef {
  final String path;
  final String labelAr, labelEn;
  final List<FieldDef> fields;
  const DocDef(this.path, this.labelAr, this.labelEn, this.fields);
}

const seasonKeys = ['holy_week', 'pascha', 'nativity', 'revival_maximus', 'revival_moses', 'summer'];

/// "Unconfirmed" flag: untick once the church has confirmed the entry, so
/// the public pages stop showing the pending-confirmation notice.
const _sampleField = FieldDef('sample', 'غير مؤكد (في انتظار تأكيد الكنيسة)', 'Unconfirmed (pending church confirmation)',
    FieldType.boolean,
    newBool: false);

/// Public visibility: hidden items stay in the database but disappear from the site.
const _visibleField = FieldDef('visible', 'ظاهر في الموقع', 'Visible on the site', FieldType.boolean,
    missingBool: true, newBool: true);

const _orderField = FieldDef('order', 'الترتيب', 'Order', FieldType.integer, min: -100000, max: 100000);

/// Optional picture shown as the card image / avatar (never required).
const _imageField = FieldDef('image', 'الصورة (اختياري)', 'Image (optional)', FieldType.image);

/// Collections whose documents may carry an `image` (see lib/domain/media.dart).
const imageCollections = ['alerts', 'seasons', 'activities', 'priests', 'milestones', 'saints'];

const _priestFields = [
  FieldDef('name', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
  FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
  _imageField, // replaces the legacy photoUrl text field (still read as a fallback)
  FieldDef('rank', 'الرتبة', 'Rank', FieldType.choice, options: ['hegumen', 'priest'], defaultOption: 'priest'),
  FieldDef('ordinationDate', 'تاريخ الرسامة', 'Ordination date', FieldType.looseDate),
  FieldDef('hegumenDate', 'تاريخ القمصية', 'Hegumen date', FieldType.looseDate),
  FieldDef('status', 'الحالة', 'Status', FieldType.choice, options: ['serving', 'departed'], defaultOption: 'serving'),
  FieldDef('departedDate', 'تاريخ النياحة', 'Departure date', FieldType.looseDate),
  FieldDef('bioAr', 'نبذة (عربي)', 'Bio (Arabic)', FieldType.multiline),
  FieldDef('bioEn', 'نبذة (إنجليزي)', 'Bio (English)', FieldType.multiline),
  _orderField,
  _visibleField,
  _sampleField,
];

const adminCollections = <CollectionDef>[
  CollectionDef('alerts', 'التنويهات', 'Alerts', [
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('bodyAr', 'النص (عربي)', 'Body (Arabic)', FieldType.multiline, maxLength: 1000),
    FieldDef('bodyEn', 'النص (إنجليزي)', 'Body (English)', FieldType.multiline, maxLength: 1000),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
    FieldDef('startsAt', 'يبدأ (توقيت القاهرة)', 'Starts (Cairo time)', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي (توقيت القاهرة)', 'Ends (Cairo time)', FieldType.dateTime),
    FieldDef('priority', 'الأولوية (الأعلى يظهر أولًا)', 'Priority (higher shows first)', FieldType.integer,
        min: 0, max: 1000),
    FieldDef('link', 'رابط (مثل /mass-schedule)', 'Link (e.g. /mass-schedule)', FieldType.url, allowPath: true),
    _imageField,
    _visibleField,
  ], [
    'titleAr',
    'titleEn'
  ], icon: 'alerts', publicPath: '/'),
  CollectionDef('seasons', 'المواسم', 'Seasons', [
    FieldDef('key', 'نوع الموسم', 'Season key', FieldType.choice, required: true, options: seasonKeys),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('startsAt', 'يبدأ (توقيت القاهرة)', 'Starts (Cairo time)', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي (توقيت القاهرة)', 'Ends (Cairo time)', FieldType.dateTime),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
    FieldDef(
      'replacesRegular',
      'يستبدل الجدول العادي (أوقفها للنهضات المسائية)',
      'Replaces regular schedule (off for evening revivals)',
      FieldType.boolean,
      missingBool: true,
    ),
    _imageField,
  ], [
    'nameAr',
    'key'
  ], icon: 'seasons', publicPath: '/mass-schedule'),
  CollectionDef('liturgies', 'القداسات والصلوات', 'Liturgies', [
    FieldDef('type', 'النوع', 'Type', FieldType.choice, required: true, options: ['mass', 'vespers', 'praise', 'other']),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('weekday', 'يوم الأسبوع (للجدول الأسبوعي)', 'Weekday (weekly schedule)', FieldType.weekday),
    FieldDef('date', 'تاريخ محدد (لمرة واحدة)', 'One-off date', FieldType.date),
    FieldDef('start', 'من (HH:mm)', 'From (HH:mm)', FieldType.time, required: true),
    FieldDef('end', 'إلى (HH:mm)', 'To (HH:mm)', FieldType.time),
    FieldDef('placeAr', 'المكان (عربي)', 'Place (Arabic)', FieldType.text),
    FieldDef('placeEn', 'المكان (إنجليزي)', 'Place (English)', FieldType.text),
    FieldDef('audienceAr', 'الفئة/ملاحظات (عربي)', 'Audience/notes (Arabic)', FieldType.text),
    FieldDef('audienceEn', 'الفئة/ملاحظات (إنجليزي)', 'Audience/notes (English)', FieldType.text),
    FieldDef('seasonKey', 'الموسم (فارغ = الجدول العادي)', 'Season (empty = regular)', FieldType.choice,
        options: seasonKeys, nullableChoice: true),
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'nameAr',
    'start'
  ], requireAnyOf: [
    'weekday',
    'date'
  ], icon: 'liturgies', publicPath: '/mass-schedule'),
  CollectionDef('meetings', 'الاجتماعات', 'Meetings', [
    FieldDef('stage', 'المرحلة', 'Stage', FieldType.choice, required: true, options: [
      'angels', 'primary', 'preparatory', 'secondary', 'youth', 'university', 'graduates', //
      'family', 'men', 'women', 'elderly',
    ]),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('weekday', 'اليوم', 'Weekday', FieldType.weekday),
    FieldDef('start', 'من (HH:mm)', 'From (HH:mm)', FieldType.time),
    FieldDef('end', 'إلى (HH:mm)', 'To (HH:mm)', FieldType.time),
    FieldDef('hallAr', 'القاعة (عربي)', 'Hall (Arabic)', FieldType.text),
    FieldDef('hallEn', 'القاعة (إنجليزي)', 'Hall (English)', FieldType.text),
    FieldDef('facebookUrl', 'رابط فيسبوك', 'Facebook URL', FieldType.url),
    FieldDef('whatsappUrl', 'رابط واتساب', 'WhatsApp URL', FieldType.url),
    FieldDef('notes', 'ملاحظات', 'Notes', FieldType.text),
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'nameAr',
    'stage'
  ], icon: 'meetings', publicPath: '/church-education'),
  CollectionDef('clinics', 'العيادات', 'Clinics', [
    FieldDef('specialty', 'مفتاح التخصص (إنجليزي، مثل dental)', 'Specialty key (e.g. dental)', FieldType.text,
        required: true, maxLength: 40),
    FieldDef('specialtyAr', 'التخصص (عربي)', 'Specialty (Arabic)', FieldType.text, required: true),
    FieldDef('specialtyEn', 'التخصص (إنجليزي)', 'Specialty (English)', FieldType.text),
    FieldDef('doctorName', 'اسم الطبيب', 'Doctor name', FieldType.text, required: true),
    FieldDef('degreeAr', 'الدرجة العلمية (عربي)', 'Degree (Arabic)', FieldType.text),
    FieldDef('degreeEn', 'الدرجة العلمية (إنجليزي)', 'Degree (English)', FieldType.text),
    FieldDef('days', 'أيام العيادة', 'Clinic days', FieldType.weekdays),
    FieldDef('start', 'من (HH:mm)', 'From (HH:mm)', FieldType.time),
    FieldDef('end', 'إلى (HH:mm)', 'To (HH:mm)', FieldType.time),
    FieldDef('bookingPhone', 'تليفون الحجز', 'Booking phone', FieldType.phone),
    FieldDef('whatsapp', 'واتساب', 'WhatsApp', FieldType.phone),
    FieldDef('active', 'مُفعّلة', 'Active', FieldType.boolean, missingBool: true), // Clinic.fromMap: absent = active
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'doctorName',
    'specialtyAr'
  ], orderable: true, icon: 'clinics', publicPath: '/clinics'),
  CollectionDef('facilities', 'الخدمات العامة', 'Public services', [
    FieldDef('type', 'النوع', 'Type', FieldType.choice,
        options: ['service', 'nursery', 'employment', 'halls', 'other'], defaultOption: 'other'),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('descAr', 'الوصف (عربي)', 'Description (Arabic)', FieldType.multiline, maxLength: 2000),
    FieldDef('descEn', 'الوصف (إنجليزي)', 'Description (English)', FieldType.multiline, maxLength: 2000),
    FieldDef('phone', 'تليفون', 'Phone', FieldType.phone),
    FieldDef('hoursAr', 'المواعيد (عربي)', 'Hours (Arabic)', FieldType.text),
    FieldDef('hoursEn', 'المواعيد (إنجليزي)', 'Hours (English)', FieldType.text),
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'nameAr',
    'nameEn'
  ], orderable: true, icon: 'services', publicPath: '/public-services'),
  CollectionDef('activities', 'الأنشطة والكورالات', 'Activities', [
    FieldDef('category', 'التصنيف', 'Category', FieldType.choice,
        options: ['service', 'choir', 'hymns', 'youth', 'servants', 'media', 'drama', 'scouts', 'deacons', 'bible', //
          'summer', 'sports', 'exhibitions'],
        defaultOption: 'service'),
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('descAr', 'الوصف (عربي)', 'Description (Arabic)', FieldType.multiline, maxLength: 2000),
    FieldDef('descEn', 'الوصف (إنجليزي)', 'Description (English)', FieldType.multiline, maxLength: 2000),
    FieldDef('scheduleAr', 'المواعيد (عربي)', 'Schedule (Arabic)', FieldType.text),
    FieldDef('scheduleEn', 'المواعيد (إنجليزي)', 'Schedule (English)', FieldType.text),
    FieldDef('ageRange', 'الأعمار', 'Ages', FieldType.text, maxLength: 60),
    FieldDef('contactPhone', 'تليفون التواصل', 'Contact phone', FieldType.phone),
    FieldDef('link', 'رابط الصفحة (فيسبوك/يوتيوب…)', 'Page link (Facebook/YouTube…)', FieldType.url),
    _imageField,
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'titleAr',
    'titleEn'
  ], orderable: true, icon: 'activities', publicPath: '/church-activities'),
  CollectionDef('priests', 'الآباء الكهنة', 'Priests', _priestFields, ['name', 'nameEn'],
      filter: MapEntry('status', 'serving'), orderable: true, icon: 'priests', publicPath: '/about'),
  CollectionDef('priests', 'الآباء المتنيحون', 'Departed fathers', _priestFields, ['name', 'nameEn'],
      id: 'departedPriests',
      filter: MapEntry('status', 'departed'),
      newDefaults: {'status': 'departed'},
      orderable: true,
      icon: 'departed',
      publicPath: '/about'),
  CollectionDef('saints', 'شفعاء الكنيسة', 'Patron saints', [
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('bioAr', 'السيرة (عربي)', 'Life (Arabic)', FieldType.multiline),
    FieldDef('bioEn', 'السيرة (إنجليزي)', 'Life (English)', FieldType.multiline),
    FieldDef('feastCopticAr', 'العيد بالتقويم القبطي (عربي)', 'Coptic feast (Arabic)', FieldType.text),
    FieldDef('feastCopticEn', 'العيد بالتقويم القبطي (إنجليزي)', 'Coptic feast (English)', FieldType.text),
    FieldDef('feastGregorianAr', 'العيد بالتقويم الميلادي (عربي)', 'Gregorian feast (Arabic)', FieldType.text),
    FieldDef('feastGregorian', 'العيد بالتقويم الميلادي (إنجليزي)', 'Gregorian feast (English)', FieldType.text),
    _imageField,
    _orderField,
    _visibleField,
  ], [
    'nameAr',
    'nameEn'
  ], orderable: true, icon: 'saints', publicPath: '/about'),
  CollectionDef('milestones', 'محطات تاريخية', 'Milestones', [
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('descAr', 'الوصف (عربي)', 'Description (Arabic)', FieldType.multiline, maxLength: 2000),
    FieldDef('descEn', 'الوصف (إنجليزي)', 'Description (English)', FieldType.multiline, maxLength: 2000),
    FieldDef('year', 'السنة', 'Year', FieldType.integer, min: 1, max: 2200),
    FieldDef('icon', 'الأيقونة', 'Icon', FieldType.choice,
        options: ['church', 'people', 'altar', 'pope', 'star'], defaultOption: 'star'),
    _imageField,
    _orderField,
    _visibleField,
  ], [
    'titleAr',
    'titleEn'
  ], orderable: true, icon: 'milestones', publicPath: '/'),
];

/// settings/church: identity, contacts, socials, history.
const churchInfoDoc = DocDef('settings/church', 'بيانات الكنيسة', 'Church info', [
  FieldDef('nameAr', 'اسم الكنيسة (عربي)', 'Church name (Arabic)', FieldType.text, required: true),
  FieldDef('nameEn', 'اسم الكنيسة (إنجليزي)', 'Church name (English)', FieldType.text, required: true),
  FieldDef('bishopAr', 'الأسقف (عربي)', 'Bishop (Arabic)', FieldType.text),
  FieldDef('bishopEn', 'الأسقف (إنجليزي)', 'Bishop (English)', FieldType.text),
  FieldDef('addressAr', 'العنوان (عربي)', 'Address (Arabic)', FieldType.text, required: true),
  FieldDef('addressEn', 'العنوان (إنجليزي)', 'Address (English)', FieldType.text),
  FieldDef('transportAr', 'المواصلات (عربي)', 'Getting here (Arabic)', FieldType.multiline, maxLength: 2000),
  FieldDef('transportEn', 'المواصلات (إنجليزي)', 'Getting here (English)', FieldType.multiline, maxLength: 2000),
  FieldDef('lat', 'خط العرض', 'Latitude', FieldType.decimal, min: -90, max: 90),
  FieldDef('lng', 'خط الطول', 'Longitude', FieldType.decimal, min: -180, max: 180),
  FieldDef('mapsQuery', 'بحث الخريطة (مثل 31.26,30.01)', 'Map query (e.g. 31.26,30.01)', FieldType.text,
      maxLength: 200),
  FieldDef('mapsUrl', 'رابط خرائط جوجل', 'Google Maps link', FieldType.url),
  FieldDef('phones', 'أرقام التليفون', 'Phone numbers', FieldType.objectList, subFields: [
    FieldDef('labelAr', 'الوصف (عربي)', 'Label (Arabic)', FieldType.text, required: true, maxLength: 80),
    FieldDef('labelEn', 'الوصف (إنجليزي)', 'Label (English)', FieldType.text, maxLength: 80),
    FieldDef('number', 'الرقم', 'Number', FieldType.phone, required: true),
    FieldDef('isMobile', 'موبايل (واتساب)', 'Mobile (WhatsApp)', FieldType.boolean, newBool: false),
  ]),
  FieldDef('whatsapp', 'رقم واتساب', 'WhatsApp number', FieldType.phone),
  FieldDef('whatsappChannel', 'قناة واتساب', 'WhatsApp channel', FieldType.url),
  FieldDef('facebook', 'فيسبوك', 'Facebook', FieldType.url),
  FieldDef('youtube', 'يوتيوب', 'YouTube', FieldType.url),
  FieldDef('instagram', 'إنستغرام', 'Instagram', FieldType.url),
  FieldDef('verseAr', 'الآية (عربي)', 'Verse (Arabic)', FieldType.text),
  FieldDef('verseEn', 'الآية (إنجليزي)', 'Verse (English)', FieldType.text),
  FieldDef('verseRefAr', 'الشاهد (عربي)', 'Verse reference (Arabic)', FieldType.text, maxLength: 60),
  FieldDef('verseRef', 'الشاهد (إنجليزي)', 'Verse reference (English)', FieldType.text, maxLength: 60),
  FieldDef('heroImageUrl', 'صورة الواجهة (رابط)', 'Hero image URL', FieldType.url),
  FieldDef('historyAr', 'التاريخ (عربي)', 'History (Arabic)', FieldType.multiline, maxLength: 8000),
  FieldDef('historyEn', 'التاريخ (إنجليزي)', 'History (English)', FieldType.multiline, maxLength: 8000),
  FieldDef('altars', 'المذابح', 'Altars', FieldType.objectList, subFields: [
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true, maxLength: 120),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text, maxLength: 120),
    FieldDef('kind', 'النوع', 'Kind', FieldType.choice, options: ['main', 'second', 'annex'], defaultOption: 'annex'),
  ]),
  FieldDef('assistantEnabled', 'تفعيل المساعد الذكي (يتطلب App Check)', 'Enable the AI assistant (needs App Check)',
      FieldType.boolean,
      newBool: false),
  FieldDef('sample', 'بيانات غير مؤكدة', 'Unconfirmed data', FieldType.boolean, newBool: false),
]);

CollectionDef? collectionById(String id) {
  for (final c in adminCollections) {
    if (c.id == id) return c;
  }
  return null;
}
