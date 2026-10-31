/// Field schemas for the admin CRUD editors.
enum FieldType { text, multiline, integer, boolean, time, weekday, weekdays, dateTime, date, choice }

class FieldDef {
  final String key;
  final String labelAr;
  final String labelEn;
  final FieldType type;
  final bool required;
  final List<String> options; // for choice
  final bool nullableChoice;
  const FieldDef(this.key, this.labelAr, this.labelEn, this.type,
      {this.required = false, this.options = const [], this.nullableChoice = false});
}

class CollectionDef {
  final String name;
  final String labelAr;
  final String labelEn;
  final List<FieldDef> fields;
  final List<String> titleKeys;
  const CollectionDef(this.name, this.labelAr, this.labelEn, this.fields, this.titleKeys);
}

const _seasonKeys = ['holy_week', 'pascha', 'nativity', 'revival_maximus', 'revival_moses', 'summer'];

const adminCollections = <CollectionDef>[
  CollectionDef('alerts', 'التنويهات', 'Alerts', [
    FieldDef('titleAr', 'العنوان (عربي)', 'Title (Arabic)', FieldType.text, required: true),
    FieldDef('titleEn', 'العنوان (إنجليزي)', 'Title (English)', FieldType.text),
    FieldDef('bodyAr', 'النص (عربي)', 'Body (Arabic)', FieldType.multiline),
    FieldDef('bodyEn', 'النص (إنجليزي)', 'Body (English)', FieldType.multiline),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
    FieldDef('startsAt', 'يبدأ (توقيت القاهرة)', 'Starts (Cairo time)', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي (توقيت القاهرة)', 'Ends (Cairo time)', FieldType.dateTime),
    FieldDef('priority', 'الأولوية', 'Priority', FieldType.integer),
    FieldDef('link', 'رابط (مثل /mass-schedule)', 'Link (e.g. /mass-schedule)', FieldType.text),
  ], [
    'titleAr',
    'titleEn'
  ]),
  CollectionDef('seasons', 'المواسم', 'Seasons', [
    FieldDef('key', 'نوع الموسم', 'Season key', FieldType.choice, required: true, options: _seasonKeys),
    FieldDef('nameAr', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('startsAt', 'يبدأ (توقيت القاهرة)', 'Starts (Cairo time)', FieldType.dateTime),
    FieldDef('endsAt', 'ينتهي (توقيت القاهرة)', 'Ends (Cairo time)', FieldType.dateTime),
    FieldDef('active', 'مُفعّل', 'Active', FieldType.boolean),
  ], [
    'nameAr',
    'key'
  ]),
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
        options: _seasonKeys, nullableChoice: true),
    FieldDef('order', 'الترتيب', 'Order', FieldType.integer),
  ], [
    'nameAr',
    'start'
  ]),
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
    FieldDef('facebookUrl', 'رابط فيسبوك', 'Facebook URL', FieldType.text),
    FieldDef('whatsappUrl', 'رابط واتساب', 'WhatsApp URL', FieldType.text),
    FieldDef('notes', 'ملاحظات', 'Notes', FieldType.text),
  ], [
    'nameAr',
    'stage'
  ]),
  CollectionDef('clinics', 'العيادات', 'Clinics', [
    FieldDef('specialty', 'مفتاح التخصص (إنجليزي، مثل dental)', 'Specialty key (e.g. dental)', FieldType.text, required: true),
    FieldDef('specialtyAr', 'التخصص (عربي)', 'Specialty (Arabic)', FieldType.text, required: true),
    FieldDef('specialtyEn', 'التخصص (إنجليزي)', 'Specialty (English)', FieldType.text),
    FieldDef('doctorName', 'اسم الطبيب', 'Doctor name', FieldType.text, required: true),
    FieldDef('degreeAr', 'الدرجة العلمية', 'Degree', FieldType.text),
    FieldDef('days', 'أيام العيادة', 'Clinic days', FieldType.weekdays),
    FieldDef('start', 'من (HH:mm)', 'From (HH:mm)', FieldType.time),
    FieldDef('end', 'إلى (HH:mm)', 'To (HH:mm)', FieldType.time),
    FieldDef('bookingPhone', 'تليفون الحجز', 'Booking phone', FieldType.text),
    FieldDef('whatsapp', 'واتساب', 'WhatsApp', FieldType.text),
    FieldDef('active', 'مُفعّلة', 'Active', FieldType.boolean),
  ], [
    'doctorName',
    'specialtyAr'
  ]),
  CollectionDef('priests', 'الآباء الكهنة', 'Priests', [
    FieldDef('name', 'الاسم (عربي)', 'Name (Arabic)', FieldType.text, required: true),
    FieldDef('nameEn', 'الاسم (إنجليزي)', 'Name (English)', FieldType.text),
    FieldDef('photoUrl', 'رابط الصورة', 'Photo URL', FieldType.text),
    FieldDef('rank', 'الرتبة', 'Rank', FieldType.choice, options: ['hegumen', 'priest']),
    FieldDef('ordinationDate', 'تاريخ الرسامة (YYYY-MM-DD)', 'Ordination date (YYYY-MM-DD)', FieldType.text),
    FieldDef('hegumenDate', 'تاريخ القمصية (YYYY-MM-DD)', 'Hegumen date (YYYY-MM-DD)', FieldType.text),
    FieldDef('status', 'الحالة', 'Status', FieldType.choice, options: ['serving', 'departed']),
    FieldDef('bioAr', 'نبذة (عربي)', 'Bio (Arabic)', FieldType.multiline),
    FieldDef('bioEn', 'نبذة (إنجليزي)', 'Bio (English)', FieldType.multiline),
    FieldDef('order', 'الترتيب', 'Order', FieldType.integer),
  ], [
    'name'
  ]),
];
