// Admin-defined categories (sections) with their items, and custom pages
// (ADR-027). Pure Dart: no Flutter / Firebase imports.
//
// * `categories/{id}`: a public category (its own page at /section/<slug>).
// * `entries/{id}`: an item assigned to a category (`categoryId`).
// * `pages/{id}`: a generic page (/page/<slug>) built from ordered blocks.
//
// The built-in sections (clinics, meetings, activities…) are NOT migrated:
// they keep their own collections, fields and pages and coexist with these
// (see ADR-027 in docs/memory-bank/10-decisions-and-history.md).

import 'features.dart' show Hideable;
import 'media.dart';

String _s(Object? v) => v is String ? v : (v == null ? '' : v.toString());
bool _b(Object? v, bool def) => v is bool ? v : def;
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

/// URL slugs: lower-case latin letters / digits joined by single hyphens.
const slugMaxLength = 60;
final _slugRe = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidSlug(String s) => s.length <= slugMaxLength && _slugRe.hasMatch(s);

/// Public path of a category / a custom page.
String categoryPath(String slug) => '/section/$slug';
String customPagePath(String slug) => '/page/$slug';

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
  static const all = [heading, paragraph, image, button, link, donation];

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
  };
}

/// Limits shared with firestore.rules (validPage / validPageBlock).
const pageMaxBlocks = 20;
const blockTextMax = 4000;
const blockAccountMax = 120, blockInstapayMax = 80, blockWalletMax = 30;

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

  /// Nothing to show (e.g. a button without a link, an empty paragraph).
  bool get isEmpty => switch (type) {
        BlockTypes.image => url.isEmpty,
        BlockTypes.button || BlockTypes.link => url.isEmpty,
        BlockTypes.donation => account.trim().isEmpty &&
            instapay.trim().isEmpty &&
            wallet.trim().isEmpty &&
            textAr.trim().isEmpty &&
            textEn.trim().isEmpty,
        _ => textAr.trim().isEmpty && textEn.trim().isEmpty,
      };
}

/// An admin-built page (`/page/<slug>`).
class CustomPage implements Hideable {
  final String id, slug, titleAr, titleEn, subtitleAr, subtitleEn;
  final MediaImage? image;
  final List<PageBlock> blocks;
  final bool showInNav;
  @override
  final bool visible;
  @override
  final int order;

  const CustomPage({
    required this.id,
    required this.slug,
    required this.titleAr,
    this.titleEn = '',
    this.subtitleAr = '',
    this.subtitleEn = '',
    this.image,
    this.blocks = const [],
    this.showInNav = false,
    this.visible = true,
    this.order = 0,
  });

  factory CustomPage.fromMap(String id, Map<String, dynamic> m) {
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
      // Off by default: a page is reached from notices / links unless the
      // admin puts it in the menu.
      showInNav: _b(m['showInNav'], false),
      visible: _b(m['visible'], true),
      order: _i(m['order']),
    );
  }

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
  LinkTarget('/clinics', 'العيادات', 'Clinics'),
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
