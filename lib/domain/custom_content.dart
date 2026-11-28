// Admin-defined categories (sections) with their items, and custom pages
// (ADR-027). Pure Dart: no Flutter / Firebase imports.
//
// * `categories/{id}`: a public category (its own page at /section/<slug>).
// * `entries/{id}`: an item assigned to a category (`categoryId`).
// * `pages/{id}`: a generic page (/page/<slug>) built from ordered blocks.
//
// The built-in sections (meetings, activities…) are NOT migrated:
// they keep their own collections, fields and pages and coexist with these
// (see ADR-027 in docs/memory-bank/10-decisions-and-history.md).

import 'features.dart' show FeatureSettings, Hideable;
import 'media.dart';

String _s(Object? v) => v is String ? v : (v == null ? '' : v.toString());
bool _b(Object? v, bool def) => v is bool ? v : def;
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
DateTime? _dateTime(Object? v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// URL slugs: lower-case latin letters / digits joined by single hyphens.
const slugMaxLength = 60;
final _slugRe = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidSlug(String s) => s.length <= slugMaxLength && _slugRe.hasMatch(s);

/// Public path of a category / a custom page.
String categoryPath(String slug) => '/section/$slug';
String customPagePath(String slug) => '/page/$slug';

/// True when [url] is an in-app path (starts with a single `/`, not `//`).
bool isInternalAppLink(String url) {
  final l = url.trim();
  return l.startsWith('/') && !l.startsWith('//');
}

String _canonicalInternalPath(String path) => switch (path) {
      '/activities' => '/church-activities',
      '/priests' => '/about',
      '/notices' => '/notifications',
      '/donations' => '/page/donations',
      '/clinics' => '/',
      _ => path,
    };

/// Whether [block] should be rendered on a public custom page given [features]
/// and the loaded public [pages] / [categories]. Internal button and link
/// targets whose route is disabled or whose target `/page/<slug>` or
/// `/section/<slug>` does not exist (or is hidden) are hidden; external links
/// are unchanged.
bool isPageBlockVisible(
  PageBlock block, {
  required FeatureSettings features,
  Iterable<CustomPage>? pages,
  Iterable<CustomCategory>? categories,
}) {
  if (block.type != BlockTypes.button && block.type != BlockTypes.link) return true;
  final raw = block.url.trim();
  if (raw.isEmpty) return false;
  if (!isInternalAppLink(raw)) return true;

  final parsed = Uri.tryParse(raw)?.path ?? raw;
  final norm = parsed.length > 1 && parsed.endsWith('/') ? parsed.substring(0, parsed.length - 1) : parsed;
  final target = _canonicalInternalPath(norm);
  if (!features.routeEnabled(target)) return false;

  if (target == '/page' || target.startsWith('/page/')) {
    final slug = target.length > '/page/'.length ? target.substring('/page/'.length) : '';
    if (slug.isEmpty || slug.contains('/')) return false;
    if (pages != null && !pages.any((p) => p.slug == slug)) return false;
  } else if (target == '/section' || target.startsWith('/section/')) {
    final slug = target.length > '/section/'.length ? target.substring('/section/'.length) : '';
    if (slug.isEmpty || slug.contains('/')) return false;
    if (categories != null && !categories.any((c) => c.slug == slug)) return false;
  }
  return true;
}

/// Icons an admin can pick for a category (mapped to Material icons in the UI).
class CategoryIcons {
  CategoryIcons._();
  static const all = [
    'star', 'church', 'people', 'heart', 'book', 'music', 'medical', 'school', 'event', 'volunteer', 'donate', 'info', //
  ];
}

/// An admin-defined public category (section).
class CustomCategory implements Hideable {
  final String id, slug, nameAr, nameEn, introAr, introEn, icon;

  /// Default image display style of its items (ADR-023); '' = card.
  final String imageStyle;
  final bool showInNav;
  @override
  final bool visible;
  @override
  final int order;

  const CustomCategory({
    required this.id,
    required this.slug,
    required this.nameAr,
    this.nameEn = '',
    this.introAr = '',
    this.introEn = '',
    this.icon = 'star',
    this.imageStyle = '',
    this.showInNav = true,
    this.visible = true,
    this.order = 0,
  });

  factory CustomCategory.fromMap(String id, Map<String, dynamic> m) => CustomCategory(
        id: id,
        slug: _s(m['slug']),
        nameAr: _s(m['nameAr']),
        nameEn: _s(m['nameEn']),
        introAr: _s(m['introAr']),
        introEn: _s(m['introEn']),
        icon: CategoryIcons.all.contains(m['icon']) ? m['icon'] as String : 'star',
        imageStyle: _s(m['imageStyle']),
        showInNav: _b(m['showInNav'], true),
        visible: _b(m['visible'], true),
        order: _i(m['order']),
      );

  String get path => categoryPath(slug);

  /// Usable on the site: a valid slug and a name.
  bool get isUsable => isValidSlug(slug) && (nameAr.trim().isNotEmpty || nameEn.trim().isNotEmpty);
}

/// An item assigned to a [CustomCategory].
class CategoryEntry implements Hideable {
  final String id, categoryId, titleAr, titleEn, descAr, descEn, contactPhone, externalUrl;
  final String externalLabelAr, externalLabelEn, imageStyle;
  final MediaImage? image;
  final bool sample;
  @override
  final bool visible;
  @override
  final int order;

  const CategoryEntry({
    required this.id,
    required this.categoryId,
    required this.titleAr,
    this.titleEn = '',
    this.descAr = '',
    this.descEn = '',
    this.contactPhone = '',
    this.externalUrl = '',
    this.externalLabelAr = '',
    this.externalLabelEn = '',
    this.imageStyle = '',
    this.image,
    this.sample = false,
    this.visible = true,
    this.order = 0,
  });

  factory CategoryEntry.fromMap(String id, Map<String, dynamic> m) => CategoryEntry(
        id: id,
        categoryId: _s(m['categoryId']),
        titleAr: _s(m['titleAr']),
        titleEn: _s(m['titleEn']),
        descAr: _s(m['descAr']),
        descEn: _s(m['descEn']),
        contactPhone: _s(m['contactPhone']),
        externalUrl: _s(m['externalUrl']),
        externalLabelAr: _s(m['externalLabelAr']),
        externalLabelEn: _s(m['externalLabelEn']),
        imageStyle: _s(m['imageStyle']),
        image: MediaImage.fromMap(m['image']),
        sample: _b(m['sample'], false),
        visible: _b(m['visible'], true),
        order: _i(m['order']),
      );
}

/// Public categories: visible, usable, unique slugs (the first by order wins),
/// sorted by `order` (stable).
List<CustomCategory> publicCategories(Iterable<CustomCategory> all) {
  final indexed = all.where((c) => c.visible && c.isUsable).toList().asMap().entries.toList()
    ..sort((a, b) {
      final o = a.value.order.compareTo(b.value.order);
      return o != 0 ? o : a.key.compareTo(b.key);
    });
  final seen = <String>{};
  return [
    for (final e in indexed)
      if (seen.add(e.value.slug)) e.value,
  ];
}

/// The public items of [categoryId] (visible, sorted by `order`, stable).
List<CategoryEntry> entriesOf(String categoryId, Iterable<CategoryEntry> all) {
  final indexed = all.where((e) => e.visible && e.categoryId == categoryId).toList().asMap().entries.toList()
    ..sort((a, b) {
      final o = a.value.order.compareTo(b.value.order);
      return o != 0 ? o : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// Entry ids an admin's category deletion must hide (ADR-027: deleting a
/// category hides its items, never deletes them). Already-hidden items are
/// left alone (nothing to write).
List<String> entryIdsToHide(String categoryId, Iterable<({String id, Map<String, dynamic> data})> entries) => [
      for (final e in entries)
        if (e.data['categoryId'] == categoryId && e.data['visible'] != false) e.id,
    ];

/// Page ids placed inside [categoryId] (`placement == 'section'`) that must be
/// unlinked back to `'link'` when [categoryId] is deleted.
List<String> pageIdsToUnlink(String categoryId, Iterable<({String id, Map<String, dynamic> data})> pages) => [
      for (final p in pages)
        if (p.data['placement'] == PagePlacements.section && p.data['categoryId'] == categoryId) p.id,
    ];

// ------------------------------------------------------------ custom pages

/// Block types of a custom page body.
class BlockTypes {
  BlockTypes._();
  static const heading = 'heading';
  static const paragraph = 'paragraph';
  static const image = 'image';
  static const button = 'button';
  static const link = 'link';
  static const donation = 'donation';
  static const list = 'list';
  static const details = 'details';
  static const all = [heading, paragraph, image, button, link, donation, list, details];

  /// Fields each type uses (the editor shows only these). A block is
  /// stored as ONE string, its 7 fields in [PageBlock.fieldOrder] joined by
  /// U+001F (firestore.rules validPageBlock: one regex per block keeps 20
  /// blocks within the 1,000-expression budget of a write).
  static const fieldsOf = <String, List<String>>{
    heading: ['textAr', 'textEn'],
    paragraph: ['textAr', 'textEn'],
    image: ['url', 'textAr', 'textEn'],
    button: ['textAr', 'textEn', 'url'],
    link: ['textAr', 'textEn', 'url'],
    donation: ['account', 'instapay', 'wallet', 'textAr', 'textEn'],
    list: ['account', 'textAr', 'textEn'],
    details: ['textAr', 'textEn'],
  };
}

/// Limits shared with firestore.rules (validPage / validPageBlock).
const pageMaxBlocks = 20;
const blockTextMax = 4000;
const blockAccountMax = 120, blockInstapayMax = 80, blockWalletMax = 30;
const listBlockMaxItems = 20;
const listItemMax = 200;
const detailsSummaryMax = 200;
const detailsBodyMax = 3500;

/// Display style for a list block in custom pages.
class ListStyles {
  ListStyles._();
  static const bullet = 'bullet';
  static const numbered = 'numbered';
  static const all = [bullet, numbered];
}

/// One bilingual item inside a [BlockTypes.list] block.
typedef PageListItem = ({String ar, String en});

/// Bilingual summary and body of a [BlockTypes.details] block.
typedef PageDetailsData = ({String summaryAr, String summaryEn, String bodyAr, String bodyEn});

/// One block of a custom page. Unused fields are ''.
class PageBlock {
  final String type, textAr, textEn, url, account, instapay, wallet;
  const PageBlock({
    required this.type,
    this.textAr = '',
    this.textEn = '',
    this.url = '',
    this.account = '',
    this.instapay = '',
    this.wallet = '',
  });

  /// Stored field order (the admin editor's sub-fields follow it too).
  static const fieldOrder = ['type', 'textAr', 'textEn', 'url', 'account', 'instapay', 'wallet'];
  static const separator = '\u001f';
  static const listSeparator = '\u001e';

  /// Builds a list block from bilingual [items] and a [ListStyles] value.
  factory PageBlock.list({
    required List<PageListItem> items,
    String style = ListStyles.bullet,
  }) {
    String clean(String s) => s.replaceAll(separator, '').replaceAll(listSeparator, '').trim();
    final cleanedAr = <String>[];
    final cleanedEn = <String>[];
    var hasEn = false;
    for (final it in items) {
      cleanedAr.add(clean(it.ar));
      final en = clean(it.en);
      if (en.isNotEmpty) hasEn = true;
      cleanedEn.add(en);
    }
    return PageBlock(
      type: BlockTypes.list,
      textAr: cleanedAr.join(listSeparator),
      textEn: hasEn ? cleanedEn.join(listSeparator) : '',
      account: ListStyles.all.contains(style) ? style : ListStyles.bullet,
    );
  }

  /// Builds a collapsible details block from bilingual summary and body.
  factory PageBlock.details({
    required String summaryAr,
    required String bodyAr,
    String summaryEn = '',
    String bodyEn = '',
  }) {
    String clean(String s) => s.replaceAll(separator, '').replaceAll(listSeparator, '').trim();
    final sAr = clean(summaryAr);
    final bAr = clean(bodyAr);
    final sEn = clean(summaryEn);
    final bEn = clean(bodyEn);
    return PageBlock(
      type: BlockTypes.details,
      textAr: (sAr.isEmpty && bAr.isEmpty) ? '' : '$sAr$listSeparator$bAr',
      textEn: (sEn.isEmpty && bEn.isEmpty) ? '' : '$sEn$listSeparator$bEn',
    );
  }

  /// The stored form: the 7 fields joined by U+001F (separators typed into a
  /// text are dropped).
  String encode() => [for (final v in toMap().values) '$v'.replaceAll(separator, '')].join(separator);

  /// A stored block: the encoded string (or, tolerantly, a map). Unknown
  /// types and malformed values read as null (skipped when rendering).
  static PageBlock? fromStored(Object? v) {
    if (v is String) {
      final parts = v.split(separator);
      if (parts.length != fieldOrder.length) return null;
      return fromMap({for (var i = 0; i < parts.length; i++) fieldOrder[i]: parts[i]});
    }
    return fromMap(v);
  }

  /// Unknown types read as null (skipped when rendering).
  static PageBlock? fromMap(Object? v) {
    if (v is! Map) return null;
    final t = _s(v['type']);
    if (!BlockTypes.all.contains(t)) return null;
    return PageBlock(
      type: t,
      textAr: _s(v['textAr']),
      textEn: _s(v['textEn']),
      url: _s(v['url']).trim(),
      account: _s(v['account']),
      instapay: _s(v['instapay']),
      wallet: _s(v['wallet']),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'textAr': textAr,
        'textEn': textEn,
        'url': url,
        'account': account,
        'instapay': instapay,
        'wallet': wallet,
      };

  bool get isDonation => type == BlockTypes.donation;

  /// Resolved display style for a [BlockTypes.list] block.
  String get listStyle => account == ListStyles.numbered ? ListStyles.numbered : ListStyles.bullet;

  /// Decoded bilingual items for a [BlockTypes.list] block (empty for other types).
  List<PageListItem> get listItems {
    if (type != BlockTypes.list || textAr.isEmpty) return const [];
    final arParts = textAr.split(listSeparator);
    final enParts = textEn.isEmpty ? const <String>[] : textEn.split(listSeparator);
    final out = <PageListItem>[];
    for (var i = 0; i < arParts.length; i++) {
      final ar = arParts[i].trim();
      if (ar.isEmpty) continue;
      final en = i < enParts.length ? enParts[i].trim() : '';
      out.add((ar: ar, en: en));
    }
    return out;
  }

  /// Decoded bilingual summary and body for a [BlockTypes.details] block.
  PageDetailsData get details {
    if (type != BlockTypes.details) {
      return (summaryAr: '', summaryEn: '', bodyAr: '', bodyEn: '');
    }
    (String, String) splitPair(String raw) {
      if (raw.isEmpty) return ('', '');
      final idx = raw.indexOf(listSeparator);
      if (idx == -1) return (raw.replaceAll(separator, '').trim(), '');
      final s = raw.substring(0, idx).replaceAll(separator, '').trim();
      final b = raw.substring(idx + 1).replaceAll(listSeparator, '').replaceAll(separator, '').trim();
      return (s, b);
    }

    final (sAr, bAr) = splitPair(textAr);
    final (sEn, bEn) = splitPair(textEn);
    return (summaryAr: sAr, summaryEn: sEn, bodyAr: bAr, bodyEn: bEn);
  }

  /// Resolves the localized `(summary, body)` pair at the **block level**:
  /// English is shown only when [isAr] is false AND both `summaryEn` and
  /// `bodyEn` are non-empty; otherwise both fields use Arabic (never mixed).
  ({String summary, String body})? resolveDetails({required bool isAr}) {
    if (type != BlockTypes.details) return null;
    final d = details;
    final hasAr = d.summaryAr.isNotEmpty && d.bodyAr.isNotEmpty;
    final hasEn = d.summaryEn.isNotEmpty && d.bodyEn.isNotEmpty;
    if (!isAr && hasEn) return (summary: d.summaryEn, body: d.bodyEn);
    if (hasAr) return (summary: d.summaryAr, body: d.bodyAr);
    if (hasEn) return (summary: d.summaryEn, body: d.bodyEn);
    return null;
  }

  /// Nothing to show (e.g. a button without a link, an empty paragraph).
  bool get isEmpty => switch (type) {
        BlockTypes.image => url.isEmpty,
        BlockTypes.button || BlockTypes.link => url.isEmpty,
        BlockTypes.donation => account.trim().isEmpty &&
            instapay.trim().isEmpty &&
            wallet.trim().isEmpty &&
            textAr.trim().isEmpty &&
            textEn.trim().isEmpty,
        BlockTypes.list => listItems.isEmpty,
        BlockTypes.details => resolveDetails(isAr: true) == null,
        _ => textAr.trim().isEmpty && textEn.trim().isEmpty,
      };
}

/// Built-in sections a custom page (`placement == 'section'`) can link to.
/// IDs use the `builtin_<key>` prefix with the canonical [Sections] key
/// (`meetings` for `/church-education`, matching `settings/features.sections`).
class BuiltInSections {
  BuiltInSections._();
  static const schedule = 'builtin_schedule';
  static const meetings = 'builtin_meetings';
  static const activities = 'builtin_activities';
  static const services = 'builtin_services';
  static const about = 'builtin_about';
  static const contact = 'builtin_contact';

  static const all = <CustomCategory>[
    CustomCategory(id: schedule, slug: 'mass-schedule', nameAr: 'مواعيد القداسات', nameEn: 'Mass schedule', icon: 'event'),
    CustomCategory(id: meetings, slug: 'church-education', nameAr: 'التربية الكنسية والاجتماعات', nameEn: 'Sunday school & meetings', icon: 'school'),
    CustomCategory(id: activities, slug: 'church-activities', nameAr: 'الأنشطة والكورالات', nameEn: 'Activities & choirs', icon: 'people'),
    CustomCategory(id: services, slug: 'public-services', nameAr: 'الخدمات العامة', nameEn: 'Public services', icon: 'volunteer'),
    CustomCategory(id: about, slug: 'about', nameAr: 'عن الكنيسة', nameEn: 'About the church', icon: 'church'),
    CustomCategory(id: contact, slug: 'contact', nameAr: 'تواصل معنا', nameEn: 'Contact us', icon: 'info'),
  ];

  static CustomCategory? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static bool isBuiltIn(String id) => switch (id) {
        schedule || meetings || activities || services || about || contact => true,
        _ => false,
      };

  /// True when built-in section [id] has at least one visible section page.
  /// Avoids [all] / [byId] so public bundles tree-shake admin section metadata.
  static bool isNonEmpty(String id, Iterable<CustomPage> pages) =>
      isBuiltIn(id) &&
      isCategoryNonEmpty(CustomCategory(id: id, slug: '', nameAr: '', nameEn: ''), const [], pages);

  /// Public route path for built-in section [id], or null if unknown.
  static String? pathFor(String id) {
    final c = byId(id);
    return c == null ? null : '/${c.slug}';
  }

  /// Maps a [CustomizablePages] key to its canonical built-in section ID, or null.
  static String? idForPageKey(String pageKey) => switch (pageKey) {
        'schedule' => schedule,
        'education' || 'meetings' => meetings,
        'activities' => activities,
        'services' => services,
        'about' => about,
        'contact' => contact,
        _ => null,
      };
}

/// Where a custom page is placed on the public site (P1-18).
class PagePlacements {
  PagePlacements._();
  static const link = 'link';
  static const nav = 'nav';
  static const section = 'section';
  static const all = [link, nav, section];
}

/// An admin-built page (`/page/<slug>`).
class CustomPage implements Hideable {
  final String id, slug, titleAr, titleEn, subtitleAr, subtitleEn;
  final MediaImage? image;
  final List<PageBlock> blocks;
  final String placement, categoryId;
  final bool showInNav, featured;
  @override
  final bool visible;
  @override
  final int order;
  final DateTime? updatedAt;

  const CustomPage({
    required this.id,
    required this.slug,
    required this.titleAr,
    this.titleEn = '',
    this.subtitleAr = '',
    this.subtitleEn = '',
    this.image,
    this.blocks = const [],
    this.placement = '',
    this.categoryId = '',
    this.showInNav = false,
    this.featured = false,
    this.visible = true,
    this.order = 0,
    this.updatedAt,
  });

  factory CustomPage.fromMap(String id, Map<String, dynamic> m) {
    final nav = _b(m['showInNav'], false);
    final rawP = _s(m['placement']);
    final p = PagePlacements.all.contains(rawP) ? rawP : (nav ? PagePlacements.nav : PagePlacements.link);
    final raw = m['blocks'];
    return CustomPage(
      id: id,
      slug: _s(m['slug']),
      titleAr: _s(m['titleAr']),
      titleEn: _s(m['titleEn']),
      subtitleAr: _s(m['subtitleAr']),
      subtitleEn: _s(m['subtitleEn']),
      image: MediaImage.fromMap(m['image']),
      blocks: raw is List ? [for (final b in raw) ?PageBlock.fromStored(b)] : const [],
      placement: p,
      categoryId: _s(m['categoryId']),
      // Off by default: a page is reached from notices / links unless placed in nav.
      showInNav: p == PagePlacements.nav,
      featured: _b(m['featured'], false),
      visible: _b(m['visible'], true),
      order: _i(m['order']),
      updatedAt: _dateTime(m['updatedAt']),
    );
  }

  /// Resolved placement, preserving backward compatibility for const fixtures
  /// constructed with only [showInNav].
  String get effectivePlacement =>
      PagePlacements.all.contains(placement) ? placement : (showInNav ? PagePlacements.nav : PagePlacements.link);

  bool get inNav => effectivePlacement == PagePlacements.nav;

  String get path => customPagePath(slug);
  bool get isUsable => isValidSlug(slug) && (titleAr.trim().isNotEmpty || titleEn.trim().isNotEmpty);
}

/// Public custom pages (visible, usable, unique slugs), sorted by `order`.
List<CustomPage> publicPages(Iterable<CustomPage> all) {
  final indexed = all.where((p) => p.visible && p.isUsable).toList().asMap().entries.toList()
    ..sort((a, b) {
      final o = a.value.order.compareTo(b.value.order);
      return o != 0 ? o : a.key.compareTo(b.key);
    });
  final seen = <String>{};
  return [
    for (final e in indexed)
      if (seen.add(e.value.slug)) e.value,
  ];
}

/// Visible usable custom pages placed inside custom category or built-in
/// section [categoryId].
List<CustomPage> sectionPages(String categoryId, Iterable<CustomPage> all) => [
      for (final p in publicPages(all))
        if (p.effectivePlacement == PagePlacements.section && p.categoryId == categoryId) p,
    ];

/// Visible usable custom pages featured on the home page, sorted by `order`
/// ascending, then `updatedAt` descending (newest first, non-null before null),
/// then original index on ties. Slugs are deduplicated (first wins).
List<CustomPage> featuredPages(Iterable<CustomPage> all) {
  final indexed = all
      .toList()
      .asMap()
      .entries
      .where((e) => e.value.visible && e.value.isUsable && e.value.featured)
      .toList()
    ..sort((a, b) {
      final pA = a.value;
      final pB = b.value;
      final o = pA.order.compareTo(pB.order);
      if (o != 0) return o;
      final uA = pA.updatedAt;
      final uB = pB.updatedAt;
      if (uA != null && uB != null) {
        final u = uB.compareTo(uA);
        if (u != 0) return u;
      } else if (uA != null) {
        return -1;
      } else if (uB != null) {
        return 1;
      }
      return a.key.compareTo(b.key);
    });
  final seen = <String>{};
  return [
    for (final e in indexed)
      if (seen.add(e.value.slug)) e.value,
  ];
}

/// True when [category] (either a custom category or one of
/// [BuiltInSections.all]) has at least one visible entry or at least one
/// visible section page.
bool isCategoryNonEmpty(
  CustomCategory category,
  Iterable<CategoryEntry> entries,
  Iterable<CustomPage> pages,
) =>
    entriesOf(category.id, entries).isNotEmpty ||
    sectionPages(category.id, pages).isNotEmpty;

/// Public categories that have at least one visible entry or visible section page.
List<CustomCategory> publicNonEmptyCategories(
  Iterable<CustomCategory> categories,
  Iterable<CategoryEntry> entries,
  Iterable<CustomPage> pages,
) =>
    [
      for (final c in publicCategories(categories))
        if (isCategoryNonEmpty(c, entries, pages)) c,
    ];

/// A link button target an admin can pick (notices' "Learn more", page
/// buttons): an in-app path or an external URL.
class LinkTarget {
  final String path, labelAr, labelEn;
  const LinkTarget(this.path, this.labelAr, this.labelEn);
}

/// Built-in in-app routes offered by the link picker.
const builtInLinkTargets = [
  LinkTarget('/', 'الرئيسية', 'Home'),
  LinkTarget('/mass-schedule', 'مواعيد القداسات', 'Mass schedule'),
  LinkTarget('/church-education', 'التربية الكنسية والاجتماعات', 'Sunday school & meetings'),
  LinkTarget('/church-activities', 'الأنشطة والكورالات', 'Activities & choirs'),
  LinkTarget('/public-services', 'الخدمات العامة', 'Public services'),
  LinkTarget('/about', 'عن الكنيسة', 'About the church'),
  LinkTarget('/contact', 'تواصل معنا', 'Contact us'),
];

/// Picker targets: custom pages first (the common case: a notice pointing at
/// a donations page), then categories, then the built-in routes. Hidden
/// pages / categories are included (marked by the admin UI) so a notice can
/// be prepared before the page goes live.
List<LinkTarget> linkTargets({
  Iterable<({String slug, String titleAr, String titleEn})> pages = const [],
  Iterable<({String slug, String titleAr, String titleEn})> categories = const [],
}) =>
    [
      for (final p in pages)
        if (isValidSlug(p.slug)) LinkTarget(customPagePath(p.slug), p.titleAr, p.titleEn),
      for (final c in categories)
        if (isValidSlug(c.slug)) LinkTarget(categoryPath(c.slug), c.titleAr, c.titleEn),
      ...builtInLinkTargets,
    ];
