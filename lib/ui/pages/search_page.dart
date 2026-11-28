import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/site_search.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Strings only this deferred chunk uses (registered before it builds).
const Map<String, List<String>> searchPageStrings = {
  'searchHint': ['ابحث عن اجتماع أو خدمة أو صفحة…', 'Search for a meeting, service, or page…'],
  'searchEmptyHint': ['اكتب كلمة للبحث في محتوى الموقع المحمّل على جهازك.', 'Type a word to search the content already loaded on your device.'],
  'searchNoResults': ['لا توجد نتائج مطابقة.', 'No matching results.'],
  'searchKindLiturgy': ['القداسات والصلوات', 'Liturgies & services'],
  'searchKindMeeting': ['الاجتماعات', 'Meetings'],
  'searchKindActivity': ['الأنشطة', 'Activities'],
  'searchKindFacility': ['الخدمات', 'Services'],
  'searchKindPriest': ['الآباء الكهنة', 'Priests'],
  'searchKindSaint': ['الشفعاء', 'Patron saints'],
  'searchKindMilestone': ['المحطات', 'Milestones'],
  'searchKindSection': ['الأقسام', 'Sections'],
  'searchKindPage': ['الصفحات', 'Pages'],
  'searchClear': ['مسح', 'Clear'],
};

String searchKindLabel(BuildContext context, SearchResultKind kind) => context.tr(switch (kind) {
      SearchResultKind.liturgy => 'searchKindLiturgy',
      SearchResultKind.meeting => 'searchKindMeeting',
      SearchResultKind.activity => 'searchKindActivity',
      SearchResultKind.facility => 'searchKindFacility',
      SearchResultKind.priest => 'searchKindPriest',
      SearchResultKind.saint => 'searchKindSaint',
      SearchResultKind.milestone => 'searchKindMilestone',
      SearchResultKind.customSection => 'searchKindSection',
      SearchResultKind.customPage => 'searchKindPage',
    });

/// Client-side public site search over already-loaded collections (this file
/// is a deferred chunk, fetched only on `/search`).
class SearchPage extends ConsumerStatefulWidget {
  final String initialQuery;
  const SearchPage({super.key, this.initialQuery = ''});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  Timer? _debounce;
  late String _query;

  @override
  void initState() {
    super.initState();
    registerStrings(searchPageStrings);
    _query = widget.initialQuery;
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery && widget.initialQuery != _controller.text) {
      _debounce?.cancel();
      _controller.text = widget.initialQuery;
      _query = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String value, {required bool updateRoute}) {
    if (!mounted) return;
    setState(() => _query = value);
    if (!updateRoute) return;
    final trimmed = value.trim();
    final path = trimmed.isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(trimmed)}';
    final current = GoRouter.of(context).routeInformationProvider.value.uri;
    final target = Uri.parse(path);
    if (current.path == target.path && current.query == target.query) return;
    context.go(path);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _commit(value, updateRoute: true));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    _focus.requestFocus();
    _commit('', updateRoute: true);
  }

  SiteSearchInput _watchedInput() => SiteSearchInput(
        features: ref.watch(featuresProvider),
        now: ref.watch(nowProvider).value,
        liturgies: ref.watch(liturgiesProvider).value ?? const [],
        seasons: ref.watch(seasonsProvider).value ?? const [],
        meetings: ref.watch(meetingsProvider).value ?? const [],
        activities: ref.watch(activitiesProvider).value ?? const [],
        facilities: ref.watch(facilitiesProvider).value ?? const [],
        priests: ref.watch(priestsProvider).value ?? const [],
        saints: ref.watch(saintsProvider).value ?? const [],
        milestones: ref.watch(milestonesProvider).value ?? const [],
        categories: ref.watch(categoriesProvider).value ?? const [],
        entries: ref.watch(entriesProvider).value ?? const [],
        pages: ref.watch(customPagesProvider).value ?? const [],
      );

  @override
  Widget build(BuildContext context) {
    registerStrings(searchPageStrings);
    setDocumentRouteMeta(path: '/search', indexable: false);
    final q = _query.trim();
    final hasQuery = q.isNotEmpty;
    final groups = hasQuery ? searchSite(_query, _watchedInput()) : const <SearchResultGroup>[];

    return PageBody(
      header: PageHeader(title: context.tr('search'), icon: Icons.search_rounded),
      children: [
        TextField(
          key: const Key('site-search-field'),
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: context.tr('searchHint'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    key: const Key('site-search-clear'),
                    tooltip: context.tr('searchClear'),
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            _commit(v, updateRoute: true);
          },
        ),
        const SizedBox(height: 16),
        if (!hasQuery)
          Text(context.tr('searchEmptyHint'), style: TextStyle(color: context.pal.muted, height: 1.6))
        else if (groups.isEmpty)
          Text(
            context.tr('searchNoResults'),
            key: const Key('site-search-empty'),
            style: TextStyle(color: context.pal.muted, height: 1.6),
          )
        else
          for (final g in groups) ...[
            SectionTitle(searchKindLabel(context, g.kind), key: ValueKey('search-group-${g.kind.name}')),
            for (final r in g.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  key: ValueKey('search-hit-${r.kind.name}-${r.id}'),
                  minTileHeight: 48,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(context.pick(r.titleAr, r.titleEn), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: context.pick(r.subtitleAr, r.subtitleEn).trim().isEmpty
                      ? null
                      : Text(context.pick(r.subtitleAr, r.subtitleEn), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.pal.muted),
                  onTap: () => context.go(r.route),
                ),
              ),
          ],
      ],
    );
  }
}
