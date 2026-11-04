/// Field schemas for the admin editors (collections + the church-info doc).
library;

import '../../domain/assistant_settings.dart';
import '../../domain/custom_content.dart';
import '../../domain/image_style.dart';

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

  /// Ordered list of `image` maps (an item's detail-page `gallery`), at most
  /// [FieldDef.maxRows] photos.
  imageList,
}

/// Where a field sits in the editor: [basic] is always open at the top; the
/// detail-page groups are collapsible cards below it.
enum FieldGroup { basic, details, media, contacts }

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

  /// [FieldType.objectList]: each row needs at least one of these sub-field
  /// keys non-empty (e.g. a title in Arabic OR English; firestore.rules
  /// validExtraField). The error shows on the first key's field.
  final List<String> rowRequireAnyOf;

  /// Optional helper text under the field.
  final String hintAr, hintEn;

  /// Max rows for [FieldType.objectList] / photos for [FieldType.imageList]
  /// (matches firestore.rules).
  final int maxRows;

  /// Editor group (collapsible card) this field belongs to.
  final FieldGroup group;

  /// Text field holding a URL slug (lower-case latin, digits, hyphens; unique
  /// within its collection — ADR-027).
  final bool slug;

  /// [FieldType.objectList] sub-fields: shown only while the row's
  /// [showWhen.key] choice is one of [showWhen.value] (page block types).
  final MapEntry<String, List<String>>? showWhen;

  /// [FieldType.choice]: options loaded at run time (e.g. 'categories': the
  /// admin-defined categories), passed to the editor by the list screen.
  final String dynamicOptions;

  /// URL fields: offer a "Pick a page…" list (custom pages, categories,
  /// built-in routes) next to the field.
  final bool linkPicker;

  /// [FieldType.objectList]: each row is stored as one string, its
  /// sub-field values in order joined by U+001F (page blocks, ADR-027).
  final bool encodedRows;

  /// Text fields: the whole (trimmed) value must match this regular
  /// expression when not blank (e.g. the assistant's model name).
  final String pattern;

  /// [FieldType.objectList] of dates: row sub-field [rowNotBefore.key] (an
  /// optional end date) may not be earlier than [rowNotBefore.value] (the
  /// start date); both are YYYY-MM-DD. The error shows on the end field.
  final MapEntry<String, String>? rowNotBefore;

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
      this.rowRequireAnyOf = const [],
      this.hintAr = '',
      this.hintEn = '',
      this.maxRows = 20,
      this.group = FieldGroup.basic,
      this.slug = false,
      this.showWhen,
      this.dynamicOptions = '',
      this.linkPicker = false,
      this.encodedRows = false,
      this.pattern = '',
      this.rowNotBefore});

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

  /// Optional note shown above the list (e.g. where built-in sections are managed).
  final String noteAr, noteEn;

  const CollectionDef(this.name, this.labelAr, this.labelEn, this.fields, this.titleKeys,
      {String? id,
      this.requireAnyOf = const [],
      this.orderable = false,
      this.filter,
      this.newDefaults = const {},
      this.icon = 'list',
      this.publicPath = '/',
      this.noteAr = '',
      this.noteEn = ''})
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

/// Per-item image display override (ADR-023): avatar / card / banner;
/// empty (—) = the section default chosen in Settings → Image display.
const _imageStyleField = FieldDef('imageStyle', 'طريقة عرض الصورة (— = الافتراضي للقسم)',
    'Image display (— = section default)', FieldType.choice,
    options: ImageStyles.all, nullableChoice: true, group: FieldGroup.media);
const _imageStyleFieldFlat = FieldDef('imageStyle', 'طريقة عرض الصورة (— = الافتراضي للقسم)',
    'Image display (— = section default)', FieldType.choice,
    options: ImageStyles.all, nullableChoice: true);

/// Collections whose documents may carry an `image` (see lib/domain/media.dart).
const imageCollections = [
  'alerts', 'seasons', 'meetings', 'activities', 'clinics', 'facilities', 'priests', 'milestones', 'saints', //
  'entries', 'pages', // ADR-027
];

// ---- optional item detail page (meetings, activities, clinics, facilities,
// priests, milestones, saints; see ItemDetails in lib/domain/models.dart and
// validDetailCommon in firestore.rules). Every field is optional and starts
// at the reader's default. The page itself is on by default (PR #14).

const _detailsGroup = [
  // Opt-out since PR #14: every item has a detail page unless switched off.
  FieldDef('detailsEnabled', 'إظهار صفحة التفاصيل', 'Show the detail page', FieldType.boolean,
      missingBool: true,
      newBool: true,
      group: FieldGroup.details,
      hintAr: 'مفعّلة تلقائيًا: الضغط على البطاقة يفتح صفحة كاملة بكل بيانات العنصر وما تضيفه هنا. أوقفها لإخفاء الصفحة ورابط «التفاصيل».',
      hintEn: 'On by default: tapping the card opens a full page with all of the item\'s info plus what you add here. '
          'Turn it off to hide the page and the "Details" link.'),
  FieldDef('detailsAr', 'التفاصيل (عربي)', 'Details (Arabic)', FieldType.multiline,
      maxLength: 10000, group: FieldGroup.details),
  FieldDef('detailsEn', 'التفاصيل (إنجليزي)', 'Details (English)', FieldType.multiline,
      maxLength: 10000, group: FieldGroup.details),
  FieldDef('extraFields', 'حقول إضافية (عنوان: قيمة)', 'Extra fields (title: value)', FieldType.objectList,
      maxRows: 15,
      group: FieldGroup.details,
      // A row needs a title in either language (validExtraField in firestore.rules).
      rowRequireAnyOf: ['titleAr', 'titleEn'],
      subFields: [
        FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, maxLength: 150),
        FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text, maxLength: 150),
        FieldDef('valueAr', 'القيمة (عربي)', 'Value (Arabic)', FieldType.multiline, maxLength: 2000),
        FieldDef('valueEn', 'القيمة (إنجليزي)', 'Value (English)', FieldType.multiline, maxLength: 2000),
      ]),
];

const _showDetailImagesField = FieldDef(
    'showDetailImages', 'عرض الصور في صفحة التفاصيل', 'Show photos on the detail page', FieldType.boolean,
    missingBool: true, newBool: true, group: FieldGroup.media);

const _galleryField = FieldDef('gallery', 'معرض الصور (حتى 8)', 'Photo gallery (up to 8)', FieldType.imageList,
    maxRows: 8, group: FieldGroup.media);

const _mediaGroup = [
  FieldDef('image', 'الصورة (اختياري)', 'Image (optional)', FieldType.image, group: FieldGroup.media),
  _imageStyleField,
  _showDetailImagesField,
  _galleryField,
];

/// BR-11 / FR-E-04: Sunday-school meetings never show identifiable children.
const _br11Ar = 'خصوصية الأطفال: يُحظر رفع صور واضحة للأطفال أو القُصَّر في مدارس الأحد';
const _br11En = "Children's privacy: never upload identifiable photos of minors in Sunday School";

const _meetingMediaGroup = [
  FieldDef('image', 'الصورة (اختياري)', 'Image (optional)', FieldType.image,
      group: FieldGroup.media, hintAr: _br11Ar, hintEn: _br11En),
  _imageStyleField,
  _showDetailImagesField,
  FieldDef('gallery', 'معرض الصور (حتى 8)', 'Photo gallery (up to 8)', FieldType.imageList,
      maxRows: 8, group: FieldGroup.media, hintAr: _br11Ar, hintEn: _br11En),
];

const _contactSwitches = [
  FieldDef('showContacts', 'عرض أرقام التواصل', 'Show contact numbers', FieldType.boolean,
      missingBool: true, newBool: true, group: FieldGroup.contacts),
  FieldDef('showSocials', 'عرض روابط التواصل الاجتماعي', 'Show social links', FieldType.boolean,
      missingBool: true, newBool: true, group: FieldGroup.contacts),
];
const _contactPhoneField =
    FieldDef('contactPhone', 'تليفون التواصل', 'Contact phone', FieldType.phone, group: FieldGroup.contacts);
const _whatsappField = FieldDef('whatsapp', 'واتساب', 'WhatsApp', FieldType.phone, group: FieldGroup.contacts);
const _whatsappUrlField = FieldDef('whatsappUrl', 'رابط واتساب (مجموعة/قناة)', 'WhatsApp group / channel link',
    FieldType.url, group: FieldGroup.contacts);
const _facebookUrlField =
    FieldDef('facebookUrl', 'رابط فيسبوك', 'Facebook URL', FieldType.url, group: FieldGroup.contacts);
const _youtubeUrlField = FieldDef('youtubeUrl', 'رابط يوتيوب', 'YouTube URL', FieldType.url, group: FieldGroup.contacts);
const _instagramUrlField =
    FieldDef('instagramUrl', 'رابط إنستغرام', 'Instagram URL', FieldType.url, group: FieldGroup.contacts);
const _externalUrlField = FieldDef('externalUrl', 'رابط خارجي / تسجيل', 'External / registration link', FieldType.url,
    group: FieldGroup.contacts);
const _contactTail = [
  FieldDef('externalLabelAr', 'نص زر الرابط (عربي)', 'Link button text (Arabic)', FieldType.text,
      maxLength: 80, group: FieldGroup.contacts),
  FieldDef('externalLabelEn', 'نص زر الرابط (إنجليزي)', 'Link button text (English)', FieldType.text,
      maxLength: 80, group: FieldGroup.contacts),
  FieldDef('contactNoteAr', 'طريقة التواصل / التسجيل (عربي)', 'How to contact / register (Arabic)', FieldType.multiline,
      maxLength: 500, group: FieldGroup.contacts),
  FieldDef('contactNoteEn', 'طريقة التواصل / التسجيل (إنجليزي)', 'How to contact / register (English)',
      FieldType.multiline,
      maxLength: 500, group: FieldGroup.contacts),
];

/// Contacts for priests, milestones and saints (no phone / link of their own).
const _plainContactsGroup = [
  ..._contactSwitches,
  _contactPhoneField,
  _whatsappField,
  _whatsappUrlField,
  _facebookUrlField,
  _youtubeUrlField,
  _instagramUrlField,
  _externalUrlField,
  ..._contactTail,
];

const _priestFields = [
  FieldDef('name', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
  FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
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
  ..._detailsGroup,
  ..._mediaGroup, // image replaces the legacy photoUrl text field (still read as a fallback)
  ..._plainContactsGroup,
];

const adminCollections = <CollectionDef>[
  CollectionDef('alerts', 'التنويهات', 'Alerts', [
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('bodyAr', 'النص (عربي)', 'Body (Arabic)', FieldType.multiline, maxLength: 1000),
    FieldDef('bodyEn', 'النص (إنجليزي)', 'Body (English)', FieldType.multiline, maxLength: 1000),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
    FieldDef('startsAt', 'يبدأ', 'Starts', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي', 'Ends', FieldType.dateTime),
    FieldDef('priority', 'الأولوية (الأعلى يظهر أولًا)', 'Priority (higher shows first)', FieldType.integer,
        min: 0, max: 1000),
    FieldDef('link', 'رابط «اعرف المزيد» (صفحة، قسم أو رابط خارجي)', '"Learn more" link (a page, a section or an external URL)',
        FieldType.url,
        allowPath: true,
        linkPicker: true,
        hintAr: 'اختر صفحة مخصصة (مثل صفحة التبرعات) أو قسمًا من «اختيار صفحة…»، أو اكتب رابطًا خارجيًا يبدأ بـ https://',
        hintEn: 'Pick a custom page (e.g. a donations page) or a section from "Pick a page…", or type an external https:// link'),
    _imageField,
    _imageStyleFieldFlat,
    _visibleField,
  ], [
    'titleAr',
    'titleEn'
  ], icon: 'alerts', publicPath: '/'),
  CollectionDef('seasons', 'المواسم', 'Seasons', [
    FieldDef('key', 'نوع الموسم', 'Season key', FieldType.choice, required: true, options: seasonKeys),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('startsAt', 'يبدأ', 'Starts', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي', 'Ends', FieldType.dateTime),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
    FieldDef(
      'replacesRegular',
      'يستبدل الجدول العادي (أوقفها للنهضات المسائية)',
      'Replaces regular schedule (off for evening revivals)',
      FieldType.boolean,
      missingBool: true,
    ),
    _imageField,
    _imageStyleFieldFlat,
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
    FieldDef('notes', 'ملاحظات', 'Notes', FieldType.text),
    _orderField,
    _visibleField,
    _sampleField,
    ..._detailsGroup,
    ..._meetingMediaGroup,
    ..._contactSwitches,
    _contactPhoneField,
    _whatsappField,
    FieldDef('whatsappUrl', 'رابط واتساب', 'WhatsApp URL', FieldType.url, group: FieldGroup.contacts),
    FieldDef('facebookUrl', 'رابط فيسبوك', 'Facebook URL', FieldType.url, group: FieldGroup.contacts),
    _youtubeUrlField,
    _instagramUrlField,
    _externalUrlField,
    ..._contactTail,
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
    FieldDef('active', 'مُفعّلة', 'Active', FieldType.boolean, missingBool: true), // Clinic.fromMap: absent = active
    _orderField,
    _visibleField,
    _sampleField,
    ..._detailsGroup,
    ..._mediaGroup,
    ..._contactSwitches,
    FieldDef('bookingPhone', 'تليفون الحجز', 'Booking phone', FieldType.phone, group: FieldGroup.contacts),
    _whatsappField,
    _whatsappUrlField,
    _facebookUrlField,
    _youtubeUrlField,
    _instagramUrlField,
    _externalUrlField,
    ..._contactTail,
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
    FieldDef('hoursAr', 'المواعيد (عربي)', 'Hours (Arabic)', FieldType.text),
    FieldDef('hoursEn', 'المواعيد (إنجليزي)', 'Hours (English)', FieldType.text),
    _orderField,
    _visibleField,
    _sampleField,
    ..._detailsGroup,
    ..._mediaGroup,
    ..._contactSwitches,
    FieldDef('phone', 'تليفون', 'Phone', FieldType.phone, group: FieldGroup.contacts),
    _whatsappField,
    _whatsappUrlField,
    _facebookUrlField,
    _youtubeUrlField,
    _instagramUrlField,
    _externalUrlField,
    ..._contactTail,
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
    _orderField,
    _visibleField,
    _sampleField,
    ..._detailsGroup,
    ..._mediaGroup,
    ..._contactSwitches,
    _contactPhoneField,
    _whatsappField,
    _whatsappUrlField,
    _facebookUrlField,
    _youtubeUrlField,
    _instagramUrlField,
    FieldDef('link', 'رابط الصفحة (فيسبوك/يوتيوب…)', 'Page link (Facebook/YouTube…)', FieldType.url,
        group: FieldGroup.contacts),
    ..._contactTail,
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
    _orderField,
    _visibleField,
    ..._detailsGroup,
    ..._mediaGroup,
    ..._plainContactsGroup,
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
    _orderField,
    _visibleField,
    ..._detailsGroup,
    ..._mediaGroup,
    ..._plainContactsGroup,
  ], [
    'titleAr',
    'titleEn'
  ], orderable: true, icon: 'milestones', publicPath: '/'),
  CollectionDef('categories', 'الأقسام المخصصة', 'Custom sections', [
    FieldDef('nameAr', 'اسم القسم (عربي)', 'Section name (Arabic)', FieldType.text, required: true, maxLength: 120),
    FieldDef('nameEn', 'اسم القسم (إنجليزي)', 'Section name (English)', FieldType.text, maxLength: 120),
    FieldDef('slug', 'رابط الصفحة (حروف إنجليزية صغيرة وأرقام و-)', 'Page address (lower-case latin, digits, -)',
        FieldType.text,
        required: true,
        maxLength: slugMaxLength,
        slug: true,
        hintAr: 'تظهر الصفحة على /section/<الرابط> مثل /section/youth-trips',
        hintEn: 'The page lives at /section/<address>, e.g. /section/youth-trips'),
    FieldDef('introAr', 'مقدمة (عربي)', 'Intro (Arabic)', FieldType.multiline, maxLength: 1500),
    FieldDef('introEn', 'مقدمة (إنجليزي)', 'Intro (English)', FieldType.multiline, maxLength: 1500),
    FieldDef('icon', 'الأيقونة', 'Icon', FieldType.choice, options: CategoryIcons.all, defaultOption: 'star'),
    FieldDef('imageStyle', 'طريقة عرض صور العناصر', 'Image display of its items', FieldType.choice,
        options: ImageStyles.all, nullableChoice: true),
    FieldDef('showInNav', 'يظهر في القائمة (خدمات الكنيسة)', 'Shown in the menu (Church services)', FieldType.boolean,
        missingBool: true, newBool: true),
    _orderField,
    _visibleField,
  ], [
    'nameAr',
    'nameEn'
  ],
      orderable: true,
      icon: 'categories',
      publicPath: '/',
      noteAr: 'الأقسام الأساسية (العيادات، الاجتماعات، الأنشطة…) تُخفى أو تُظهر من «الأقسام والصفحة الرئيسية» ويُعاد تسميتها من «عناوين الصفحات» هناك. '
          'حذف قسم مخصص يُخفي عناصره ولا يحذفها.',
      noteEn: 'Built-in sections (clinics, meetings, activities…) are switched on/off in "Sections & home page" and renamed in its '
          '"Page headers". Deleting a custom section hides its items, never deletes them.'),
  CollectionDef('entries', 'عناصر الأقسام', 'Section items', [
    FieldDef('categoryId', 'القسم', 'Section', FieldType.choice, required: true, dynamicOptions: 'categories'),
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('descAr', 'الوصف (عربي)', 'Description (Arabic)', FieldType.multiline, maxLength: 2000),
    FieldDef('descEn', 'الوصف (إنجليزي)', 'Description (English)', FieldType.multiline, maxLength: 2000),
    FieldDef('contactPhone', 'تليفون التواصل', 'Contact phone', FieldType.phone),
    FieldDef('externalUrl', 'رابط (صفحة أو رابط خارجي)', 'Link (a page or an external URL)', FieldType.url,
        allowPath: true, linkPicker: true),
    FieldDef('externalLabelAr', 'نص زر الرابط (عربي)', 'Link button text (Arabic)', FieldType.text, maxLength: 80),
    FieldDef('externalLabelEn', 'نص زر الرابط (إنجليزي)', 'Link button text (English)', FieldType.text, maxLength: 80),
    _imageField,
    _imageStyleFieldFlat,
    _orderField,
    _visibleField,
    _sampleField,
  ], [
    'titleAr',
    'titleEn'
  ], orderable: true, icon: 'entries', publicPath: '/'),
  CollectionDef('pages', 'الصفحات المخصصة', 'Custom pages', [
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true, maxLength: 200),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text, maxLength: 200),
    FieldDef('slug', 'رابط الصفحة (حروف إنجليزية صغيرة وأرقام و-)', 'Page address (lower-case latin, digits, -)',
        FieldType.text,
        required: true,
        maxLength: slugMaxLength,
        slug: true,
        hintAr: 'تظهر الصفحة على /page/<الرابط> مثل /page/new-building-donations',
        hintEn: 'The page lives at /page/<address>, e.g. /page/new-building-donations'),
    FieldDef('subtitleAr', 'العنوان الفرعي (عربي)', 'Subtitle (Arabic)', FieldType.text),
    FieldDef('subtitleEn', 'العنوان الفرعي (إنجليزي)', 'Subtitle (English)', FieldType.text),
    FieldDef('image', 'صورة الواجهة (اختياري)', 'Hero image (optional)', FieldType.image),
    FieldDef('blocks', 'محتوى الصفحة (حتى 20 فقرة)', 'Page content (up to 20 blocks)', FieldType.objectList,
        maxRows: pageMaxBlocks,
        encodedRows: true,
        subFields: [
          FieldDef('type', 'نوع الفقرة', 'Block type', FieldType.choice,
              options: BlockTypes.all, defaultOption: BlockTypes.paragraph),
          FieldDef('textAr', 'النص (عربي)', 'Text (Arabic)', FieldType.multiline,
              maxLength: blockTextMax,
              showWhen: MapEntry('type', [BlockTypes.heading, BlockTypes.paragraph, BlockTypes.image, BlockTypes.button,
                BlockTypes.link, BlockTypes.donation]),
              hintAr: 'للصورة: وصف/تعليق. للزر والرابط: النص الظاهر. للتبرع: ملاحظات.',
              hintEn: 'Image: caption. Button / link: its text. Donation: notes.'),
          FieldDef('textEn', 'النص (إنجليزي)', 'Text (English)', FieldType.multiline,
              maxLength: blockTextMax,
              showWhen: MapEntry('type', [BlockTypes.heading, BlockTypes.paragraph, BlockTypes.image, BlockTypes.button,
                BlockTypes.link, BlockTypes.donation])),
          FieldDef('url', 'الرابط', 'Link', FieldType.url,
              allowPath: true,
              linkPicker: true,
              showWhen: MapEntry('type', [BlockTypes.image, BlockTypes.button, BlockTypes.link]),
              hintAr: 'للصورة: رابط https للصورة. للزر والرابط: صفحة داخلية أو رابط خارجي.',
              hintEn: 'Image: the picture\'s https link. Button / link: an in-app page or an external URL.'),
          FieldDef('account', 'رقم الحساب البنكي (والبنك)', 'Bank account (and bank)', FieldType.text,
              maxLength: blockAccountMax, showWhen: MapEntry('type', [BlockTypes.donation])),
          FieldDef('instapay', 'عنوان/رقم إنستاباي', 'InstaPay address / number', FieldType.text,
              maxLength: blockInstapayMax, showWhen: MapEntry('type', [BlockTypes.donation])),
          FieldDef('wallet', 'رقم المحفظة', 'Wallet number', FieldType.text,
              maxLength: blockWalletMax, showWhen: MapEntry('type', [BlockTypes.donation])),
        ]),
    FieldDef('showInNav', 'إظهار في القائمة', 'Show in the menu', FieldType.boolean,
        missingBool: false,
        newBool: false,
        hintAr: 'غير ظاهرة في القائمة افتراضيًا؛ اربطها من تنويه («اعرف المزيد») أو من زر.',
        hintEn: 'Not in the menu by default; link it from a notice ("Learn more") or a button.'),
    _orderField,
    _visibleField,
  ], [
    'titleAr',
    'titleEn'
  ], orderable: true, icon: 'pages', publicPath: '/'),
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

/// settings/assistant (ADR-029): model, persona, topics, refusal / welcome
/// texts, suggestions and the client-side limits. Blank = code default
/// (AssistantSettings). On / off stays with the "Ask the church" section
/// switch and Church info → "Enable the AI assistant".
const assistantSettingsDoc = DocDef('settings/assistant', 'المساعد الذكي', 'AI assistant', [
  FieldDef('model', 'النموذج (اتركه فارغًا للافتراضي)', 'Model (blank = default)', FieldType.text,
      maxLength: AssistantLimits.modelMax,
      pattern: r'gemini-[a-z0-9][a-z0-9.\-]{0,52}',
      hintAr: 'اسم نموذج Gemini مدعوم في Firebase AI Logic، مثل gemini-3.1-flash-lite (الافتراضي، مجاني). إذا رُفض الاسم يُستخدم الافتراضي تلقائيًا.',
      hintEn: 'A Gemini model id supported by Firebase AI Logic, e.g. gemini-3.1-flash-lite (the default, free tier). If it is rejected, the default is used automatically.'),
  FieldDef('instructions', 'تعليمات الشخصية والأسلوب', 'Persona & style instructions', FieldType.multiline,
      maxLength: AssistantLimits.instructionsMax,
      hintAr: 'اتركه فارغًا للنص الافتراضي. قواعد النطاق وعدم اختلاق المواعيد والأرقام تُضاف دائمًا ولا يمكن حذفها.',
      hintEn: 'Blank = the default text. The scope rules and "never invent times or numbers" are always added and cannot be removed.'),
  FieldDef('topics', 'الموضوعات المسموح بها (موضوع في كل سطر)', 'Allowed topics (one per line)', FieldType.multiline,
      maxLength: AssistantLimits.topicsMax,
      hintAr: 'اتركه فارغًا للقائمة الافتراضية (المواعيد، الاجتماعات، العيادات، الأنشطة، الآباء، القديسون، التواصل، الحجز، التبرعات، الأقسام والصفحات المخصصة).',
      hintEn: 'Blank = the default list (times, meetings, clinics, activities, priests, saints, contact, bookings, donations, custom sections and pages).'),
  FieldDef('refusalAr', 'رسالة الاعتذار عن الأسئلة الأخرى (عربي)', 'Refusal message (Arabic)', FieldType.multiline,
      maxLength: AssistantLimits.textMax),
  FieldDef('refusalEn', 'رسالة الاعتذار عن الأسئلة الأخرى (إنجليزي)', 'Refusal message (English)', FieldType.multiline,
      maxLength: AssistantLimits.textMax),
  FieldDef('welcomeAr', 'رسالة الترحيب (عربي)', 'Welcome text (Arabic)', FieldType.multiline,
      maxLength: AssistantLimits.textMax),
  FieldDef('welcomeEn', 'رسالة الترحيب (إنجليزي)', 'Welcome text (English)', FieldType.multiline,
      maxLength: AssistantLimits.textMax),
  FieldDef('showSuggestions', 'إظهار الأسئلة المقترحة', 'Show suggested questions', FieldType.boolean,
      newBool: false,
      hintAr: 'مغلق افتراضيًا. عند التفعيل تظهر الأسئلة المكتوبة أدناه فقط (لا توجد أسئلة افتراضية).',
      hintEn: 'Off by default. When on, only the questions written below are shown (there are no built-in ones).'),
  FieldDef('suggestionsAr', 'أسئلة مقترحة (عربي، سؤال في كل سطر، حتى 3)', 'Suggested questions (Arabic, one per line, up to 3)',
      FieldType.multiline,
      maxLength: AssistantLimits.suggestionsMax),
  FieldDef('suggestionsEn', 'أسئلة مقترحة (إنجليزي، سؤال في كل سطر، حتى 3)', 'Suggested questions (English, one per line, up to 3)',
      FieldType.multiline,
      maxLength: AssistantLimits.suggestionsMax),
  FieldDef('sourceDomains', 'مصادر الأسئلة الدينية (نطاقات)', 'Sources for faith questions (domains)', FieldType.text,
      maxLength: AssistantLimits.sourceDomainsMax,
      pattern: r'[a-z0-9.\-]+([ ,]+[a-z0-9.\-]+)*',
      hintAr: 'الأسئلة الدينية غير الموجودة في بيانات الموقع لا يُجاب عنها من معرفة عامة؛ يظهر رابط بحث في هذه المواقع فقط وصفحة التواصل. افصل بفاصلة. الافتراضي: st-takla.org',
      hintEn: 'Faith questions not in the site data are never answered from general knowledge; visitors get a search of these sites only plus the contact page. Comma separated. Default: st-takla.org'),
  FieldDef('faithReplyAr', 'رد الأسئلة الدينية غير الموجودة في البيانات (عربي)', 'Reply for faith questions not in the data (Arabic)',
      FieldType.multiline,
      maxLength: AssistantLimits.faithReplyMax,
      hintAr: 'يظهر قبل رابط البحث ورابط صفحة التواصل. اتركه فارغًا للنص الافتراضي: ${AssistantSettings.defaultFaithReplyAr}',
      hintEn: 'Shown before the search and contact links. Blank = default (Arabic).'),
  FieldDef('faithReplyEn', 'رد الأسئلة الدينية غير الموجودة في البيانات (إنجليزي)', 'Reply for faith questions not in the data (English)',
      FieldType.multiline,
      maxLength: AssistantLimits.faithReplyMax,
      hintAr: 'اتركه فارغًا للنص الافتراضي (إنجليزي).',
      hintEn: 'Shown before the search and contact links. Blank = default: ${AssistantSettings.defaultFaithReplyEn}'),
  FieldDef('mentionUnconfirmed', 'ذكر علامة "غير مؤكد"', 'Mention unconfirmed flags', FieldType.boolean,
      newBool: false,
      hintAr: 'مغلق افتراضيًا: يجيب المساعد من البيانات مباشرة دون تنبيه. عند التفعيل يذكر مرة واحدة باختصار أن البند غير مؤكد فقط إذا سُئل عنه.',
      hintEn: 'Off by default: answers straight from the data with no disclaimer. On: says once, briefly, that an item is unconfirmed, only when asked about that item.'),
  FieldDef('maxChars', 'أقصى طول للسؤال (حروف)', 'Max question length (characters)', FieldType.integer,
      min: AssistantLimits.maxCharsMin, max: AssistantLimits.maxCharsMax,
      hintAr: 'الافتراضي ${AssistantLimits.maxCharsDefault}', hintEn: 'Default ${AssistantLimits.maxCharsDefault}'),
  FieldDef('perMinute', 'أقصى عدد أسئلة في الدقيقة', 'Max questions per minute', FieldType.integer,
      min: AssistantLimits.perMinuteMin, max: AssistantLimits.perMinuteMax,
      hintAr: 'الافتراضي ${AssistantLimits.perMinuteDefault}', hintEn: 'Default ${AssistantLimits.perMinuteDefault}'),
  FieldDef('perDay', 'أقصى عدد أسئلة لكل جهاز في اليوم', 'Max questions per device per day', FieldType.integer,
      min: AssistantLimits.perDayMin, max: AssistantLimits.perDayMax,
      hintAr: 'الافتراضي ${AssistantLimits.perDayDefault}، يتجدد عند منتصف الليل (عدّاد على الجهاز؛ مسح بيانات الموقع يعيده).',
      hintEn: 'Default ${AssistantLimits.perDayDefault}, resets at midnight (an on-device counter; clearing site data resets it).'),
]);

CollectionDef? collectionById(String id) {
  for (final c in adminCollections) {
    if (c.id == id) return c;
  }
  return null;
}

/// /admin → "Today & live stream" (ADR-039 / ADR-040): top-level keys of
/// settings/features (no extra document or listener for visitors). The
/// generic form writes only the keys it changed, so the Sections & home page
/// editor and this screen never overwrite each other.
const todaySettingsDoc = DocDef('settings/features', 'اليوم والبث المباشر', 'Today & live stream', [
  FieldDef('copticStrip', 'شريط التاريخ القبطي', 'Coptic date strip', FieldType.choice,
      options: ['all', 'home', 'off'],
      defaultOption: 'all',
      hintAr: 'يظهر أعلى الصفحات: اليوم والشهر القبطي وسنة الشهداء (مثل «الأربعاء ٢٥ بابه ١٧٤٣ ش»). كل الصفحات، الرئيسية فقط، أو إيقاف.',
      hintEn: 'Shown at the top of the pages: the day, Coptic month and Year of the Martyrs (e.g. "Wednesday 25 Baba 1743 AM"). Every page, Home only, or off.'),
  FieldDef('dayStartMode', 'بداية اليوم الكنسي', 'Start of the liturgical day', FieldType.choice,
      options: ['fixed', 'sunset'],
      defaultOption: 'fixed',
      hintAr: 'اليوم الكنسي يبدأ مساء اليوم السابق: بعد هذا الوقت يتحول التاريخ القبطي وآية اليوم إلى اليوم التالي («ليلة الخميس»). «ساعة ثابتة» (الافتراضي ١٨:٠٠) أو «غروب الشمس» محسوبًا لموقع الكنيسة.',
      hintEn: 'The liturgical day starts the evening before: after this time the Coptic date and the verse of the day move to the next day ("Eve of Thursday"). A fixed time (default 18:00) or sunset computed for the church\'s location.'),
  FieldDef('dayStartsAt', 'الساعة الثابتة (HH:mm، فارغ = 18:00)', 'Fixed time (HH:mm, blank = 18:00)', FieldType.time,
      hintAr: 'تُستخدم مع «ساعة ثابتة». 00:00 = منتصف الليل (اليوم المدني).',
      hintEn: 'Used with "fixed time". 00:00 = midnight (the civil day).'),
  FieldDef('topEvent', 'بطاقة «حدث اليوم» في الرئيسية', 'Home "Today\'s event" card', FieldType.boolean,
      missingBool: true,
      newBool: true,
      hintAr: 'تعرض حدث الكنيسة المضاف أدناه لهذا اليوم، وإلا عيد أو تذكار اليوم.',
      hintEn: 'Shows the church event added below for the day, otherwise the day\'s feast or commemoration.'),
  FieldDef('commemoration', 'عرض عيد / تذكار اليوم تلقائيًا (القطمارس)', 'Show the day\'s feast / commemoration automatically (Katameros)',
      FieldType.boolean,
      missingBool: true,
      newBool: true,
      hintAr: 'عند عدم وجود حدث للكنيسة: سنكسار اليوم من القطمارس (يُحدَّث مرتين يوميًا)، وبدون إنترنت قائمة الأعياد المحسوبة. أوقفه لإظهار أحداث الكنيسة فقط.',
      hintEn: 'When there is no church event: the day\'s Synaxarium from Katameros (refreshed twice a day), or the computed feast list offline. Turn off to show church events only.'),
  FieldDef('dayEvents', 'أحداث الكنيسة حسب التاريخ (حتى 20)', 'Church events by date (up to 20)', FieldType.objectList,
      maxRows: 20,
      encodedRows: true,
      rowNotBefore: MapEntry('endDate', 'date'),
      hintAr: 'مثل «الليلة الرابعة من نهضة الشفعاء» أو «بصخة ليلة الأربعاء». يتصدر الحدث الصفحة الرئيسية في يومه (وفي المساء يظهر حدث الليلة التالية بعد انتهاء حدث اليوم). احذف الأحداث القديمة لتوفير مكان.',
      hintEn: 'E.g. "Fourth night of the patrons\' revival" or "Pascha of Wednesday eve". It leads the home page on its day (in the evening, the next night\'s event after today\'s has ended). Delete old events to make room.',
      subFields: [
        FieldDef('date', 'التاريخ (YYYY-MM-DD)', 'Date (YYYY-MM-DD)', FieldType.date, required: true),
        FieldDef('endDate', 'حتى تاريخ (اختياري)', 'Until (optional)', FieldType.date),
        FieldDef('start', 'من (HH:mm)', 'From (HH:mm)', FieldType.time),
        FieldDef('end', 'إلى (HH:mm)', 'To (HH:mm)', FieldType.time),
        FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
        FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
        FieldDef('speakerAr', 'المتكلم (عربي)', 'Speaker (Arabic)', FieldType.text),
        FieldDef('speakerEn', 'المتكلم (إنجليزي)', 'Speaker (English)', FieldType.text),
        FieldDef('topicAr', 'الموضوع (عربي)', 'Topic (Arabic)', FieldType.text),
        FieldDef('topicEn', 'الموضوع (إنجليزي)', 'Topic (English)', FieldType.text),
        FieldDef('noteAr', 'ملاحظة (عربي)', 'Note (Arabic)', FieldType.multiline, maxLength: 500),
        FieldDef('noteEn', 'ملاحظة (إنجليزي)', 'Note (English)', FieldType.multiline, maxLength: 500),
        FieldDef('link', 'رابط «اعرف المزيد» (اختياري)', '"Learn more" link (optional)', FieldType.url, allowPath: true),
      ]),
  FieldDef('liveEnabled', 'شريط البث المباشر', 'Live-stream banner', FieldType.boolean,
      newBool: false,
      hintAr: 'عند التشغيل يظهر أعلى كل الصفحات «بث مباشر الآن من الكنيسة» مع نبض أحمر، والضغط يفتح الرابط.',
      hintEn: 'When on, "Live now from the church" with a pulsing red dot shows at the top of every page; a tap opens the link.'),
  FieldDef('liveUrl', 'رابط البث (يوتيوب / فيسبوك)', 'Stream link (YouTube / Facebook)', FieldType.url),
  FieldDef('liveLabelAr', 'نص الشريط (عربي، فارغ = بث مباشر الآن من الكنيسة)', 'Banner text (Arabic, blank = default)',
      FieldType.text,
      maxLength: 120),
  FieldDef('liveLabelEn', 'نص الشريط (إنجليزي)', 'Banner text (English, blank = "Live now from the church")', FieldType.text,
      maxLength: 120),
  FieldDef('liveEndsAt', 'إيقاف تلقائي (اختياري)', 'Switch off automatically at (optional)', FieldType.dateTime,
      hintAr: 'بعد هذا الوقت يختفي الشريط وحده حتى لو بقي المفتاح مفعّلًا.',
      hintEn: 'After this time the banner disappears on its own, even if the switch stays on.'),
]);
