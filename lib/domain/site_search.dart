// Pure-Dart client-side public site search & shared Arabic text normalization.
// Zero Flutter or Firebase imports so matching/normalization are unit-tested
// directly and shared with the admin list search without duplicating logic.

import 'cairo_time.dart';
import 'custom_content.dart';
import 'features.dart';
import 'item_detail.dart';
import 'models.dart';
import 'rules.dart';
import 'time_format.dart';

final RegExp _arabicDiacriticsAndTatweel = RegExp(r'[\u0640\u064B-\u065F\u0670]');
final RegExp _collapseWhitespace = RegExp(r'\s+');

/// Normalizes Arabic and Latin text for client-side search (shared by the
/// public site search and the admin list filter):
/// - converts Arabic-Indic / Persian digits to ASCII digits via [normalizeDigits]
/// - strips Arabic diacritics (tashkeel) and tatweel
/// - unifies Arabic Alef variants (`أ إ آ ٱ` -> `ا`), Teh Marbuta (`ة` -> `ه`),
///   and Alef Maksura (`ى` -> `ي`)
/// - lower-cases Latin characters and collapses whitespace.
String normalizeSearchText(String input) {
  if (input.isEmpty) return '';
  final digits = normalizeDigits(input);
  final stripped = digits.replaceAll(_arabicDiacriticsAndTatweel, '');
  final buf = StringBuffer();
  for (final rune in stripped.runes) {
    switch (rune) {
      case 0x0622: // آ
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        buf.writeCharCode(0x0627); // ا
      case 0x0629: // ة
        buf.writeCharCode(0x0647); // ه
      case 0x0649: // ى
        buf.writeCharCode(0x064A); // ي
      default:
        buf.writeCharCode(rune);
    }
  }
  return buf.toString().toLowerCase().replaceAll(_collapseWhitespace, ' ').trim();
}

/// Tokenizes [query] after [normalizeSearchText].
List<String> searchTokens(String query) {
  final q = normalizeSearchText(query);
  if (q.isEmpty) return const [];
  return q.split(' ').where((t) => t.isNotEmpty).toList();
}

/// True when every normalized [tokens] entry appears in [normalizedHaystack].
bool matchesSearchTokens(String normalizedHaystack, List<String> tokens) =>
    tokens.isNotEmpty && tokens.every(normalizedHaystack.contains);

/// Content categories shown in grouped search results.
enum SearchResultKind {
  liturgy,
  meeting,
  activity,
  facility,
  priest,
  saint,
  milestone,
  customSection,
  customPage,
}

/// One matching public item with its destination in-app route.
class SearchResult {
  final SearchResultKind kind;
  final String id;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String route;
  final bool titleMatched;

  const SearchResult({
    required this.kind,
    required this.id,
    required this.titleAr,
    required this.titleEn,
    this.subtitleAr = '',
    this.subtitleEn = '',
    required this.route,
    this.titleMatched = false,
  });
}

/// Grouped search hits for one [SearchResultKind].
class SearchResultGroup {
  final SearchResultKind kind;
  final List<SearchResult> items;
  const SearchResultGroup({required this.kind, required this.items});
}

/// Already-loaded client collections searched in memory with zero extra reads.
class SiteSearchInput {
  final FeatureSettings features;
  final DateTime? now;
  final List<Liturgy> liturgies;
  final List<Season> seasons;
  final List<Meeting> meetings;
  final List<Activity> activities;
  final List<Facility> facilities;
  final List<Priest> priests;
  final List<Saint> saints;
  final List<Milestone> milestones;
  final List<CustomCategory> categories;
  final List<CategoryEntry> entries;
  final List<CustomPage> pages;

  const SiteSearchInput({
    this.features = FeatureSettings.defaults,
    this.now,
    this.liturgies = const [],
    this.seasons = const [],
    this.meetings = const [],
    this.activities = const [],
    this.facilities = const [],
    this.priests = const [],
    this.saints = const [],
    this.milestones = const [],
    this.categories = const [],
    this.entries = const [],
    this.pages = const [],
  });
}

String _extraFieldsText(ItemDetails d) => [
      for (final f in d.extraFields) ...[f.titleAr, f.titleEn, f.valueAr, f.valueEn],
    ].join(' ');

String _programText(ProgramInfo p) =>
    '${p.speakerAr} ${p.speakerEn} ${p.topicAr} ${p.topicEn} ${p.choirAr} ${p.choirEn} ${p.attachmentLabelAr} ${p.attachmentLabelEn}';

String _joinParts(Iterable<String> parts) => parts.where((s) => s.trim().isNotEmpty).join(' • ');

List<SearchResult> _orderByTitleMatch(List<SearchResult> list) {
  if (list.length <= 1) return list;
  final titleFirst = <SearchResult>[
    for (final r in list)
      if (r.titleMatched) r,
    for (final r in list)
      if (!r.titleMatched) r,
  ];
  return titleFirst;
}

SearchResult? _matchItem({
  required List<String> tokens,
  required SearchResultKind kind,
  required String id,
  required String titleAr,
  required String titleEn,
  String subtitleAr = '',
  String subtitleEn = '',
  required Iterable<String> extraSearchParts,
  required String route,
}) {
  final normTitle = normalizeSearchText('$titleAr $titleEn');
  final normBody = normalizeSearchText([titleAr, titleEn, subtitleAr, subtitleEn, ...extraSearchParts].join(' '));
  if (!matchesSearchTokens(normBody, tokens)) return null;
  return SearchResult(
    kind: kind,
    id: id,
    titleAr: titleAr,
    titleEn: titleEn,
    subtitleAr: subtitleAr,
    subtitleEn: subtitleEn,
    route: route,
    titleMatched: matchesSearchTokens(normTitle, tokens),
  );
}

/// Searches already-loaded public collections in memory and returns non-empty
/// groups ordered by section type, honoring [SiteSearchInput.features] toggles.
List<SearchResultGroup> searchSite(String query, SiteSearchInput input) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return const [];

  final f = input.features;
  final groups = <SearchResultGroup>[];
  void addGroup(SearchResultKind kind, List<SearchResult> items) {
    if (items.isNotEmpty) groups.add(SearchResultGroup(kind: kind, items: _orderByTitleMatch(items)));
  }

  // 1. Liturgies (only regular or active-season services; skip past one-offs).
  if (f.enabled(Sections.schedule)) {
    final activeSeasonKeys = {
      for (final s in input.seasons)
        if (s.active && s.key.isNotEmpty) s.key,
    };
    final nowInstant = input.now;
    final todayStart = nowInstant == null ? null : CairoTime.startOfDay(CairoTime.fromInstant(nowInstant));
    final hits = <SearchResult>[];
    for (final l in input.liturgies) {
      if (!l.visible) continue;
      if (l.seasonKey != null && l.seasonKey!.isNotEmpty && !activeSeasonKeys.contains(l.seasonKey)) continue;
      if (todayStart != null && l.date != null) {
        final cal = CairoTime.calendarDate(l.date!);
        if (CairoTime.at(cal.year, cal.month, cal.day).isBefore(todayStart)) continue;
      }
      final dayAr = l.date != null
          ? formatDate(CairoTime.calendarDate(l.date!), arabic: true)
          : weekdayName(l.weekday, arabic: true);
      final dayEn = l.date != null
          ? formatDate(CairoTime.calendarDate(l.date!), arabic: false)
          : weekdayName(l.weekday, arabic: false);
      final timeAr = formatRangeArabic(l.start, l.end);
      final timeEn = formatRangeLatin(l.start, l.end);
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.liturgy,
        id: l.id,
        titleAr: l.nameAr,
        titleEn: l.nameEn,
        subtitleAr: _joinParts([dayAr, timeAr, l.placeAr]),
        subtitleEn: _joinParts([dayEn, timeEn, l.placeEn]),
        extraSearchParts: [
          l.type,
          l.placeAr,
          l.placeEn,
          l.audienceAr,
          l.audienceEn,
          _programText(l.program),
          weekdayName(l.weekday, arabic: true),
          weekdayName(l.weekday, arabic: false),
        ],
        route: '/mass-schedule',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.liturgy, hits);
  }

  // 2. Meetings
  if (f.enabled(Sections.meetings)) {
    final hits = <SearchResult>[];
    for (final m in input.meetings) {
      if (!m.visible) continue;
      final dayAr = weekdayName(m.weekday, arabic: true);
      final dayEn = weekdayName(m.weekday, arabic: false);
      final timeAr = formatRangeArabic(m.start, m.end);
      final timeEn = formatRangeLatin(m.start, m.end);
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.meeting,
        id: m.id,
        titleAr: m.nameAr,
        titleEn: m.nameEn,
        subtitleAr: _joinParts([dayAr, timeAr, m.hallAr]),
        subtitleEn: _joinParts([dayEn, timeEn, m.hallEn]),
        extraSearchParts: [
          m.stage,
          m.hallAr,
          m.hallEn,
          m.notes,
          _programText(m.program),
          m.details.detailsAr,
          m.details.detailsEn,
          _extraFieldsText(m.details),
        ],
        route: m.details.detailsEnabled ? detailPathFor(DetailKind.meeting, m.id) : '/church-education',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.meeting, hits);
  }

  // 3. Activities
  if (f.enabled(Sections.activities)) {
    final hits = <SearchResult>[];
    for (final a in input.activities) {
      if (!a.visible) continue;
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.activity,
        id: a.id,
        titleAr: a.titleAr,
        titleEn: a.titleEn,
        subtitleAr: a.scheduleAr.isNotEmpty ? a.scheduleAr : a.ageRange,
        subtitleEn: a.scheduleEn.isNotEmpty ? a.scheduleEn : a.ageRange,
        extraSearchParts: [
          a.descAr,
          a.descEn,
          a.ageRange,
          a.category,
          a.details.detailsAr,
          a.details.detailsEn,
          _extraFieldsText(a.details),
        ],
        route: a.details.detailsEnabled ? detailPathFor(DetailKind.activity, a.id) : '/church-activities',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.activity, hits);
  }

  // 4. Facilities / Public services
  if (f.enabled(Sections.services)) {
    final hits = <SearchResult>[];
    for (final fac in input.facilities) {
      if (!fac.visible) continue;
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.facility,
        id: fac.id,
        titleAr: fac.nameAr,
        titleEn: fac.nameEn,
        subtitleAr: fac.hoursAr.isNotEmpty ? fac.hoursAr : fac.descAr,
        subtitleEn: fac.hoursEn.isNotEmpty ? fac.hoursEn : fac.descEn,
        extraSearchParts: [
          fac.descAr,
          fac.descEn,
          fac.hoursAr,
          fac.hoursEn,
          fac.type,
          fac.phone,
          fac.details.detailsAr,
          fac.details.detailsEn,
          _extraFieldsText(fac.details),
        ],
        route: fac.details.detailsEnabled ? detailPathFor(DetailKind.facility, fac.id) : '/public-services',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.facility, hits);
  }

  // 5. Priests (gated separately for serving vs departed)
  if (f.enabled(Sections.priests) || f.enabled(Sections.departedPriests)) {
    final hits = <SearchResult>[];
    for (final p in input.priests) {
      if (!p.visible) continue;
      final allowed = p.departed ? f.enabled(Sections.departedPriests) : f.enabled(Sections.priests);
      if (!allowed) continue;
      final rankAr = p.rank == 'hegumen' ? 'القمص' : 'القس';
      final rankEn = p.rank == 'hegumen' ? 'Hegumen' : 'Priest';
      final subAr = p.departed ? '$rankAr • متنيح' : rankAr;
      final subEn = p.departed ? '$rankEn • Departed' : rankEn;
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.priest,
        id: p.id,
        titleAr: p.name,
        titleEn: p.nameEn,
        subtitleAr: subAr,
        subtitleEn: subEn,
        extraSearchParts: [
          p.rank,
          p.status,
          p.bioAr,
          p.bioEn,
          p.details.detailsAr,
          p.details.detailsEn,
          _extraFieldsText(p.details),
        ],
        route: p.details.detailsEnabled ? detailPathFor(DetailKind.priest, p.id) : '/about',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.priest, hits);
  }

  // 6. Saints
  if (f.enabled(Sections.saints)) {
    final hits = <SearchResult>[];
    for (final s in input.saints) {
      if (!s.visible) continue;
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.saint,
        id: s.id,
        titleAr: s.nameAr,
        titleEn: s.nameEn,
        subtitleAr: s.feastCopticAr.isNotEmpty ? s.feastCopticAr : s.feastGregorianAr,
        subtitleEn: s.feastCopticEn.isNotEmpty ? s.feastCopticEn : s.feastGregorian,
        extraSearchParts: [
          s.bioAr,
          s.bioEn,
          s.feastCopticAr,
          s.feastCopticEn,
          s.feastGregorianAr,
          s.feastGregorian,
          s.details.detailsAr,
          s.details.detailsEn,
          _extraFieldsText(s.details),
        ],
        route: s.details.detailsEnabled ? detailPathFor(DetailKind.saint, s.id) : '/about',
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.saint, hits);
  }

  // 7. Milestones
  if (f.enabled(Sections.milestones)) {
    final hits = <SearchResult>[];
    final fallbackRoute = f.showAboutMilestones && f.routeEnabled('/about') ? '/about' : '/';
    for (final m in input.milestones) {
      if (!m.visible) continue;
      final yearStr = m.year != null ? '${m.year}' : '';
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.milestone,
        id: m.id,
        titleAr: m.titleAr,
        titleEn: m.titleEn,
        subtitleAr: yearStr.isNotEmpty ? toArabicDigits(yearStr) : '',
        subtitleEn: yearStr,
        extraSearchParts: [
          m.descAr,
          m.descEn,
          yearStr,
          m.details.detailsAr,
          m.details.detailsEn,
          _extraFieldsText(m.details),
        ],
        route: m.details.detailsEnabled ? detailPathFor(DetailKind.milestone, m.id) : fallbackRoute,
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.milestone, hits);
  }

  final pubPages = f.enabled(Sections.customPages) ? publicPages(input.pages) : const <CustomPage>[];
  final pubCats = f.enabled(Sections.customSections)
      ? publicNonEmptyCategories(input.categories, input.entries, pubPages)
      : const <CustomCategory>[];

  // 8. Custom sections & their entries
  if (f.enabled(Sections.customSections)) {
    final hits = <SearchResult>[];
    for (final c in pubCats) {
      final catHit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.customSection,
        id: 'cat-${c.id}',
        titleAr: c.nameAr,
        titleEn: c.nameEn,
        subtitleAr: c.introAr,
        subtitleEn: c.introEn,
        extraSearchParts: const [],
        route: c.path,
      );
      if (catHit != null) hits.add(catHit);

      for (final e in entriesOf(c.id, input.entries)) {
        final entryHit = _matchItem(
          tokens: tokens,
          kind: SearchResultKind.customSection,
          id: 'entry-${e.id}',
          titleAr: e.titleAr,
          titleEn: e.titleEn,
          subtitleAr: c.nameAr,
          subtitleEn: c.nameEn.isNotEmpty ? c.nameEn : c.nameAr,
          extraSearchParts: [
            e.descAr,
            e.descEn,
            e.contactPhone,
            e.externalLabelAr,
            e.externalLabelEn,
            c.nameAr,
            c.nameEn,
          ],
          route: c.path,
        );
        if (entryHit != null) hits.add(entryHit);
      }
    }
    addGroup(SearchResultKind.customSection, hits);
  }

  // 9. Custom pages
  if (f.enabled(Sections.customPages)) {
    final hits = <SearchResult>[];
    for (final p in pubPages) {
      final blockTexts = <String>[];
      for (final b in p.blocks) {
        if (b.isEmpty || !isPageBlockVisible(b, features: f, pages: pubPages, categories: pubCats)) continue;
        blockTexts.add(b.textAr.replaceAll(PageBlock.listSeparator, ' '));
        blockTexts.add(b.textEn.replaceAll(PageBlock.listSeparator, ' '));
        if (b.account.isNotEmpty) blockTexts.add(b.account);
        if (b.instapay.isNotEmpty) blockTexts.add(b.instapay);
        if (b.wallet.isNotEmpty) blockTexts.add(b.wallet);
      }
      final hit = _matchItem(
        tokens: tokens,
        kind: SearchResultKind.customPage,
        id: p.id,
        titleAr: p.titleAr,
        titleEn: p.titleEn,
        subtitleAr: p.subtitleAr,
        subtitleEn: p.subtitleEn,
        extraSearchParts: blockTexts,
        route: p.path,
      );
      if (hit != null) hits.add(hit);
    }
    addGroup(SearchResultKind.customPage, hits);
  }

  return groups;
}
