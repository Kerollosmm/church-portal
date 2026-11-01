// Feature toggles and home-page layout (Firestore doc `settings/features`).
// Pure Dart: no Flutter / Firebase imports, so the logic is unit-tested.

/// Public sections an admin can switch on or off.
class Sections {
  Sections._();
  static const schedule = 'schedule'; // liturgies, vespers, seasons, next-mass card
  static const meetings = 'meetings'; // Sunday school & meetings (/church-education)
  static const clinics = 'clinics';
  static const services = 'services'; // public services: nursery, employment, halls, library, Anba Abraam...
  static const history = 'history'; // church history text + altars
  static const milestones = 'milestones'; // "Our story" highlight cards
  static const saints = 'saints'; // patron saints
  static const priests = 'priests'; // serving priests
  static const departedPriests = 'departedPriests';
  static const activities = 'activities'; // choirs, youth, servants, media...
  static const alerts = 'alerts'; // urgent notice banner
  static const contactInfo = 'contactInfo'; // phones, address, map
  static const socials = 'socials'; // WhatsApp / Facebook / YouTube / Instagram links
  static const contactForm = 'contactForm';
  static const assistant = 'assistant'; // "Ask the church"

  static const all = [
    schedule, meetings, clinics, services, history, milestones, saints, priests, departedPriests, //
    activities, alerts, contactInfo, socials, contactForm, assistant,
  ];

  /// [ar, en] labels used in the admin toggles screen.
  static const labels = <String, List<String>>{
    schedule: ['القداسات والصلوات والمواسم', 'Liturgies, vespers & seasons'],
    meetings: ['التربية الكنسية والاجتماعات', 'Sunday school & meetings'],
    clinics: ['العيادات', 'Clinics'],
    services: ['الخدمات العامة (الحضانة، التوظيف، القاعات، المكتبة، الأنبا أبرآم…)', 'Public services (nursery, employment, halls, library, Anba Abraam…)'],
    history: ['تاريخ الكنيسة والمذابح', 'Church history & altars'],
    milestones: ['محطات تاريخية (قصتنا)', 'Milestones ("Our story")'],
    saints: ['شفعاء الكنيسة', 'Patron saints'],
    priests: ['الآباء الكهنة', 'Priests'],
    departedPriests: ['الآباء المتنيحون', 'Departed fathers'],
    activities: ['الأنشطة والكورالات', 'Activities & choirs'],
    alerts: ['التنويهات العاجلة', 'Urgent notices'],
    contactInfo: ['التليفونات والعنوان والخريطة', 'Phones, address & map'],
    socials: ['روابط التواصل الاجتماعي', 'Social links'],
    contactForm: ['نموذج المراسلة', 'Contact form'],
    assistant: ['اسأل الكنيسة (المساعد الذكي)', 'Ask the church (AI assistant)'],
  };
}

/// Blocks of the home page an admin can reorder / hide. The hero is always first.
class HomeBlocks {
  HomeBlocks._();
  static const banner = 'banner'; // admin announcement banner
  static const alerts = 'alerts';
  static const nextMass = 'nextMass';
  static const quickContacts = 'quickContacts';
  static const milestones = 'milestones';
  static const directory = 'directory';
  static const map = 'map';

  static const defaultOrder = [banner, alerts, nextMass, quickContacts, milestones, directory, map];

  static const labels = <String, List<String>>{
    banner: ['شريط الإعلان', 'Announcement banner'],
    alerts: ['التنويهات العاجلة', 'Urgent notices'],
    nextMass: ['بطاقة القداس القادم', 'Next liturgy card'],
    quickContacts: ['أرقام التليفون السريعة', 'Quick phone numbers'],
    milestones: ['قصتنا (محطات)', 'Our story (milestones)'],
    directory: ['دليل الخدمات', 'Service directory'],
    map: ['خريطة الكنيسة', 'Church map'],
  };

  /// Section a block depends on (the block disappears when it is off).
  static const requires = <String, String>{
    alerts: Sections.alerts,
    nextMass: Sections.schedule,
    quickContacts: Sections.contactInfo,
    milestones: Sections.milestones,
    map: Sections.contactInfo,
  };
}

/// Accent theme presets (primary colour of the design system).
class ThemePresets {
  ThemePresets._();
  static const burgundy = 'burgundy';
  static const all = <String, int>{
    'burgundy': 0xFF6B1426,
    'navy': 0xFF1F3A5F,
    'green': 0xFF1E5631,
    'brown': 0xFF5D3A1A,
    'purple': 0xFF4A235A,
  };
  static const labels = <String, List<String>>{
    'burgundy': ['عنابي (الافتراضي)', 'Burgundy (default)'],
    'navy': ['كحلي', 'Navy'],
    'green': ['أخضر', 'Green'],
    'brown': ['بني', 'Brown'],
    'purple': ['بنفسجي', 'Purple'],
  };
}

bool? _bool(Object? v) => v is bool ? v : null;
String _str(Object? v) => v is String ? v : '';

class FeatureSettings {
  /// Per-section enabled flags. Missing keys mean enabled.
  final Map<String, bool> sections;

  /// Home blocks in display order (unknown keys dropped, missing ones appended).
  final List<String> homeOrder;

  /// Home blocks the admin hid.
  final Set<String> homeHidden;

  final String heroTitleAr, heroTitleEn, heroSubtitleAr, heroSubtitleEn;
  final bool bannerEnabled;
  final String bannerAr, bannerEn, bannerLink;
  final String theme;

  const FeatureSettings({
    this.sections = const {},
    this.homeOrder = HomeBlocks.defaultOrder,
    this.homeHidden = const {},
    this.heroTitleAr = '',
    this.heroTitleEn = '',
    this.heroSubtitleAr = '',
    this.heroSubtitleEn = '',
    this.bannerEnabled = false,
    this.bannerAr = '',
    this.bannerEn = '',
    this.bannerLink = '',
    this.theme = ThemePresets.burgundy,
  });

  /// Everything on: used before the doc loads and when it does not exist.
  static const defaults = FeatureSettings();

  factory FeatureSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;
    final rawSections = m['sections'];
    final sections = <String, bool>{};
    if (rawSections is Map) {
      rawSections.forEach((k, v) {
        final b = _bool(v);
        if (b != null) sections[k.toString()] = b;
      });
    }
    final rawOrder = m['homeOrder'];
    final rawHidden = m['homeHidden'];
    final theme = _str(m['theme']);
    return FeatureSettings(
      sections: sections,
      homeOrder: normalizeHomeOrder(rawOrder is List ? rawOrder.map((e) => e.toString()).toList() : const []),
      homeHidden: rawHidden is List
          ? rawHidden.map((e) => e.toString()).where(HomeBlocks.defaultOrder.contains).toSet()
          : const {},
      heroTitleAr: _str(m['heroTitleAr']),
      heroTitleEn: _str(m['heroTitleEn']),
      heroSubtitleAr: _str(m['heroSubtitleAr']),
      heroSubtitleEn: _str(m['heroSubtitleEn']),
      bannerEnabled: _bool(m['bannerEnabled']) ?? false,
      bannerAr: _str(m['bannerAr']),
      bannerEn: _str(m['bannerEn']),
      bannerLink: _str(m['bannerLink']),
      theme: ThemePresets.all.containsKey(theme) ? theme : ThemePresets.burgundy,
    );
  }

  Map<String, dynamic> toMap() => {
        'sections': {for (final s in Sections.all) s: enabled(s)},
        'homeOrder': homeOrder,
        'homeHidden': homeHidden.toList()..sort(),
        'heroTitleAr': heroTitleAr,
        'heroTitleEn': heroTitleEn,
        'heroSubtitleAr': heroSubtitleAr,
        'heroSubtitleEn': heroSubtitleEn,
        'bannerEnabled': bannerEnabled,
        'bannerAr': bannerAr,
        'bannerEn': bannerEn,
        'bannerLink': bannerLink,
        'theme': theme,
      };

  FeatureSettings copyWith({
    Map<String, bool>? sections,
    List<String>? homeOrder,
    Set<String>? homeHidden,
    String? heroTitleAr,
    String? heroTitleEn,
    String? heroSubtitleAr,
    String? heroSubtitleEn,
    bool? bannerEnabled,
    String? bannerAr,
    String? bannerEn,
    String? bannerLink,
    String? theme,
  }) =>
      FeatureSettings(
        sections: sections ?? this.sections,
        homeOrder: homeOrder ?? this.homeOrder,
        homeHidden: homeHidden ?? this.homeHidden,
        heroTitleAr: heroTitleAr ?? this.heroTitleAr,
        heroTitleEn: heroTitleEn ?? this.heroTitleEn,
        heroSubtitleAr: heroSubtitleAr ?? this.heroSubtitleAr,
        heroSubtitleEn: heroSubtitleEn ?? this.heroSubtitleEn,
        bannerEnabled: bannerEnabled ?? this.bannerEnabled,
        bannerAr: bannerAr ?? this.bannerAr,
        bannerEn: bannerEn ?? this.bannerEn,
        bannerLink: bannerLink ?? this.bannerLink,
        theme: theme ?? this.theme,
      );

  bool enabled(String section) => sections[section] ?? true;

  /// Whether a home block is shown (not hidden, its section on, and for the
  /// banner: switched on with some text).
  bool showHomeBlock(String block) {
    if (homeHidden.contains(block)) return false;
    final req = HomeBlocks.requires[block];
    if (req != null && !enabled(req)) return false;
    if (block == HomeBlocks.banner) return bannerEnabled && (bannerAr.trim().isNotEmpty || bannerEn.trim().isNotEmpty);
    return true;
  }

  /// Home blocks to render, in order.
  List<String> get visibleHomeBlocks => homeOrder.where(showHomeBlock).toList();

  /// Whether a public route is available. Unknown routes are always allowed.
  bool routeEnabled(String path) {
    final sections = routeSections[_normalizePath(path)];
    if (sections == null) return true;
    return sections.any(enabled);
  }

  int get disabledCount => Sections.all.where((s) => !enabled(s)).length;
}

/// Public routes and the sections that keep them alive (any one enabled).
const routeSections = <String, List<String>>{
  '/mass-schedule': [Sections.schedule],
  '/church-education': [Sections.meetings],
  '/church-activities': [Sections.activities],
  '/clinics': [Sections.clinics],
  '/public-services': [Sections.services],
  '/about': [Sections.history, Sections.saints, Sections.priests, Sections.departedPriests],
  '/contact': [Sections.contactInfo, Sections.socials, Sections.contactForm],
  '/ask': [Sections.assistant],
};

String _normalizePath(String p) {
  if (p.length > 1 && p.endsWith('/')) return p.substring(0, p.length - 1);
  return p;
}

/// Known blocks only, no duplicates; blocks missing from [order] are appended
/// in default order (so a new block added later still shows up).
List<String> normalizeHomeOrder(List<String> order) {
  final out = <String>[];
  for (final b in order) {
    if (HomeBlocks.defaultOrder.contains(b) && !out.contains(b)) out.add(b);
  }
  for (final b in HomeBlocks.defaultOrder) {
    if (!out.contains(b)) out.add(b);
  }
  return out;
}

/// Content items that can be hidden from the public without deleting them.
abstract class Hideable {
  bool get visible;
  int get order;
}

/// Visible items only, stably sorted by `order` (ties keep their input order).
List<T> publicItems<T extends Hideable>(Iterable<T> items) {
  final indexed = items.where((e) => e.visible).toList().asMap().entries.toList()
    ..sort((a, b) {
      final o = a.value.order.compareTo(b.value.order);
      return o != 0 ? o : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}
