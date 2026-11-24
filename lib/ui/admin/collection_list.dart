import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/item_detail.dart';
import '../../domain/time_format.dart';
import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import 'admin_schema.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';
import 'doc_editor.dart';
import 'pending_delete.dart';
import 'screen_header.dart';

enum ListFilter { all, visible, hidden, unconfirmed }

enum PriestStatusFilter { all, serving, departed }

String priestStatus(Map<String, dynamic> data) {
  final s = data['status']?.toString() ?? '';
  return s.isEmpty ? 'serving' : s;
}

/// Sorted for display: orderable collections by `order`, others by
/// order/weekday then start time, then id.
List<AdminDoc> sortAdminDocs(CollectionDef def, List<AdminDoc> docs) {
  int? n(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
  final list = [...docs];
  list.sort((a, b) {
    final oa = n(a.data['order']) ?? (def.orderable ? 1 << 30 : n(a.data['weekday']) ?? 99);
    final ob = n(b.data['order']) ?? (def.orderable ? 1 << 30 : n(b.data['weekday']) ?? 99);
    if (oa != ob) return oa.compareTo(ob);
    final s = '${a.data['start'] ?? ''}'.compareTo('${b.data['start'] ?? ''}');
    return s != 0 ? s : a.id.compareTo(b.id);
  });
  return list;
}

/// Docs that match the screen filter, the list filter, optional priest status filter, and the search text.
List<AdminDoc> filterAdminDocs(
  CollectionDef def,
  List<AdminDoc> docs, {
  String query = '',
  ListFilter filter = ListFilter.all,
  PriestStatusFilter statusFilter = PriestStatusFilter.all,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final d in docs)
      if (def.matches(d.data) &&
          (def.name != 'priests' ||
              statusFilter == PriestStatusFilter.all ||
              priestStatus(d.data) == statusFilter.name) &&
          switch (filter) {
            ListFilter.all => true,
            ListFilter.visible => d.data['visible'] != false,
            ListFilter.hidden => d.data['visible'] == false,
            ListFilter.unconfirmed => d.data['sample'] == true,
          } &&
          (q.isEmpty || searchableText(d.data).contains(q) || d.id.toLowerCase().contains(q)))
        d,
  ];
}

/// Slugs currently reserved by other documents in the same collection
/// (includes hidden docs and locally undoable soft-deletes; ignores
/// non-pending soft-deletes and trims whitespace).
@visibleForTesting
Set<String> collectTakenSlugs(
  Iterable<AdminDoc> docs, {
  String? excludeId,
  bool Function(String id)? isPendingDelete,
}) =>
    {
      for (final x in docs)
        if (x.id != excludeId &&
            (!isSoftDeleted(x.data) || (isPendingDelete?.call(x.id) ?? false)) &&
            x.data['slug'] is String)
          if ((x.data['slug'] as String).trim() case final slug when slug.isNotEmpty) slug,
    };

class CollectionListScreen extends StatefulWidget {
  final AdminBackend repo;
  final CollectionDef def;
  final bool showHeader;
  const CollectionListScreen({super.key, required this.repo, required this.def, this.showHeader = true});

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _search = TextEditingController();
  final _pendingDelete = PendingDelete();
  final _pendingEntries = <String, ({AdminBackend repo, String collection, String title})>{};
  final Map<String, Future<bool>> _inFlightDeleteWrites = {};
  final Map<String, int> _deleteGen = {};
  final Set<String> _restoringIds = {};
  final Set<String> _purging = {};
  final Set<String> _togglingVisibility = {};
  final Map<String, bool> _optimisticVisible = {};
  final Map<String, bool> _latestStreamVisible = {};
  final Map<String, int> _settledAtStreamSeq = {};
  final Map<String, int> _streamSeqByCollection = {};
  int _screenEpoch = 0;
  ListFilter _filter = ListFilter.all;
  PriestStatusFilter _priestFilter = PriestStatusFilter.all;
  late Stream<({int seq, List<AdminDoc> docs})> _stream =
      _trackStream(widget.def.name, widget.repo.watch(widget.def.name));
  late Stream<({int seq, List<AdminDoc> docs})>? _entriesStream =
      widget.def.name == 'categories' ? _trackStream('entries', widget.repo.watch('entries')) : null;
  late Stream<({int seq, List<AdminDoc> docs})>? _pagesStream =
      widget.def.name == 'categories' ? _trackStream('pages', widget.repo.watch('pages')) : null;
  StreamSubscription<AdminDoc?>? _featuresSub;
  bool _englishEnabled = true;
  bool _openingEditor = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoSnackBarController;
  int _undoSnackBarCount = 0;
  bool _undoBarUsesMultiAction = false;
  final ValueNotifier<({int count, String title})?> _undoBarState = ValueNotifier(null);
  Timer? _undoSnackBarTimer;
  Timer? _fabCooldownTimer;
  final _FabSnackHeightTracker _fabHeightTracker = _FabSnackHeightTracker();
  final List<SnackBar> _deferredErrorSnacks = [];

  /// The list as last shown (slug uniqueness checks in the editor).
  List<AdminDoc> _lastDocs = const [];

  /// Latest `pages` snapshot on the categories screen (reused by `_openEditor`
  /// for `takenSlugs` and link targets without spawning a redundant read).
  List<AdminDoc>? _lastPages;

  @override
  void initState() {
    super.initState();
    _bindFeatures();
  }

  void _bindFeatures() {
    _featuresSub?.cancel();
    _englishEnabled = true;
    _featuresSub = widget.repo.watchDoc('settings/features').listen(
      (d) {
        if (!mounted) return;
        final next = FeatureSettings.fromMap(d?.data).englishEnabled;
        if (next != _englishEnabled) setState(() => _englishEnabled = next);
      },
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(covariant CollectionListScreen old) {
    super.didUpdateWidget(old);
    if (old.def.name != widget.def.name || old.repo != widget.repo) {
      _screenEpoch++;
      _lastDocs = const [];
      _lastPages = null;
      _restoringIds.clear();
      _togglingVisibility.clear();
      _optimisticVisible.clear();
      _latestStreamVisible.clear();
      _settledAtStreamSeq.clear();
      _streamSeqByCollection.clear();
      _deferredErrorSnacks.clear();
      _stream = _trackStream(widget.def.name, widget.repo.watch(widget.def.name));
      _entriesStream =
          widget.def.name == 'categories' ? _trackStream('entries', widget.repo.watch('entries')) : null;
      _pagesStream =
          widget.def.name == 'categories' ? _trackStream('pages', widget.repo.watch('pages')) : null;
    }
    if (old.repo != widget.repo) _bindFeatures();
    if (old.def.id != widget.def.id || old.def.name != widget.def.name) {
      _priestFilter = PriestStatusFilter.all;
    }
  }

  @override
  void dispose() {
    _undoSnackBarTimer?.cancel();
    _fabCooldownTimer?.cancel();
    _undoSnackBarController = null;
    _undoBarState.dispose();
    _deferredErrorSnacks.clear();
    _featuresSub?.cancel();
    _pendingDelete.dispose();
    _pendingEntries.clear();
    _inFlightDeleteWrites.clear();
    _deleteGen.clear();
    _restoringIds.clear();
    _search.dispose();
    super.dispose();
  }

  bool get _isFabHeldElevated => _undoSnackBarController != null || _fabCooldownTimer != null;

  bool _isVisibleDoc(AdminDoc d) =>
      (!isSoftDeleted(d.data) || _restoringIds.contains(d.id)) && !_pendingDelete.isPending(d.id);

  void _startFabCooldown() {
    _fabCooldownTimer?.cancel();
    _fabCooldownTimer = Timer(const Duration(milliseconds: 650), () {
      _fabCooldownTimer = null;
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _cancelFabCooldown() {
    _fabCooldownTimer?.cancel();
    _fabCooldownTimer = null;
  }

  CollectionDef get def => widget.def;

  String _title(AdminDoc d, [CollectionDef? targetDef]) {
    final activeDef = targetDef ?? def;
    for (final k in activeDef.titleKeys) {
      final v = d.data[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return d.id;
  }

  String _subtitle(BuildContext context, AdminDoc d, [CollectionDef? targetDef]) {
    final activeDef = targetDef ?? def;
    final parts = <String>[];
    final wd = d.data['weekday'];
    if (wd is int) parts.add(weekdayName(wd, arabic: context.isAr));
    final date = d.data['date'];
    if (date is DateTime) parts.add(formatDate(CairoTime.calendarDate(date), arabic: context.isAr));
    if (d.data['start'] != null && d.data['start'].toString().isNotEmpty) {
      parts.add(formatRangeLatin(d.data['start'].toString(), (d.data['end'] ?? '').toString()));
    }
    for (final k in ['seasonKey', 'stage', 'category', 'type', 'specialtyEn']) {
      final v = d.data[k];
      if (v is String && v.isNotEmpty && !activeDef.titleKeys.contains(k)) parts.add(choiceLabel(context, v));
    }
    if (d.data['active'] == false) parts.add('⛔ ${context.tr('inactive')}');
    for (final k in ['startsAt', 'endsAt']) {
      final v = d.data[k];
      if (v is DateTime) parts.add(fmtDateTime(v));
    }
    return parts.join(' • ');
  }

  ScaffoldMessengerState? get _messenger => _messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: context.pal.background,
        floatingActionButtonLocation: _UndoClearFabLocation(
          holdElevated: _isFabHeldElevated,
          tracker: _fabHeightTracker,
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'add-${def.id}',
          onPressed: () {
            if (def.name == 'pages') {
              _openNewPageChooser(context);
            } else {
              final extra = def.name == 'priests' && _priestFilter != PriestStatusFilter.all
                  ? <String, Object?>{'status': _priestFilter.name}
                  : const <String, Object?>{};
              _openEditor(context, null, extraDefaults: extra);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(context.tr('add')),
        ),
        body: Stack(
          children: [
            StreamBuilder<({int seq, List<AdminDoc> docs})>(
        // A new stream (another backend) gets a fresh StreamBuilder: a reused
        // one keeps the old backend's list while the new one loads.
        key: ObjectKey(_stream),
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rawSnapshot = snap.data!;
          _syncStreamVisibility(def.name, rawSnapshot);
          final all = sortAdminDocs(
              def,
              rawSnapshot.docs
                  .where((d) => def.matches(d.data))
                  .toList());
          _lastDocs = all
              .where((d) => !isSoftDeleted(d.data) || _pendingDelete.isPending(d.id) || _restoringIds.contains(d.id))
              .toList();
          final visible = all.where(_isVisibleDoc).toList();
          final docs = filterAdminDocs(
            def,
            visible,
            query: _search.text,
            filter: _filter,
            statusFilter: def.name == 'priests' ? _priestFilter : PriestStatusFilter.all,
          );
          _checkLazyPurge(rawSnapshot.docs, def);

          if (def.name == 'categories' && _entriesStream != null && _pagesStream != null) {
            return StreamBuilder<({int seq, List<AdminDoc> docs})>(
              key: ObjectKey(_entriesStream),
              stream: _entriesStream,
              builder: (context, entrySnap) {
                if (entrySnap.hasError) {
                  return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${entrySnap.error}')));
                }
                if (!entrySnap.hasData) return const Center(child: CircularProgressIndicator());
                return StreamBuilder<({int seq, List<AdminDoc> docs})>(
                  key: ObjectKey(_pagesStream),
                  stream: _pagesStream,
                  builder: (context, pageSnap) {
                    if (pageSnap.hasError) {
                      return Center(
                          child: Padding(padding: const EdgeInsets.all(24), child: Text('${pageSnap.error}')));
                    }
                    if (!pageSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final entriesDef = collectionById('entries')!;
                    final pagesDef = collectionById('pages')!;
                    final entriesSnapshot = entrySnap.data!;
                    final rawEntries = entriesSnapshot.docs;
                    _syncStreamVisibility(entriesDef.name, entriesSnapshot);
                    _checkLazyPurge(rawEntries, entriesDef);
                    final pagesSnapshot = pageSnap.data!;
                    final rawPages = pagesSnapshot.docs;
                    _lastPages = rawPages;
                    _syncStreamVisibility(pagesDef.name, pagesSnapshot);
                    _checkLazyPurge(rawPages, pagesDef);
                    final unsoftEntries = rawEntries.where(_isVisibleDoc).toList();
                    final unsoftPages = rawPages.where(_isVisibleDoc).toList();

                    final domainEntries = [
                      for (final e in unsoftEntries) CategoryEntry.fromMap(e.id, e.data),
                    ];
                    final domainPages = [
                      for (final p in unsoftPages) CustomPage.fromMap(p.id, p.data),
                    ];

                    final visibleEntries = sortAdminDocs(entriesDef, unsoftEntries);
                    final filteredEntries =
                        filterAdminDocs(entriesDef, visibleEntries, query: _search.text, filter: _filter);

                    final rawSectionPages = [
                      for (final p in unsoftPages)
                        if (CustomPage.fromMap(p.id, p.data).effectivePlacement == PagePlacements.section)
                          p,
                    ];
                    final visibleSectionPages = sortAdminDocs(pagesDef, rawSectionPages);
                    final filteredSectionPages =
                        filterAdminDocs(pagesDef, visibleSectionPages, query: _search.text, filter: _filter);

                    final hasFilter = _search.text.trim().isNotEmpty || _filter != ListFilter.all;
                    final matchingCatIds = {for (final c in docs) c.id};
                    final allCatIds = {for (final c in visible) c.id};

                    final allEntriesByCat = <String, List<AdminDoc>>{};
                    for (final e in visibleEntries) {
                      final cid = '${e.data['categoryId'] ?? ''}';
                      if (allCatIds.contains(cid)) {
                        (allEntriesByCat[cid] ??= []).add(e);
                      }
                    }
                    final entriesByCat = <String, List<AdminDoc>>{};
                    final unassigned = <AdminDoc>[];
                    for (final e in filteredEntries) {
                      final cid = '${e.data['categoryId'] ?? ''}';
                      if (allCatIds.contains(cid)) {
                        (entriesByCat[cid] ??= []).add(e);
                      } else {
                        unassigned.add(e);
                      }
                    }

                    final allSectionPagesByCat = <String, List<AdminDoc>>{};
                    for (final p in visibleSectionPages) {
                      final cid = '${p.data['categoryId'] ?? ''}';
                      if (allCatIds.contains(cid) || BuiltInSections.isBuiltIn(cid)) {
                        (allSectionPagesByCat[cid] ??= []).add(p);
                      }
                    }
                    final sectionPagesByCat = <String, List<AdminDoc>>{};
                    for (final p in filteredSectionPages) {
                      final cid = '${p.data['categoryId'] ?? ''}';
                      if (allCatIds.contains(cid) || BuiltInSections.isBuiltIn(cid)) {
                        (sectionPagesByCat[cid] ??= []).add(p);
                      }
                    }

                    final emptyCatIds = <String>{
                      for (final c in visible)
                        if (!isCategoryNonEmpty(CustomCategory.fromMap(c.id, c.data), domainEntries, domainPages))
                          c.id,
                    };
                    final shownCats = hasFilter
                        ? [
                            for (final c in visible)
                              if (matchingCatIds.contains(c.id) ||
                                  (entriesByCat[c.id]?.isNotEmpty ?? false) ||
                                  (sectionPagesByCat[c.id]?.isNotEmpty ?? false))
                                c,
                          ]
                        : visible;
                    final q = _search.text.trim().toLowerCase();
                    final shownBuiltIns = [
                      for (final b in BuiltInSections.all)
                        if ((allSectionPagesByCat[b.id]?.isNotEmpty ?? false) &&
                            (!hasFilter ||
                                (sectionPagesByCat[b.id]?.isNotEmpty ?? false) ||
                                (q.isNotEmpty &&
                                    (_filter == ListFilter.all || _filter == ListFilter.visible) &&
                                    (b.nameAr.toLowerCase().contains(q) ||
                                        b.nameEn.toLowerCase().contains(q) ||
                                        b.id.toLowerCase().contains(q) ||
                                        b.slug.toLowerCase().contains(q)))))
                          b,
                    ];
                    final builtInWithPages = BuiltInSections.all
                        .where((b) => allSectionPagesByCat[b.id]?.isNotEmpty ?? false)
                        .length;
                    final hasAnyBuiltInPages = builtInWithPages > 0;
                    final canReorder =
                        def.orderable && !hasFilter && shownCats.length > 1;
                    return CustomScrollView(slivers: [
                      if (widget.showHeader)
                        SliverToBoxAdapter(
                          child: AdminScreenHeader(
                            title: context.pick(def.labelAr, def.labelEn),
                            help: context.pick(def.helpAr, def.helpEn),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: _toolbar(
                          context,
                          visible.length + builtInWithPages,
                          shownCats.length + shownBuiltIns.length,
                          canReorder,
                          showUnconfirmed: entriesDef.hasSample,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _categoriesBody(
                          context,
                          entriesDef: entriesDef,
                          pagesDef: pagesDef,
                          allVisibleCats: visible,
                          shownCats: shownCats,
                          entriesByCat: entriesByCat,
                          allEntriesByCat: allEntriesByCat,
                          sectionPagesByCat: sectionPagesByCat,
                          allSectionPagesByCat: allSectionPagesByCat,
                          shownBuiltIns: shownBuiltIns,
                          hasAnyBuiltInPages: hasAnyBuiltInPages,
                          hasFilter: hasFilter,
                          unassigned: unassigned,
                          canReorder: canReorder,
                          emptyCatIds: emptyCatIds,
                        ),
                      ),
                    ]);
                  },
                );
              },
            );
          }

          final canReorder = def.orderable && _search.text.trim().isEmpty && _filter == ListFilter.all && docs.length > 1;
          final bottomPad = _listBottomPadding(context);
          return CustomScrollView(slivers: [
            if (widget.showHeader)
              SliverToBoxAdapter(
                child: AdminScreenHeader(
                  title: context.pick(def.labelAr, def.labelEn),
                  help: context.pick(def.helpAr, def.helpEn),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                ),
              ),
            SliverToBoxAdapter(child: _toolbar(context, visible.length, docs.length, canReorder)),
            if (docs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 24, 12, bottomPad),
                    child: Text(context.tr(visible.isEmpty ? 'noItems' : 'noMatches')),
                  ),
                ),
              )
            else if (canReorder)
              SliverToBoxAdapter(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPad),
                  itemCount: docs.length,
                  onReorderItem: (from, to) => _reorder(context, docs, from, to),
                  itemBuilder: (context, i) => _tile(context, docs[i], dragIndex: i, docs: docs),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPad),
                sliver: SliverList.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _tile(context, docs[i]),
                ),
              ),
          ]);
        },
      ),
            if (_fabCooldownTimer != null && _undoSnackBarController == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _fabHeightTracker.lastUndoSnackHeight,
                child: GestureDetector(
                  key: const Key('undo-vacated-tap-shield'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: () {},
                ),
              ),
          ],
        ),
    ),
    );
  }

  Widget _toolbar(BuildContext context, int total, int shown, bool canReorder, {bool showUnconfirmed = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (def.noteAr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.pick(def.noteAr, def.noteEn),
                key: const Key('admin-collectionNote'),
                style: TextStyle(color: context.pal.ink, fontSize: 15, height: 1.6)),
          ),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('admin-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('searchHint'),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('clearSearch'),
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // The public page that shows this collection (CollectionDef.publicPath).
          IconButton(
            key: const Key('admin-openOnSite'),
            tooltip: context.tr('openOnSite'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => _openOnSite(context),
          ),
        ]),
        if (def.name == 'priests') ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in PriestStatusFilter.values)
              ChoiceChip(
                key: ValueKey('priestFilter-${s.name}'),
                label: Text(switch (s) {
                  PriestStatusFilter.all => context.tr('filter_all'),
                  PriestStatusFilter.serving => context.tr('opt_serving'),
                  PriestStatusFilter.departed => context.tr('opt_departed'),
                }),
                selected: _priestFilter == s,
                showCheckmark: false,
                labelStyle: TextStyle(color: _priestFilter == s ? context.pal.onBar : context.pal.primary),
                onSelected: (_) => setState(() => _priestFilter = s),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in ListFilter.values)
            if ((f != ListFilter.unconfirmed || def.hasSample || showUnconfirmed) &&
                ((f != ListFilter.visible && f != ListFilter.hidden) || def.hasVisible))
              ChoiceChip(
                label: Text(context.tr('filter_${f.name}')),
                selected: _filter == f,
                showCheckmark: false,
                labelStyle: TextStyle(color: _filter == f ? context.pal.onBar : context.pal.primary),
                onSelected: (_) => setState(() => _filter = f),
              ),
          Text('  ${context.tr('showingCount', {'n': '$shown', 't': '$total'})}',
              style: TextStyle(color: context.pal.muted, fontSize: 12)),
          if (canReorder)
            Text('  ↕ ${context.tr('dragToReorder')}', style: TextStyle(color: context.pal.muted, fontSize: 12)),
        ]),
      ]),
    );
  }

  /// Opens [CollectionDef.publicPath] in a new tab on web (the dashboard stays
  /// open), in the dashboard's language; elsewhere navigates to it in the app.
  void _openOnSite(BuildContext context, [String? path]) {
    path ??= publicPathFor(def, english: !context.isAr);
    if (kIsWeb) {
      openUrl(Uri.base.resolve(path).toString());
    } else {
      context.go(path);
    }
  }

  Widget _categoriesBody(
    BuildContext context, {
    required CollectionDef entriesDef,
    required CollectionDef pagesDef,
    required List<AdminDoc> allVisibleCats,
    required List<AdminDoc> shownCats,
    required Map<String, List<AdminDoc>> entriesByCat,
    required Map<String, List<AdminDoc>> allEntriesByCat,
    required Map<String, List<AdminDoc>> sectionPagesByCat,
    required Map<String, List<AdminDoc>> allSectionPagesByCat,
    required List<CustomCategory> shownBuiltIns,
    required bool hasAnyBuiltInPages,
    required bool hasFilter,
    required List<AdminDoc> unassigned,
    required bool canReorder,
    Set<String> emptyCatIds = const {},
  }) {
    if (allVisibleCats.isEmpty && unassigned.isEmpty && !hasAnyBuiltInPages) {
      return Center(
        key: const Key('emptyCategories'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_open_rounded, size: 48, color: context.pal.muted),
            const SizedBox(height: 12),
            Text(context.tr('emptySectionsPrompt'),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('addFirstSectionBtn'),
              onPressed: () => _openEditor(context, null),
              icon: const Icon(Icons.add),
              label: Text(context.tr('addFirstSection')),
            ),
          ]),
        ),
      );
    }
    if (shownCats.isEmpty && unassigned.isEmpty && shownBuiltIns.isEmpty) {
      return Center(child: Text(context.tr('noMatches')));
    }
    final bottomPad = _listBottomPadding(context);
    if (canReorder && unassigned.isEmpty && shownBuiltIns.isEmpty) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPad),
        itemCount: shownCats.length,
        onReorderItem: (from, to) => _reorder(context, shownCats, from, to),
        itemBuilder: (context, i) => _categoryTile(
          context,
          shownCats[i],
          entriesDef: entriesDef,
          pagesDef: pagesDef,
          entries: entriesByCat[shownCats[i].id] ?? const [],
          sectionPages: sectionPagesByCat[shownCats[i].id] ?? const [],
          hasAnyEntries: allEntriesByCat[shownCats[i].id]?.isNotEmpty ?? false,
          hasAnyPages: allSectionPagesByCat[shownCats[i].id]?.isNotEmpty ?? false,
          hasFilter: hasFilter,
          dragIndex: i,
          docs: shownCats,
          isEmptyHidden: emptyCatIds.contains(shownCats[i].id),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPad),
      children: [
        if (allVisibleCats.isEmpty && !hasAnyBuiltInPages)
          Card(
            key: const Key('emptyCategories'),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(context.tr('emptySectionsPrompt'),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('addFirstSectionBtn'),
                  onPressed: () => _openEditor(context, null),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('addFirstSection')),
                ),
              ]),
            ),
          ),
        if (canReorder)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: shownCats.length,
            onReorderItem: (from, to) => _reorder(context, shownCats, from, to),
            itemBuilder: (context, i) => _categoryTile(
              context,
              shownCats[i],
              entriesDef: entriesDef,
              pagesDef: pagesDef,
              entries: entriesByCat[shownCats[i].id] ?? const [],
              sectionPages: sectionPagesByCat[shownCats[i].id] ?? const [],
              hasAnyEntries: allEntriesByCat[shownCats[i].id]?.isNotEmpty ?? false,
              hasAnyPages: allSectionPagesByCat[shownCats[i].id]?.isNotEmpty ?? false,
              hasFilter: hasFilter,
              dragIndex: i,
              docs: shownCats,
              isEmptyHidden: emptyCatIds.contains(shownCats[i].id),
            ),
          )
        else
          for (final c in shownCats)
            _categoryTile(
              context,
              c,
              entriesDef: entriesDef,
              pagesDef: pagesDef,
              entries: entriesByCat[c.id] ?? const [],
              sectionPages: sectionPagesByCat[c.id] ?? const [],
              hasAnyEntries: allEntriesByCat[c.id]?.isNotEmpty ?? false,
              hasAnyPages: allSectionPagesByCat[c.id]?.isNotEmpty ?? false,
              hasFilter: hasFilter,
              isEmptyHidden: emptyCatIds.contains(c.id),
            ),
        for (final b in shownBuiltIns)
          _builtInCategoryTile(
            context,
            b,
            pagesDef: pagesDef,
            sectionPages: sectionPagesByCat[b.id] ?? const [],
            hasAnyPages: allSectionPagesByCat[b.id]?.isNotEmpty ?? false,
            hasFilter: hasFilter,
          ),
        if (unassigned.isNotEmpty) _unassignedCard(context, entriesDef, unassigned),
      ],
    );
  }

  Widget _namedDeleteButton(BuildContext context, {required Key key, required VoidCallback onPressed}) => Tooltip(
        message: context.tr('delete'),
        child: TextButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(Icons.delete_outline, color: context.pal.alert, size: 18),
          label: Text(context.tr('delete'), style: TextStyle(color: context.pal.alert)),
        ),
      );

  Widget _openOnSiteButton(BuildContext context, AdminDoc d, String itemPath) => Tooltip(
        message: context.tr('openItemOnSite'),
        child: TextButton.icon(
          key: ValueKey('openItem-${d.id}'),
          onPressed: () => _openOnSite(context, itemPath),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(context.tr('openOnSite')),
        ),
      );

  String _visKey(String collection, String id) => '$collection:$id';

  Stream<({int seq, List<AdminDoc> docs})> _trackStream(
    String collection,
    Stream<List<AdminDoc>> source,
  ) {
    final epoch = _screenEpoch;
    return source.map((docs) {
      if (epoch != _screenEpoch) return (seq: 0, docs: docs);
      final seq = (_streamSeqByCollection[collection] ?? 0) + 1;
      _streamSeqByCollection[collection] = seq;
      return (seq: seq, docs: docs);
    });
  }

  void _syncStreamVisibility(String collection, ({int seq, List<AdminDoc> docs}) snapshot) {
    final seq = snapshot.seq;
    for (final d in snapshot.docs) {
      final k = _visKey(collection, d.id);
      final streamVisible = d.data['visible'] != false;
      _latestStreamVisible[k] = streamVisible;
      final settledSeq = _settledAtStreamSeq[k];
      final hasNewerSnapshot = settledSeq != null && seq > settledSeq;
      if (!_togglingVisibility.contains(k) &&
          _optimisticVisible.containsKey(k) &&
          (hasNewerSnapshot || _optimisticVisible[k] == streamVisible)) {
        _optimisticVisible.remove(k);
        _settledAtStreamSeq.remove(k);
      }
    }
  }

  void _showSnack(ScaffoldMessengerState? messenger, SnackBar bar, {bool deferWhileUndo = false}) {
    if (!mounted || messenger == null || !messenger.mounted) return;
    if (deferWhileUndo && _undoSnackBarController != null) {
      _deferredErrorSnacks.add(bar);
      return;
    }
    messenger.showSnackBar(bar);
  }

  void _flushDeferredErrors(ScaffoldMessengerState? messenger) {
    if (!mounted || messenger == null || !messenger.mounted) return;
    if (_undoSnackBarController != null || _deferredErrorSnacks.isEmpty) return;
    for (final bar in _deferredErrorSnacks) {
      messenger.showSnackBar(bar);
    }
    _deferredErrorSnacks.clear();
  }

  bool _effectiveHidden(AdminDoc d, {CollectionDef? targetDef}) {
    final k = _visKey((targetDef ?? def).name, d.id);
    final streamVisible = d.data['visible'] != false;
    _latestStreamVisible[k] = streamVisible;
    final opt = _optimisticVisible[k];
    if (opt != null) {
      if (!_togglingVisibility.contains(k) && streamVisible == opt) {
        _optimisticVisible.remove(k);
        return !streamVisible;
      }
      return !opt;
    }
    return !streamVisible;
  }

  /// Renders an admin row whose main body opens [onTap] (`DocEditor`), keeping [trailing]
  /// (visibility toggle / desktop reorder buttons / duplicate) outside `ListTile`'s `InkWell`
  /// and pinned to the top-end corner so rapid taps on or near the eye can never leak to [onTap].
  Widget _splitActionRow({
    Key? tileKey,
    bool dense = false,
    EdgeInsetsGeometry? contentPadding,
    Widget? leading,
    required Widget title,
    Widget? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    double trailingEndPadding = 8,
  }) {
    final effectivePadding = contentPadding ??
        EdgeInsetsDirectional.only(
          start: 16,
          end: trailing == null ? 16 : 4,
        );
    final tile = ListTile(
      key: tileKey,
      dense: dense,
      contentPadding: effectivePadding,
      leading: leading,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
    if (trailing == null) return tile;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: tile),
        Padding(
          padding: EdgeInsetsDirectional.only(top: dense ? 2 : 4, end: trailingEndPadding),
          child: trailing,
        ),
      ],
    );
  }

  double _listBottomPadding(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.5);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Extended FAB starts at 56 px + 16 px Scaffold margin and grows with text scale;
    // keep the last card's footer actions completely clear above it.
    return 104 + (scale - 1.0) * 32 + safeBottom;
  }

  Widget _visibilityButton(
    BuildContext context,
    AdminDoc d, {
    required Key key,
    CollectionDef? targetDef,
  }) {
    final activeDef = targetDef ?? def;
    final k = _visKey(activeDef.name, d.id);
    final saving = _togglingVisibility.contains(k);
    final hidden = _effectiveHidden(d, targetDef: activeDef);
    final label = saving ? context.tr('savingVisibility') : context.tr(hidden ? 'show' : 'hide');
    // Keep a constant >=48x48 hit target and always-active TapGestureRecognizer
    // so rapid taps (even if a write completes mid-press) never leak to ListTile.onTap.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {},
        child: IconButton(
          key: key,
          tooltip: label,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          onPressed: saving ? null : () => _setVisible(context, d, hidden, targetDef: activeDef),
          icon: SizedBox.square(
            dimension: 24,
            child: Center(
              child: saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.primary),
                    )
                  : Icon(
                      hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: hidden ? context.pal.muted : context.pal.success,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryTile(
    BuildContext context,
    AdminDoc d, {
    required CollectionDef entriesDef,
    required CollectionDef pagesDef,
    required List<AdminDoc> entries,
    required List<AdminDoc> sectionPages,
    bool hasAnyEntries = false,
    bool hasAnyPages = false,
    bool hasFilter = false,
    int? dragIndex,
    List<AdminDoc>? docs,
    bool isEmptyHidden = false,
  }) {
    final hidden = _effectiveHidden(d);
    final updated = d.updatedAt;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final itemPath = itemPublicPathFor(def, d.id, d.data, english: !context.isAr);
    final moves = <Widget>[
      if (dragIndex != null && docs != null) ...[
        IconButton(
          key: ValueKey('moveUp-${d.id}'),
          tooltip: context.tr('moveUp'),
          icon: const Icon(Icons.arrow_upward),
          onPressed: dragIndex == 0 ? null : () => _reorder(context, docs, dragIndex, dragIndex - 1),
        ),
        IconButton(
          key: ValueKey('moveDown-${d.id}'),
          tooltip: context.tr('moveDown'),
          icon: const Icon(Icons.arrow_downward),
          onPressed: dragIndex == docs.length - 1 ? null : () => _reorder(context, docs, dragIndex, dragIndex + 1),
        ),
      ],
    ];
    final openItem = itemPath == null ? null : _openOnSiteButton(context, d, itemPath);
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 10),
      color: hidden ? context.pal.surfaceAlt.withValues(alpha: 0.7) : context.pal.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _splitActionRow(
          leading: dragIndex != null
              ? ReorderableDragStartListener(index: dragIndex, child: const Icon(Icons.drag_indicator))
              : null,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(_title(d),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: hidden ? context.pal.muted : context.pal.ink)),
              _Tag(context.tr(hidden ? 'hidden' : 'visibleTag'),
                  hidden ? context.pal.muted : context.pal.success),
              if (isEmptyHidden)
                _Tag(context.tr('emptyHiddenFromVisitors'), context.pal.muted),
            ],
          ),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (updated != null)
              Text(
                context.tr('updatedBy', {'t': fmtDateTime(updated), 'u': d.updatedBy.isEmpty ? '—' : d.updatedBy}),
                style: TextStyle(fontSize: 11, color: context.pal.muted),
              ),
            if (narrow && moves.isNotEmpty) Wrap(children: moves),
          ]),
          onTap: () => _openEditor(context, d),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!narrow) ...moves,
            _visibilityButton(context, d, key: ValueKey('visibility-${d.id}')),
          ]),
        ),
        const Divider(height: 1),
        if (entries.isEmpty && sectionPages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              context.tr(hasFilter && (hasAnyEntries || hasAnyPages) ? 'noMatches' : 'sectionEmptyItems'),
              style: TextStyle(color: context.pal.muted, fontSize: 13),
            ),
          )
        else ...[
          for (final e in entries) _entryRow(context, entriesDef, e),
          for (final p in sectionPages) _sectionPageRow(context, pagesDef, p),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: ValueKey('addEntryIn-${d.id}'),
                onPressed: () => _openEditor(context, null, targetDef: entriesDef, extraDefaults: {'categoryId': d.id}),
                icon: const Icon(Icons.add),
                label: Text(context.tr('addSectionItem')),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?openItem,
                  _namedDeleteButton(
                    context,
                    key: ValueKey('delete-${d.id}'),
                    onPressed: () => _deleteCategory(d),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _builtInCategoryTile(
    BuildContext context,
    CustomCategory b, {
    required CollectionDef pagesDef,
    required List<AdminDoc> sectionPages,
    bool hasAnyPages = false,
    bool hasFilter = false,
  }) {
    return Card(
      key: ValueKey(b.id),
      margin: const EdgeInsets.only(bottom: 10),
      color: context.pal.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(context.pick(b.nameAr, b.nameEn),
                  style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.ink)),
              _Tag(context.tr('builtInSectionTag'), context.pal.primary),
            ],
          ),
        ),
        const Divider(height: 1),
        if (sectionPages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              context.tr(hasFilter && hasAnyPages ? 'noMatches' : 'sectionEmptyItems'),
              style: TextStyle(color: context.pal.muted, fontSize: 13),
            ),
          )
        else
          for (final p in sectionPages) _sectionPageRow(context, pagesDef, p),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _openOnSiteButton(
              context,
              AdminDoc(b.id, const {}),
              !context.isAr ? '/${b.slug}?lang=en' : '/${b.slug}',
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sectionPageRow(BuildContext context, CollectionDef pagesDef, AdminDoc p) {
    final hidden = _effectiveHidden(p, targetDef: pagesDef);
    final sub = _subtitle(context, p, pagesDef);
    return _splitActionRow(
      tileKey: Key('sectionPageRow-${p.id}'),
      dense: true,
      contentPadding: const EdgeInsetsDirectional.only(start: 20, end: 4),
      leading: Icon(Icons.description_outlined, size: 18, color: context.pal.muted),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Text(_title(p, pagesDef),
              style: TextStyle(fontWeight: FontWeight.w600, color: hidden ? context.pal.muted : context.pal.ink)),
          _Tag(context.tr('pageTag'), context.pal.primary),
          _Tag(context.tr(hidden ? 'hidden' : 'visibleTag'),
              hidden ? context.pal.muted : context.pal.success),
        ],
      ),
      subtitle: sub.isEmpty ? null : Text(sub),
      onTap: () => _openEditor(context, p, targetDef: pagesDef),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('duplicateSectionPage-${p.id}'),
            tooltip: context.tr('duplicate'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _duplicatePage(context, p, pagesDef: pagesDef),
          ),
          _visibilityButton(context, p, key: ValueKey('visibilitySectionPage-${p.id}'), targetDef: pagesDef),
        ],
      ),
    );
  }

  Widget _unassignedCard(BuildContext context, CollectionDef entriesDef, List<AdminDoc> entries) {
    return Card(
      key: const Key('unassignedItemsCard'),
      margin: const EdgeInsets.only(bottom: 10),
      color: context.pal.surfaceAlt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(context.tr('unassignedItems'),
              style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.primary)),
        ),
        const Divider(height: 1),
        for (final e in entries) _entryRow(context, entriesDef, e),
      ]),
    );
  }

  Widget _entryRow(BuildContext context, CollectionDef entriesDef, AdminDoc e) {
    final hidden = _effectiveHidden(e, targetDef: entriesDef);
    final unconfirmed = e.data['sample'] == true;
    final sub = _subtitle(context, e, entriesDef);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _splitActionRow(
        tileKey: ValueKey('entry-${e.id}'),
        dense: true,
        contentPadding: const EdgeInsetsDirectional.only(start: 20, end: 4),
        leading: Icon(Icons.subdirectory_arrow_left_rounded, size: 18, color: context.pal.muted),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(_title(e, entriesDef),
                style: TextStyle(fontWeight: FontWeight.w600, color: hidden ? context.pal.muted : context.pal.ink)),
            _Tag(context.tr(hidden ? 'hidden' : 'visibleTag'),
                hidden ? context.pal.muted : context.pal.success),
            if (unconfirmed) _Tag(context.tr('sampleTag'), context.pal.goldText),
          ],
        ),
        subtitle: sub.isEmpty ? null : Text(sub),
        onTap: () => _openEditor(context, e, targetDef: entriesDef),
        trailing: _visibilityButton(context, e, key: ValueKey('visibilityEntry-${e.id}'), targetDef: entriesDef),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(44, 0, 8, 4),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _namedDeleteButton(
            context,
            key: ValueKey('deleteEntry-${e.id}'),
            onPressed: () => _deleteItem(e, targetDef: entriesDef),
          ),
        ),
      ),
    ]);
  }

  Widget _tile(BuildContext context, AdminDoc d, {int? dragIndex, List<AdminDoc>? docs}) {
    final hidden = def.hasVisible ? _effectiveHidden(d) : d.data['visible'] == false;
    final unconfirmed = d.data['sample'] == true;
    final stopped = d.data.containsKey('active') && d.data['active'] == false;
    final expired = _isExpired(def, d.data);
    final isDepartedPriest = def.name == 'priests' && priestStatus(d.data) == 'departed';
    final sub = _subtitle(context, d);
    final updated = d.updatedAt;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    // Missing = on (PR #14), but only collections with detail routes have pages.
    final details = detailKindForCollection(def.name) != null && d.data['detailsEnabled'] != false;
    final itemPath = itemPublicPathFor(def, d.id, d.data, english: !context.isAr);
    final sameGroupUp = dragIndex != null &&
        docs != null &&
        dragIndex > 0 &&
        (def.name != 'priests' || priestStatus(docs[dragIndex - 1].data) == priestStatus(d.data));
    final sameGroupDown = dragIndex != null &&
        docs != null &&
        dragIndex < docs.length - 1 &&
        (def.name != 'priests' || priestStatus(docs[dragIndex + 1].data) == priestStatus(d.data));
    // Single-tap alternative to dragging (WCAG 2.5.7).
    final moves = <Widget>[
      if (dragIndex != null && docs != null) ...[
        IconButton(
          key: ValueKey('moveUp-${d.id}'),
          tooltip: context.tr('moveUp'),
          icon: const Icon(Icons.arrow_upward),
          onPressed: !sameGroupUp ? null : () => _reorder(context, docs, dragIndex, dragIndex - 1),
        ),
        IconButton(
          key: ValueKey('moveDown-${d.id}'),
          tooltip: context.tr('moveDown'),
          icon: const Icon(Icons.arrow_downward),
          onPressed: !sameGroupDown ? null : () => _reorder(context, docs, dragIndex, dragIndex + 1),
        ),
      ],
    ];
    // The item's own detail page when it has one (else the toolbar's
    // "open on site" shows the collection page).
    final openItem = itemPath == null ? null : _openOnSiteButton(context, d, itemPath);
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 8),
      color: hidden ? context.pal.surfaceAlt.withValues(alpha: 0.7) : context.pal.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _splitActionRow(
          leading: dragIndex != null
              ? ReorderableDragStartListener(index: dragIndex, child: const Icon(Icons.drag_indicator))
              : null,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(_title(d),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: hidden ? context.pal.muted : context.pal.ink)),
              if (def.hasVisible)
                _Tag(context.tr(hidden ? 'hidden' : 'visibleTag'),
                    hidden ? context.pal.muted : context.pal.success),
              if (isDepartedPriest)
                _Tag(context.tr('opt_departed'), context.pal.muted),
              if (stopped)
                _Tag(context.tr('stoppedTag'), context.pal.alert),
              if (expired)
                _Tag(context.tr('expiredTag'), context.pal.muted),
              if (unconfirmed)
                _Tag(context.tr('sampleTag'), context.pal.goldText),
            ],
          ),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Own line: the title row keeps its width on phones.
            if (details)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: _Tag(context.tr('detailPageBadge'), context.pal.primary, margin: EdgeInsetsDirectional.zero),
              ),
            if (sub.isNotEmpty) Text(sub),
            if (updated != null)
              Text(
                context.tr('updatedBy', {'t': fmtDateTime(updated), 'u': d.updatedBy.isEmpty ? '—' : d.updatedBy}),
                style: TextStyle(fontSize: 11, color: context.pal.muted),
              ),
            // Phones: the move buttons get their own row so the title keeps its width.
            if (narrow && moves.isNotEmpty) Wrap(children: moves),
          ]),
          onTap: () => _openEditor(context, d),
          trailing: (!narrow && moves.isNotEmpty) || def.hasVisible
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!narrow) ...moves,
                  if (def.hasVisible) _visibilityButton(context, d, key: ValueKey('visibility-${d.id}')),
                ])
              : null,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: openItem != null ? WrapAlignment.spaceBetween : WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                ?openItem,
                if (def.name == 'pages')
                  TextButton.icon(
                    key: ValueKey('duplicate-${d.id}'),
                    onPressed: () => _duplicatePage(context, d, pagesDef: def),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(context.tr('duplicate')),
                  ),
                _namedDeleteButton(
                  context,
                  key: ValueKey('delete-${d.id}'),
                  onPressed: () => _confirmDelete(d),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _setVisible(BuildContext context, AdminDoc d, bool visible, {CollectionDef? targetDef}) async {
    final activeDef = targetDef ?? def;
    final k = _visKey(activeDef.name, d.id);
    if (_togglingVisibility.contains(k)) return;
    final repo = widget.repo;
    final epoch = _screenEpoch;
    final messenger = _messenger;
    final msg = context.tr(visible ? 'nowVisible' : 'nowHidden');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    setState(() {
      _togglingVisibility.add(k);
      _optimisticVisible[k] = visible;
      _settledAtStreamSeq.remove(k);
    });
    try {
      await repo.update(activeDef.name, d.id, {'visible': visible});
      if (!mounted || epoch != _screenEpoch || !identical(widget.repo, repo)) {
        return;
      }
      setState(() {
        _togglingVisibility.remove(k);
        if (_latestStreamVisible[k] == visible) {
          _optimisticVisible.remove(k);
          _settledAtStreamSeq.remove(k);
        } else {
          // Stamp current snapshot sequence for this collection so unrelated
          // streams (e.g. entries vs pages) cannot release its override early.
          _settledAtStreamSeq[k] = _streamSeqByCollection[activeDef.name] ?? 0;
        }
      });
      _showSnack(
        messenger,
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        deferWhileUndo: true,
      );
    } catch (e) {
      if (!mounted || epoch != _screenEpoch || !identical(widget.repo, repo)) {
        return;
      }
      setState(() {
        _togglingVisibility.remove(k);
        _optimisticVisible.remove(k);
        _settledAtStreamSeq.remove(k);
      });
      _showSnack(
        messenger,
        SnackBar(content: Text(failed.replaceAll('{e}', formatAdminError(e)))),
        deferWhileUndo: true,
      );
    }
  }

  Future<void> _reorder(BuildContext context, List<AdminDoc> docs, int from, int to) async {
    final list = [...docs];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    final movedStatus = def.name == 'priests' ? priestStatus(moved.data) : null;
    // Serving and departed priests share the `priests` collection: keep
    // each status group in its own order range (0+ vs 1000+) and never mix.
    final ids = [
      for (final d in list)
        if (movedStatus == null || priestStatus(d.data) == movedStatus) d.id,
    ];
    final messenger = _messenger;
    final ok = context.tr('orderSaved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    try {
      await widget.repo.reorder(def.name, ids, base: reorderBase(def, status: movedStatus));
      if (!mounted) return;
      _showSnack(
        messenger,
        SnackBar(content: Text(ok), duration: const Duration(seconds: 2)),
        deferWhileUndo: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        messenger,
        SnackBar(content: Text(failed.replaceAll('{e}', formatAdminError(e)))),
        deferWhileUndo: true,
      );
    }
  }

  void _checkLazyPurge(List<AdminDoc> docs, CollectionDef targetDef) {
    final now = DateTime.now().toUtc();
    if (docs.any((d) => isExpiredSoftDelete(d.data, now) && !_pendingDelete.isPending(d.id))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          purgeExpiredSoftDeletes(
            widget.repo,
            targetDef,
            docs,
            isLocalPending: _pendingDelete.isPending,
            purging: _purging,
          );
        }
      });
    }
  }

  void _confirmDelete(AdminDoc d) {
    final def = widget.def;
    if (def.name == 'categories') {
      _deleteCategory(d);
      return;
    }
    _deleteItem(d);
  }

  Future<void> _deleteItem(AdminDoc d, {CollectionDef? targetDef}) async {
    final activeDef = targetDef ?? def;
    final id = d.id;
    if (_pendingDelete.isPending(id)) return;
    final title = _title(d, activeDef);
    final messenger = _messenger;
    final failedMsg = context.tr('deleteFailed', {'e': '{e}'});
    final repo = widget.repo;
    final docData = d.data;
    final deleteNow = DateTime.now().toUtc();
    final gen = (_deleteGen[id] ?? 0) + 1;
    _deleteGen[id] = gen;
    _restoringIds.remove(id);

    final priorPending = [
      for (final entry in _pendingEntries.entries.toList())
        if (entry.key != id && _pendingDelete.isPending(entry.key)) (id: entry.key, info: entry.value),
    ];

    // Register the item in PendingDelete synchronously BEFORE awaiting Firestore
    // so rapid consecutive deletes and immediate "Undo all" taps always operate on
    // the full batch atomically and never fall back to a single-item undo bar.
    setState(() {
      _pendingEntries[id] = (repo: repo, collection: activeDef.name, title: title);
      _pendingDelete.schedule(id, () async {
        _pendingEntries.remove(id);
        try {
          await repo.delete(activeDef.name, id);
          await removeOrphanedDocMedia(repo.media, docData);
        } catch (e) {
          try {
            await repo.update(activeDef.name, id, {'deletedAt': null});
          } catch (_) {}
          if (!mounted) return;
          setState(() {});
          _syncUndoBarAfterExpiry(messenger, failedMsg: failedMsg);
          _showSnack(
            messenger,
            SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
            deferWhileUndo: true,
          );
          return;
        }
        if (!mounted) return;
        _syncUndoBarAfterExpiry(messenger, failedMsg: failedMsg);
      });
    });

    // Acquire holds BEFORE scheduling _undoSnackBarTimer so renewal anchor timers
    // are registered ahead of the SnackBar timer and stay aligned at t = 10s.
    final initialHoldTokens = _pendingDelete.holdAll([id]);
    final initialToken = initialHoldTokens[id];
    final priorHoldTokens = priorPending.isEmpty
        ? const <String, Object>{}
        : _pendingDelete.holdAll([for (final p in priorPending) p.id]);

    _presentUndoSnackBar(
      messenger,
      title: title,
      fallbackRepo: repo,
      fallbackCollection: activeDef.name,
      failedMsg: failedMsg,
      resetTimer: true,
      clearQueue: true,
    );

    // Serialize this item's soft-delete write behind any earlier in-flight write
    // for the same id so updates arrive in order.
    final priorSelfWrite = _inFlightDeleteWrites[id];
    late final Future<bool> selfWrite;
    selfWrite = () async {
      if (priorSelfWrite != null) {
        try {
          await priorSelfWrite;
        } catch (_) {}
      }
      var written = false;
      try {
        await repo.update(activeDef.name, id, {'deletedAt': deleteNow});
        written = true;
      } catch (e) {
        if (mounted && _deleteGen[id] == gen) {
          _pendingDelete.undo(id);
          _pendingEntries.remove(id);
          setState(() {});
          _syncUndoBarAfterExpiry(messenger, failedMsg: failedMsg);
          _showSnack(
            messenger,
            SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
            deferWhileUndo: true,
          );
        }
        return false;
      }
      if (!mounted) return written;
      if (_deleteGen[id] == gen) {
        await _pendingDelete.releaseHold(id, extend: true, token: initialToken);
        if (mounted) _syncUndoBarAfterExpiry(messenger, failedMsg: failedMsg);
      }
      return written;
    }();
    _inFlightDeleteWrites[id] = selfWrite;
    unawaited(selfWrite.whenComplete(() {
      if (identical(_inFlightDeleteWrites[id], selfWrite)) {
        _inFlightDeleteWrites.remove(id);
      }
    }));

    // Renew deletedAt for every prior pending item, serialized per item so slower
    // earlier renewals never overwrite newer deletedAt timestamps.
    for (final p in priorPending) {
      final token = priorHoldTokens[p.id];
      final priorGen = _deleteGen[p.id];
      final prevChain = _inFlightDeleteWrites[p.id];
      late final Future<bool> chainedRenewal;
      chainedRenewal = () async {
        var priorWritten = true;
        if (prevChain != null) {
          try {
            priorWritten = await prevChain;
          } catch (_) {
            priorWritten = false;
          }
        }
        if (!mounted || _deleteGen[p.id] != priorGen || !_pendingDelete.isPending(p.id)) {
          return priorWritten;
        }
        var renewed = false;
        try {
          await p.info.repo.update(p.info.collection, p.id, {'deletedAt': deleteNow});
          renewed = true;
        } catch (_) {}
        if (!mounted) return priorWritten || renewed;
        if (_deleteGen[p.id] == priorGen) {
          await _pendingDelete.releaseHold(p.id, extend: renewed, token: token);
          if (mounted) _syncUndoBarAfterExpiry(messenger, failedMsg: failedMsg);
        }
        return priorWritten || renewed;
      }();
      _inFlightDeleteWrites[p.id] = chainedRenewal;
      unawaited(chainedRenewal.whenComplete(() {
        if (identical(_inFlightDeleteWrites[p.id], chainedRenewal)) {
          _inFlightDeleteWrites.remove(p.id);
        }
      }));
    }
  }

  void _syncUndoBarAfterExpiry(ScaffoldMessengerState? messenger, {required String failedMsg}) {
    if (!mounted) return;
    if (!_pendingDelete.hasPending) {
      final hadActiveUndoBar = _undoSnackBarController != null;
      _undoSnackBarTimer?.cancel();
      _undoSnackBarTimer = null;
      _undoSnackBarController = null;
      _undoSnackBarCount = 0;
      _undoBarUsesMultiAction = false;
      _undoBarState.value = null;
      if (hadActiveUndoBar) {
        _startFabCooldown();
        if (messenger != null && messenger.mounted) {
          messenger.removeCurrentSnackBar();
        }
      }
      _flushDeferredErrors(messenger);
      return;
    }
    final pendingCount = _pendingDelete.pendingIds.length;
    if (_undoSnackBarController == null || _undoSnackBarCount == pendingCount) return;
    final last = _pendingEntries.values.isNotEmpty ? _pendingEntries.values.last : null;
    if (last == null) return;
    _presentUndoSnackBar(
      messenger,
      title: last.title,
      fallbackRepo: last.repo,
      fallbackCollection: last.collection,
      failedMsg: failedMsg,
      resetTimer: false,
      clearQueue: false,
    );
  }

  void _scheduleUndoSnackBarTimer(
    ScaffoldMessengerState messenger, {
    required String failedMsg,
  }) {
    _undoSnackBarTimer?.cancel();
    _undoSnackBarTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_pendingDelete.hasPending && _pendingEntries.values.isNotEmpty) {
        final last = _pendingEntries.values.last;
        _presentUndoSnackBar(
          messenger,
          title: last.title,
          fallbackRepo: last.repo,
          fallbackCollection: last.collection,
          failedMsg: failedMsg,
          resetTimer: true,
          clearQueue: false,
        );
        return;
      }
      final hadActiveUndoBar = _undoSnackBarController != null;
      _undoSnackBarTimer = null;
      _undoSnackBarController = null;
      _undoSnackBarCount = 0;
      _undoBarUsesMultiAction = false;
      _undoBarState.value = null;
      if (hadActiveUndoBar) {
        _startFabCooldown();
        if (messenger.mounted) messenger.removeCurrentSnackBar();
      }
      _flushDeferredErrors(messenger);
    });
  }

  Future<void> _undoAllPending(
    ScaffoldMessengerState messenger, {
    required AdminBackend fallbackRepo,
    required String fallbackCollection,
    required String failedMsg,
  }) async {
    _undoSnackBarTimer?.cancel();
    _undoSnackBarTimer = null;
    _undoSnackBarController = null;
    _undoSnackBarCount = 0;
    _undoBarUsesMultiAction = false;
    _undoBarState.value = null;
    _startFabCooldown();
    if (messenger.mounted) messenger.removeCurrentSnackBar();

    final ids = _pendingDelete.pendingIds.toList();
    final undone = <({String id, AdminBackend repo, String collection, Future<bool>? inFlight})>[];
    for (final pid in ids) {
      if (_pendingDelete.undo(pid)) {
        _deleteGen[pid] = (_deleteGen[pid] ?? 0) + 1;
        final entry = _pendingEntries.remove(pid);
        _restoringIds.add(pid);
        undone.add((
          id: pid,
          repo: entry?.repo ?? fallbackRepo,
          collection: entry?.collection ?? fallbackCollection,
          inFlight: _inFlightDeleteWrites[pid],
        ));
      }
    }
    if (mounted && undone.isNotEmpty) setState(() {});
    // Yield past SnackBarAction._handlePressed()'s trailing hideCurrentSnackBar call
    // so flushed errors are not immediately dismissed as if they were the Undo bar.
    await Future<void>.microtask(() {});
    _flushDeferredErrors(messenger);
    if (undone.isEmpty) return;

    final restoreTasks = <Future<bool>>[];
    for (final item in undone) {
      late final Future<bool> restoreFuture;
      restoreFuture = () async {
        var hadSoftDeleteWrite = true;
        if (item.inFlight != null) {
          try {
            hadSoftDeleteWrite = await item.inFlight!;
          } catch (_) {
            hadSoftDeleteWrite = false;
          }
        }
        if (!hadSoftDeleteWrite) {
          _restoringIds.remove(item.id);
          if (mounted) setState(() {});
          return false;
        }
        try {
          await item.repo.update(item.collection, item.id, {'deletedAt': null});
          return false;
        } catch (e) {
          if (mounted) {
            _showSnack(
              messenger,
              SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))),
              deferWhileUndo: true,
            );
          }
          return true;
        } finally {
          _restoringIds.remove(item.id);
          if (mounted) setState(() {});
        }
      }();
      _inFlightDeleteWrites[item.id] = restoreFuture;
      unawaited(restoreFuture.whenComplete(() {
        if (identical(_inFlightDeleteWrites[item.id], restoreFuture)) {
          _inFlightDeleteWrites.remove(item.id);
        }
      }));
      restoreTasks.add(restoreFuture);
    }
    await Future.wait(restoreTasks);
  }

  void _presentUndoSnackBar(
    ScaffoldMessengerState? messenger, {
    required String title,
    required AdminBackend fallbackRepo,
    required String fallbackCollection,
    required String failedMsg,
    required bool resetTimer,
    bool clearQueue = false,
  }) {
    if (!mounted || messenger == null || !messenger.mounted) return;
    final pendingCount = _pendingDelete.pendingIds.length;
    if (pendingCount == 0) return;
    final wantMulti = pendingCount > 1;
    _undoBarState.value = (count: pendingCount, title: title);
    _undoSnackBarCount = pendingCount;
    _cancelFabCooldown();

    // Update the active Undo bar in place when the action label stays identical
    // (e.g., 2 -> 3 -> 4 deletes keep "Undo all") to avoid ScaffoldMessenger queue
    // churn, exit/re-entry flicker, or FAB bounce.
    if (_undoSnackBarController != null && _undoBarUsesMultiAction == wantMulti) {
      if (resetTimer) {
        _scheduleUndoSnackBarTimer(messenger, failedMsg: failedMsg);
      }
      return;
    }

    final actionLabel = context.tr(wantMulti ? 'undoAll' : 'undo');
    if (resetTimer) {
      _undoSnackBarTimer?.cancel();
      _undoSnackBarTimer = null;
    }
    _undoSnackBarController = null;
    _undoBarUsesMultiAction = wantMulti;
    // Clear prior non-undo queues on user-initiated deletes so the Undo bar always
    // shows immediately at the front, while automatic expiry refreshes preserve queued bars.
    if (clearQueue) messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    final undoController = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        persist: true,
        content: ValueListenableBuilder<({int count, String title})?>(
          valueListenable: _undoBarState,
          builder: (ctx, state, _) {
            final count = state?.count ?? pendingCount;
            final lastTitle = state?.title ?? title;
            final text = count > 1
                ? ctx.tr('deletedItemMultiUndo', {'n': '$count', 'last': lastTitle})
                : ctx.tr('deletedItemUndo', {'n': lastTitle});
            return Text(text);
          },
        ),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: () => _undoAllPending(
            messenger,
            fallbackRepo: fallbackRepo,
            fallbackCollection: fallbackCollection,
            failedMsg: failedMsg,
          ),
        ),
      ),
    );
    _undoSnackBarController = undoController;
    setState(() {});
    undoController.closed.then((reason) {
      if (identical(_undoSnackBarController, undoController)) {
        _undoSnackBarController = null;
        _undoSnackBarCount = 0;
        _undoBarUsesMultiAction = false;
        _undoBarState.value = null;
        _undoSnackBarTimer?.cancel();
        _undoSnackBarTimer = null;
        if (reason == SnackBarClosedReason.timeout &&
            mounted &&
            _pendingDelete.hasPending &&
            _pendingEntries.values.isNotEmpty) {
          final last = _pendingEntries.values.last;
          _presentUndoSnackBar(
            messenger,
            title: last.title,
            fallbackRepo: last.repo,
            fallbackCollection: last.collection,
            failedMsg: failedMsg,
            resetTimer: true,
          );
        } else {
          _startFabCooldown();
          _flushDeferredErrors(messenger);
        }
      }
    });
    if (resetTimer) {
      _scheduleUndoSnackBarTimer(messenger, failedMsg: failedMsg);
    }
  }

  /// Deleting a custom category hides its items (visible: false) first and
  /// never deletes them (ADR-027); they can be moved to another category.
  Future<void> _deleteCategory(AdminDoc d) async {
    final messenger = _messenger;
    final failedMsg = context.tr('deleteFailed', {'e': '{e}'});
    final deletedMsg = context.tr('catDeleted');
    List<AdminDoc> entries;
    try {
      entries = await widget.repo.watch('entries').first.timeout(const Duration(seconds: 15));
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))));
      return;
    }
    final inCat = entries.where((e) => e.data['categoryId'] == d.id).length;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('deleteCategoryDialog'),
        title: Text(_title(d)),
        content: Text(context.tr('catDeleteConfirm', {'n': _title(d), 'c': '$inCat'})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.pal.alert),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      for (final id in entryIdsToHide(d.id, [for (final e in entries) (id: e.id, data: e.data)])) {
        await widget.repo.update('entries', id, {'visible': false});
      }
      await widget.repo.delete(def.name, d.id);
      _showSnack(messenger, SnackBar(content: Text(deletedMsg)));
    } catch (e) {
      if (!mounted) return;
      _showSnack(messenger, SnackBar(content: Text(failedMsg.replaceAll('{e}', formatAdminError(e)))));
    }
  }

  /// Categories and custom pages for the editor's run-time choices and link
  /// picker (best effort: an unreadable list just offers fewer choices).
  Future<List<AdminDoc>> _read(String collection) async {
    try {
      return await widget.repo.watch(collection).first.timeout(const Duration(seconds: 10));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openNewPageChooser(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('addPageDialog'),
        title: Text(context.tr('addPageTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: const Key('addPage-blank'),
                leading: Icon(Icons.article_outlined, color: context.pal.primary),
                title: Text(context.tr('blankPageOption'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(context.tr('blankPageHint')),
                onTap: () => Navigator.pop(ctx, 'blank'),
              ),
            ),
            Card(
              child: ListTile(
                key: const Key('addPage-donation'),
                leading: Icon(Icons.volunteer_activism_outlined, color: context.pal.primary),
                title: Text(context.tr('donationPageOption'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(context.tr('donationPageHint')),
                onTap: () => Navigator.pop(ctx, 'donation'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    await _openEditor(
      context,
      null,
      extraDefaults: choice == 'donation' ? donationPageTemplate() : const {},
    );
  }

  Future<void> _duplicatePage(
    BuildContext _,
    AdminDoc source, {
    required CollectionDef pagesDef,
  }) async {
    if (_openingEditor) return;
    _openingEditor = true;
    try {
      final editorTitle = '${context.tr('duplicate')} — ${context.pick(pagesDef.labelAr, pagesDef.labelEn)}';
      await _openEditorBody(
        null,
        targetDef: pagesDef,
        titleOverride: editorTitle,
        duplicateSource: source,
      );
    } finally {
      _openingEditor = false;
    }
  }

  Future<void> _openEditor(
    BuildContext _,
    AdminDoc? d, {
    CollectionDef? targetDef,
    Map<String, Object?> extraDefaults = const {},
    String? titleOverride,
    String? initialNotice,
  }) async {
    if (_openingEditor) return;
    _openingEditor = true;
    try {
      await _openEditorBody(
        d,
        targetDef: targetDef,
        extraDefaults: extraDefaults,
        titleOverride: titleOverride,
        initialNotice: initialNotice,
      );
    } finally {
      _openingEditor = false;
    }
  }

  Future<void> _openEditorBody(
    AdminDoc? d, {
    CollectionDef? targetDef,
    Map<String, Object?> extraDefaults = const {},
    String? titleOverride,
    String? initialNotice,
    AdminDoc? duplicateSource,
  }) async {
    final editDef = targetDef ?? def;
    bool usesLinks(List<FieldDef> fs) => fs.any((f) => f.linkPicker || usesLinks(f.subFields));
    final needsCats = editDef.fields.any((f) => f.dynamicOptions == 'categories');
    final needsProgram = editDef.fields.any((f) => f.dynamicOptions == 'venues' || f.dynamicOptions == 'audiences');
    final needsLinks = usesLinks(editDef.fields);
    final cats = needsCats || needsLinks ? await _read('categories') : const <AdminDoc>[];
    final cachedPages = def.name == 'categories' ? _lastPages : null;
    final pages = needsLinks || (editDef.name == 'pages' && editDef.name != def.name)
        ? (cachedPages ?? await _read('pages'))
        : const <AdminDoc>[];
    final seasonDocs = editDef.name == 'liturgies' ? await _read('seasons') : const <AdminDoc>[];
    // Venues / audiences (ADR-041): the admin lists in settings/features
    // (defaults when none), read once when the editor opens.
    final settings = needsProgram ? await _read('settings') : const <AdminDoc>[];
    final features = settings.where((x) => x.id == 'features').firstOrNull;
    final programOpts = ProgramOptions.fromMap(features?.data ?? const {});
    if (!mounted) return;
    String name(AdminDoc x, String ar, String en) {
      final v = context.pick('${x.data[ar] ?? ''}', '${x.data[en] ?? ''}');
      return x.data['visible'] == false ? '$v ${context.tr('hiddenTag')}' : v;
    }

    final catDef = collectionById('categories') ?? editDef;
    final catChoices = [
      if (editDef.name == 'pages')
        for (final b in BuiltInSections.all)
          (b.id, context.pick(b.nameAr, b.nameEn)),
      for (final c in sortAdminDocs(catDef, cats))
        (c.id, name(c, 'nameAr', 'nameEn')),
    ];
    final targets = [
      for (final t in linkTargets(
        pages: [
          for (final p in pages)
            if (!isSoftDeleted(p.data))
              (slug: '${p.data['slug'] ?? ''}', titleAr: name(p, 'titleAr', 'titleEn'), titleEn: name(p, 'titleAr', 'titleEn')),
        ],
        categories: [
          for (final c in cats)
            if (!isSoftDeleted(c.data))
              (slug: '${c.data['slug'] ?? ''}', titleAr: name(c, 'nameAr', 'nameEn'), titleEn: name(c, 'nameAr', 'nameEn')),
        ],
      ))
        (t.path, context.pick(t.labelAr, t.labelEn)),
    ];
    final taken = switch (editDef.name) {
      _ when editDef.name == def.name => collectTakenSlugs(
          _lastDocs,
          excludeId: d?.id,
          isPendingDelete: _pendingDelete.isPending,
        ),
      'pages' => collectTakenSlugs(
          pages,
          excludeId: d?.id,
          isPendingDelete: _pendingDelete.isPending,
        ),
      'categories' => collectTakenSlugs(
          cats,
          excludeId: d?.id,
          isPendingDelete: _pendingDelete.isPending,
        ),
      _ => const <String>{},
    };
    var resolvedExtra = extraDefaults;
    var resolvedNotice = initialNotice;
    if (duplicateSource != null) {
      final dup = buildDuplicatePageDefaults(duplicateSource.data, takenSlugs: taken);
      resolvedExtra = {...extraDefaults, ...dup.defaults};
      if (dup.droppedOwnedImage) resolvedNotice = context.tr('duplicateDroppedImage');
    }
    final seasons = [
      for (final s in seasonDocs)
        if (!isSoftDeleted(s.data)) Season.fromMap(s.id, s.data),
    ];
    List<(String, String)> optChoices(List<ProgramOption> l) => [for (final o in l) (o.key, context.pick(o.labelAr, o.labelEn))];
    _pushEditor(
      context,
      d,
      editDef: editDef,
      extraDefaults: resolvedExtra,
      dynamicChoices: {
        'categories': catChoices,
        // The item's own key stays selectable even if the admin list no
        // longer holds it (a default key, Sentry review).
        'venues': optChoices(ProgramOptions.withUsed(
            programOpts.venues, ['${d?.data['venue'] ?? ''}'], programOpts.venue)),
        'audiences': optChoices(ProgramOptions.withUsed(
            programOpts.audiences, ['${d?.data['audience'] ?? ''}'], programOpts.audience)),
      },
      linkTargets: needsLinks ? targets : const [],
      takenSlugs: taken,
      seasons: seasons,
      titleOverride: titleOverride,
      initialNotice: resolvedNotice,
    );
  }

  void _pushEditor(
    BuildContext context,
    AdminDoc? d, {
    required CollectionDef editDef,
    Map<String, Object?> extraDefaults = const {},
    Map<String, List<(String, String)>> dynamicChoices = const {},
    List<(String, String)> linkTargets = const [],
    Set<String> takenSlugs = const {},
    List<Season> seasons = const [],
    String? titleOverride,
    String? initialNotice,
  }) {
    final label = context.pick(editDef.labelAr, editDef.labelEn);
    final editorTitle = titleOverride ?? '${context.tr(d == null ? 'add' : 'edit')} — $label';
    // The editor may save in several writes (gallery / extraFields go on
    // their own): the first one creates a new document, the rest merge into it.
    var id = d?.id;
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocEditor(
        title: editorTitle,
        fields: editDef.fields,
        def: editDef,
        data: d?.data,
        docId: d?.id,
        newDefaults: {...editDef.newDefaults, ...extraDefaults},
        onSave: (data) async => id = await widget.repo.save(editDef.name, id, data),
        media: widget.repo.media,
        dynamicChoices: dynamicChoices,
        linkTargets: linkTargets,
        takenSlugs: takenSlugs,
        existingDocs: editDef.name == def.name
            ? [
                for (final x in _lastDocs)
                  if (_isVisibleDoc(x)) x,
              ]
            : const [],
        seasons: seasons,
        englishEnabled: _englishEnabled,
        initialNotice: initialNotice,
        popMessenger: _messenger,
      ),
    ));
  }

  bool _isExpired(CollectionDef def, Map<String, dynamic> data) =>
      isExpiredAdminDoc(def.name, data, CairoTime.now());
}

/// [def]'s public page, with `?lang=en` when the dashboard is in English.
String publicPathFor(CollectionDef def, {required bool english}) {
  final path = def.publicPath.isEmpty ? '/' : def.publicPath;
  return english ? Uri.parse(path).replace(queryParameters: {'lang': 'en'}).toString() : path;
}

/// Public detail page of an item (PR #13 routes), or null when the item has
/// none: its collection has no detail pages, `detailsEnabled` is explicitly
/// false (missing = on, PR #14), or the item is hidden.
/// (not listed publicly, so its page shows "not available"). `?lang=en` when the dashboard is in English.
String? itemPublicPathFor(CollectionDef def, String id, Map<String, dynamic> data, {required bool english}) {
  // Custom categories / pages (ADR-027): their own page by slug.
  if (def.name == 'categories' || def.name == 'pages') {
    final slug = '${data['slug'] ?? ''}';
    if (!isValidSlug(slug) || data['visible'] == false) return null;
    final path = def.name == 'pages' ? customPagePath(slug) : categoryPath(slug);
    return english ? '$path?lang=en' : path;
  }
  final kind = detailKindForCollection(def.name);
  if (kind == null || data['detailsEnabled'] == false || data['visible'] == false) return null;
  final path = detailPathFor(kind, id);
  return english ? '$path?lang=en' : path;
}

/// First `order` value minus 10 for [def]'s reorder (BUG-13).
int reorderBase(CollectionDef def, {String? status}) =>
    (def.id == 'departedPriests' || status == 'departed') ? 1000 : 0;

class _FabSnackHeightTracker {
  double lastUndoSnackHeight = 64.0;
}

/// Places the "Add" FAB at standard `endFloat` normally, and elevates it with a
/// clear 48 px vertical gap above an active Undo SnackBar. Holds that elevated
/// clearance across SnackBar swaps and during a 650 ms post-close cooldown so
/// stray follow-up taps aimed at the vacated Undo button never hit the FAB.
class _UndoClearFabLocation extends StandardFabLocation with FabEndOffsetX, FabFloatOffsetY {
  final bool holdElevated;
  final _FabSnackHeightTracker tracker;
  const _UndoClearFabLocation({required this.holdElevated, required this.tracker});

  static const double undoGap = 48.0;

  @override
  double getOffsetY(ScaffoldPrelayoutGeometry scaffoldGeometry, double adjustment) {
    final baseY = super.getOffsetY(scaffoldGeometry, adjustment);
    if (!holdElevated) return baseY;
    final snackH = scaffoldGeometry.snackBarSize.height;
    if (snackH > 0.0) {
      tracker.lastUndoSnackHeight = math.max(snackH, 56.0);
    }
    final fabH = scaffoldGeometry.floatingActionButtonSize.height;
    final effectiveSnackH = math.max(snackH, tracker.lastUndoSnackHeight);
    final desiredY = scaffoldGeometry.contentBottom - effectiveSnackH - fabH - undoGap;
    final minY = scaffoldGeometry.contentTop + kFloatingActionButtonMargin;
    return math.max(minY, math.min(baseY, desiredY));
  }

  @override
  bool operator ==(Object other) =>
      other is _UndoClearFabLocation &&
      other.holdElevated == holdElevated &&
      identical(other.tracker, tracker);

  @override
  int get hashCode => Object.hash(holdElevated, identityHashCode(tracker));
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final EdgeInsetsGeometry margin;
  const _Tag(this.text, this.color, {this.margin = const EdgeInsetsDirectional.only(start: 6)});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}
