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
  static const media = 'media'; // optional images on cards (priests, saints, milestones, activities, alerts, seasons)

  static const all = [
    schedule, meetings, clinics, services, history, milestones, saints, priests, departedPriests, //
    activities, alerts, contactInfo, socials, contactForm, assistant, media,
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
    media: ['الصور (إظهار صور الآباء والشفعاء والأنشطة…)', 'Images (show photos on priests, saints, activities…)'],
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
    'burgundy': 0xFF7B2216, // icon oxblood (was wine 0xFF6B1426 before the Coptic identity)
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

/// Public pages whose header (title / subtitle) and intro note an admin can
/// customise (`settings/features.pageHeaders.<key>`).
class CustomizablePages {
  CustomizablePages._();
  static const about = 'about';
  static const schedule = 'schedule';
  static const education = 'education';
  static const activities = 'activities';
  static const clinics = 'clinics';
  static const services = 'services';
  static const contact = 'contact';
  static const ask = 'ask';

  static const all = [about, schedule, education, activities, clinics, services, contact, ask];

  /// [ar, en] labels used in the admin features screen.
  static const labels = <String, List<String>>{
    about: ['عن الكنيسة', 'About the church'],
    schedule: ['مواعيد القداسات', 'Mass schedule'],
    education: ['التربية الكنسية والاجتماعات', 'Sunday school & meetings'],
    activities: ['الأنشطة والكورالات', 'Activities & choirs'],
    clinics: ['العيادات', 'Clinics'],
    services: ['الخدمات العامة', 'Public services'],
    contact: ['تواصل معنا', 'Contact us'],
    ask: ['اسأل الكنيسة', 'Ask the church'],
  };
}

bool? _bool(Object? v) => v is bool ? v : null;
String _str(Object? v) => v is String ? v : '';

/// Admin overrides for one public page: header title / subtitle and an
/// optional intro note. Empty strings keep the built-in text.
class PageCustom {
  final String titleAr, titleEn, subtitleAr, subtitleEn, introAr, introEn;

  const PageCustom({
    this.titleAr = '',
    this.titleEn = '',
    this.subtitleAr = '',
    this.subtitleEn = '',
    this.introAr = '',
    this.introEn = '',
  });

  static const empty = PageCustom();

  bool get isEmpty => [titleAr, titleEn, subtitleAr, subtitleEn, introAr, introEn].every((v) => v.trim().isEmpty);

  factory PageCustom.fromMap(Map<dynamic, dynamic> m) => PageCustom(
        titleAr: _str(m['titleAr']),
        titleEn: _str(m['titleEn']),
        subtitleAr: _str(m['subtitleAr']),
        subtitleEn: _str(m['subtitleEn']),
        introAr: _str(m['introAr']),
        introEn: _str(m['introEn']),
      );

  Map<String, dynamic> toMap() => {
        'titleAr': titleAr,
        'titleEn': titleEn,
        'subtitleAr': subtitleAr,
        'subtitleEn': subtitleEn,
        'introAr': introAr,
        'introEn': introEn,
      };

  @override
  bool operator ==(Object other) =>
      other is PageCustom &&
      other.titleAr == titleAr &&
      other.titleEn == titleEn &&
      other.subtitleAr == subtitleAr &&
      other.subtitleEn == subtitleEn &&
      other.introAr == introAr &&
      other.introEn == introEn;

  @override
  int get hashCode => Object.hash(titleAr, titleEn, subtitleAr, subtitleEn, introAr, introEn);
}

/// Site footer options (FR-G-04). Defaults keep the footer as it was.
class FooterConfig {
  final bool showPhones, showSocials, showQuickLinks;
  final String noteAr, noteEn;

  const FooterConfig({
    this.showPhones = true,
    this.showSocials = true,
    this.showQuickLinks = true,
    this.noteAr = '',
    this.noteEn = '',
  });

  factory FooterConfig.fromMap(Object? v) {
    if (v is! Map) return const FooterConfig();
    return FooterConfig(
      showPhones: _bool(v['showPhones']) ?? true,
      showSocials: _bool(v['showSocials']) ?? true,
      showQuickLinks: _bool(v['showQuickLinks']) ?? true,
      noteAr: _str(v['noteAr']),
      noteEn: _str(v['noteEn']),
    );
  }

  Map<String, dynamic> toMap() => {
        'showPhones': showPhones,
        'showSocials': showSocials,
        'showQuickLinks': showQuickLinks,
        'noteAr': noteAr,
        'noteEn': noteEn,
      };
}

/// Known pages only, empty entries dropped, in [CustomizablePages.all] order.
Map<String, PageCustom> _pageHeaders(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final k in CustomizablePages.all)
      if (v[k] is Map && !PageCustom.fromMap(v[k] as Map).isEmpty) k: PageCustom.fromMap(v[k] as Map),
  };
}

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

  /// Per-page header / intro overrides (keys: [CustomizablePages.all]).
  final Map<String, PageCustom> pageHeaders;

  /// Footer options (FR-G-04).
  final FooterConfig footer;

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
    this.pageHeaders = const {},
    this.footer = const FooterConfig(),
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
      pageHeaders: _pageHeaders(m['pageHeaders']),
      footer: FooterConfig.fromMap(m['footer']),
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
        'pageHeaders': {
          for (final k in CustomizablePages.all)
            if (pageHeaders[k] != null && !pageHeaders[k]!.isEmpty) k: pageHeaders[k]!.toMap(),
        },
        'footer': footer.toMap(),
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
    Map<String, PageCustom>? pageHeaders,
    FooterConfig? footer,
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
        pageHeaders: pageHeaders ?? this.pageHeaders,
        footer: footer ?? this.footer,
      );

  bool enabled(String section) => sections[section] ?? true;

  /// Admin overrides for [pageKey] (one of [CustomizablePages.all]).
  PageCustom pageHeader(String pageKey) => pageHeaders[pageKey] ?? PageCustom.empty;

  /// Optional item images are shown (admin switch `media`, default on).
  bool get showImages => enabled(Sections.media);

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

  /// Whether a public route (or one of its detail sub-routes, such as
  /// `/clinics/<id>`) is available. Unknown routes are always allowed.
  bool routeEnabled(String path) {
    final sections = sectionsForPath(path);
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

/// Detail sub-routes under `/about` and the sections that keep them alive.
const aboutSubRouteSections = <String, List<String>>{
  'priests': [Sections.priests, Sections.departedPriests],
  'saints': [Sections.saints],
  'milestones': [Sections.milestones],
};

/// Sections behind [path] (any one enabled keeps it alive), or null for a
/// route no section controls. Prefix-aware: `/clinics/<id>` is gated like
/// `/clinics`, `/about/priests/<id>` by the (serving or departed) priests
/// sections, `/about/saints/<id>` by saints and `/about/milestones/<id>` by
/// milestones; any other sub-path follows its top-level page.
List<String>? sectionsForPath(String path) {
  final p = _normalizePath(path);
  final exact = routeSections[p];
  if (exact != null) return exact;
  final parts = p.split('/'); // ['', top, sub, ...]
  if (parts.length < 3 || parts.first.isNotEmpty) return null;
  if (parts[1] == 'about') {
    final sub = aboutSubRouteSections[parts[2]];
    if (sub != null) return sub;
  }
  return routeSections['/${parts[1]}'];
}

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
