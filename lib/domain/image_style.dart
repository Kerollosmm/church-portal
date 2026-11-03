// How an item's optional image is displayed on its card (ADR-023).
// Pure Dart: no Flutter / Firebase imports.

/// Image display styles: `avatar` (round portrait in a gold halo, for a
/// person), `card` (large cover on top of the card, whole picture visible),
/// `banner` (full-width cover, edge to edge).
class ImageStyles {
  ImageStyles._();
  static const avatar = 'avatar';
  static const card = 'card';
  static const banner = 'banner';
  static const all = [avatar, card, banner];

  /// Collections whose items may carry an `image` (and so an `imageStyle`).
  static const collections = [
    'priests', 'saints', 'activities', 'milestones', 'meetings', 'alerts', 'seasons', 'facilities', 'clinics', //
  ];

  /// Built-in default per collection: people as avatars, everything else
  /// (events, activities, milestones, places) as cards that show the whole
  /// picture. Saints use a portrait card (taller aspect).
  static const defaults = <String, String>{
    'priests': avatar,
    'clinics': avatar, // the doctor's photo
    'saints': card,
    'activities': card,
    'milestones': card,
    'meetings': card,
    'alerts': card,
    'seasons': card,
    'facilities': card,
  };

  /// [ar, en] labels (admin).
  static const labels = <String, List<String>>{
    avatar: ['دائرة (صورة شخص)', 'Avatar (round, for a person)'],
    card: ['بطاقة (الصورة كاملة أعلى البطاقة)', 'Card (whole picture on top)'],
    banner: ['شريط عريض (بعرض البطاقة)', 'Banner (full width)'],
  };

  /// [ar, en] collection names (admin).
  static const collectionLabels = <String, List<String>>{
    'priests': ['الآباء الكهنة والمتنيحون', 'Priests & departed fathers'],
    'saints': ['شفعاء الكنيسة', 'Patron saints'],
    'activities': ['الأنشطة', 'Activities'],
    'milestones': ['محطات تاريخية', 'Milestones'],
    'meetings': ['الاجتماعات', 'Meetings'],
    'alerts': ['التنويهات', 'Notices'],
    'seasons': ['المواسم والنهضات', 'Seasons & revivals'],
    'facilities': ['الخدمات العامة', 'Public services'],
    'clinics': ['العيادات (صورة الطبيب)', 'Clinics (doctor photo)'],
  };

  static bool isValid(String? v) => v != null && all.contains(v);

  /// The style to use: the item's own [itemStyle] when valid, else the
  /// admin's section default [sectionStyle], else the built-in default.
  static String resolve(String collection, {String? itemStyle, String? sectionStyle}) {
    if (isValid(itemStyle)) return itemStyle!;
    if (isValid(sectionStyle)) return sectionStyle!;
    return defaults[collection] ?? card;
  }
}

/// Known collections with valid styles only (settings/features.imageStyles).
Map<String, String> parseImageStyles(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final c in ImageStyles.collections)
      if (ImageStyles.isValid(v[c]?.toString())) c: v[c].toString(),
  };
}
