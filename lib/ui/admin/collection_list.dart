import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/item_detail.dart';
import '../../domain/media.dart';
import '../../domain/program.dart';
import '../../domain/time_format.dart';
import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';
import 'doc_editor.dart';
import 'pending_delete.dart';

enum ListFilter { all, visible, hidden, unconfirmed }

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

/// Docs that match the screen filter, the list filter and the search text.
List<AdminDoc> filterAdminDocs(CollectionDef def, List<AdminDoc> docs, {String query = '', ListFilter filter = ListFilter.all}) {
  final q = query.trim().toLowerCase();
  return [
    for (final d in docs)
      if (def.matches(d.data) &&
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

class CollectionListScreen extends StatefulWidget {
  final AdminBackend repo;
  final CollectionDef def;
  const CollectionListScreen({super.key, required this.repo, required this.def});

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  final _search = TextEditingController();
  final _pendingDelete = PendingDelete();
  ListFilter _filter = ListFilter.all;
  late Stream<List<AdminDoc>> _stream = widget.repo.watch(widget.def.name);

  /// The list as last shown (slug uniqueness checks in the editor).
  List<AdminDoc> _lastDocs = const [];

  @override
  void didUpdateWidget(covariant CollectionListScreen old) {
    super.didUpdateWidget(old);
    if (old.def.name != widget.def.name || old.repo != widget.repo) {
      _stream = widget.repo.watch(widget.def.name);
    }
  }

  @override
  void dispose() {
    _pendingDelete.dispose();
    _search.dispose();
    super.dispose();
  }

  CollectionDef get def => widget.def;

  String _title(AdminDoc d) {
    for (final k in def.titleKeys) {
      final v = d.data[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return d.id;
  }

  String _subtitle(BuildContext context, AdminDoc d) {
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
      if (v is String && v.isNotEmpty && !def.titleKeys.contains(k)) parts.add(choiceLabel(context, v));
    }
    if (d.data['active'] == false) parts.add('⛔ ${context.tr('inactive')}');
    for (final k in ['startsAt', 'endsAt']) {
      final v = d.data[k];
      if (v is DateTime) parts.add(fmtDateTime(v));
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pal.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-${def.id}',
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('add')),
      ),
      body: StreamBuilder<List<AdminDoc>>(
        // A new stream (another backend) gets a fresh StreamBuilder: a reused
        // one keeps the old backend's list while the new one loads.
        key: ObjectKey(_stream),
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = sortAdminDocs(
              def,
              snap.data!
                  .where((d) => def.matches(d.data))
                  .toList());
          _lastDocs = all;
          final visible = all.where((d) => !_pendingDelete.pendingIds.contains(d.id)).toList();
          final docs = filterAdminDocs(def, visible, query: _search.text, filter: _filter);
          final canReorder = def.orderable && _search.text.trim().isEmpty && _filter == ListFilter.all && docs.length > 1;
          return Column(children: [
            _toolbar(context, visible.length, docs.length, canReorder),
            Expanded(
              child: docs.isEmpty
                  ? Center(child: Text(context.tr(all.isEmpty ? 'noItems' : 'noMatches')))
                  : canReorder
                      ? ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: docs.length,
                          onReorderItem: (from, to) => _reorder(context, docs, from, to),
                          itemBuilder: (context, i) => _tile(context, docs[i], dragIndex: i, docs: docs),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: docs.length,
                          itemBuilder: (context, i) => _tile(context, docs[i]),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context, int total, int shown, bool canReorder) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (def.noteAr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.pick(def.noteAr, def.noteEn),
                key: const Key('admin-collectionNote'), style: TextStyle(color: context.pal.muted, height: 1.5)),
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
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in ListFilter.values)
            if ((f != ListFilter.unconfirmed || def.hasSample) &&
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

  Widget _tile(BuildContext context, AdminDoc d, {int? dragIndex, List<AdminDoc>? docs}) {
    final hidden = d.data['visible'] == false;
    final unconfirmed = d.data['sample'] == true;
    final sub = _subtitle(context, d);
    final updated = d.updatedAt;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    // Missing = on (PR #14), but only collections with detail routes have pages.
    final details = detailKindForCollection(def.name) != null && d.data['detailsEnabled'] != false;
    final itemPath = itemPublicPathFor(def, d.id, d.data, english: !context.isAr);
    // Single-tap alternative to dragging (WCAG 2.5.7).
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
    // The item's own detail page when it has one (else the toolbar's
    // "open on site" shows the collection page).
    final openItem = itemPath == null
        ? null
        : IconButton(
            key: ValueKey('openItem-${d.id}'),
            tooltip: context.tr('openItemOnSite'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => _openOnSite(context, itemPath),
          );
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 8),
      color: hidden ? context.pal.surfaceAlt.withValues(alpha: 0.7) : context.pal.surface,
      child: ListTile(
        leading: dragIndex != null
            ? ReorderableDragStartListener(index: dragIndex, child: const Icon(Icons.drag_indicator))
            : null,
        title: Row(children: [
          Flexible(
            child: Text(_title(d),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: hidden ? context.pal.muted : context.pal.ink)),
          ),
          if (hidden) _Tag(context.tr('hidden'), context.pal.muted),
          if (unconfirmed) _Tag(context.tr('unconfirmed'), context.pal.goldText),
        ]),
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
          // Phones: the move buttons (and the item's page link, which every
          // item has since PR #14) get their own row so the title keeps its width.
          if (narrow && (moves.isNotEmpty || openItem != null))
            Wrap(children: [...moves, ?openItem]),
        ]),
        onTap: () => _openEditor(context, d),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!narrow) ...moves,
          if (!narrow && openItem != null) openItem,
          if (def.hasVisible)
            IconButton(
              tooltip: context.tr(hidden ? 'show' : 'hide'),
              icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: hidden ? context.pal.muted : context.pal.success),
              onPressed: () => _setVisible(context, d, hidden),
            ),
          IconButton(
            tooltip: context.tr('delete'),
            icon: Icon(Icons.delete_outline, color: context.pal.alert),
            onPressed: () => _confirmDelete(context, d),
          ),
        ]),
      ),
    );
  }

  Future<void> _setVisible(BuildContext context, AdminDoc d, bool visible) async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = context.tr(visible ? 'nowVisible' : 'nowHidden');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    try {
      await widget.repo.update(def.name, d.id, {'visible': visible});
      messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    }
  }

  Future<void> _reorder(BuildContext context, List<AdminDoc> docs, int from, int to) async {
    // onReorderItem already adjusts [to] for the removed item.
    final ids = [for (final d in docs) d.id];
    ids.insert(to, ids.removeAt(from));
    final messenger = ScaffoldMessenger.of(context);
    final ok = context.tr('orderSaved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    try {
      // Serving and departed priests share the `priests` collection: departed
      // fathers are numbered from 1000 so the two lists never collide.
      await widget.repo.reorder(def.name, ids, base: reorderBase(def));
      messenger.showSnackBar(SnackBar(content: Text(ok), duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    }
  }

  void _confirmDelete(BuildContext context, AdminDoc d) {
    final def = widget.def;
    if (def.name == 'categories') {
      _deleteCategory(context, d);
      return;
    }
    final title = _title(d);
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg = context.tr('deleteFailed', {'e': '{e}'});
    final repo = widget.repo;
    final media = repo.media;
    final docData = d.data;
    setState(() {
      _pendingDelete.schedule(d.id, () async {
        try {
          await repo.delete(def.name, d.id);
          if (media != null) {
            await Future.wait([
              for (final id in orphanedDocMediaIds(docData, null))
                media.delete(id).catchError((Object _) {}),
            ]);
          }
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(failedMsg.replaceAll('{e}', '$e'))));
        }
      });
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(context.tr('deletedUndo', {'n': title})),
        action: SnackBarAction(
          label: context.tr('undo'),
          onPressed: () {
            if (_pendingDelete.undo(d.id)) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }

  /// Deleting a custom category hides its items (visible: false) first and
  /// never deletes them (ADR-027); they can be moved to another category.
  Future<void> _deleteCategory(BuildContext context, AdminDoc d) async {
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg = context.tr('deleteFailed', {'e': '{e}'});
    final deletedMsg = context.tr('catDeleted');
    List<AdminDoc> entries;
    try {
      entries = await widget.repo.watch('entries').first.timeout(const Duration(seconds: 15));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failedMsg.replaceAll('{e}', '$e'))));
      return;
    }
    final inCat = entries.where((e) => e.data['categoryId'] == d.id).length;
    if (!context.mounted) return;
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
    if (ok != true) return;
    try {
      for (final id in entryIdsToHide(d.id, [for (final e in entries) (id: e.id, data: e.data)])) {
        await widget.repo.update('entries', id, {'visible': false});
      }
      await widget.repo.delete(def.name, d.id);
      messenger.showSnackBar(SnackBar(content: Text(deletedMsg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failedMsg.replaceAll('{e}', '$e'))));
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

  Future<void> _openEditor(BuildContext context, AdminDoc? d) async {
    bool usesLinks(List<FieldDef> fs) => fs.any((f) => f.linkPicker || usesLinks(f.subFields));
    final needsCats = def.fields.any((f) => f.dynamicOptions == 'categories');
    final needsProgram = def.fields.any((f) => f.dynamicOptions == 'venues' || f.dynamicOptions == 'audiences');
    final needsLinks = usesLinks(def.fields);
    final cats = needsCats || needsLinks ? await _read('categories') : const <AdminDoc>[];
    final pages = needsLinks ? await _read('pages') : const <AdminDoc>[];
    // Venues / audiences (ADR-041): the admin lists in settings/features
    // (defaults when none), read once when the editor opens.
    final settings = needsProgram ? await _read('settings') : const <AdminDoc>[];
    final features = settings.where((x) => x.id == 'features').firstOrNull;
    final programOpts = ProgramOptions.fromMap(features?.data ?? const {});
    if (!context.mounted) return;
    String name(AdminDoc x, String ar, String en) {
      final v = context.pick('${x.data[ar] ?? ''}', '${x.data[en] ?? ''}');
      return x.data['visible'] == false ? '$v ${context.tr('hiddenTag')}' : v;
    }

    final catChoices = [for (final c in sortAdminDocs(def, cats)) (c.id, name(c, 'nameAr', 'nameEn'))];
    final targets = [
      for (final t in linkTargets(
        pages: [for (final p in pages) (slug: '${p.data['slug'] ?? ''}', titleAr: name(p, 'titleAr', 'titleEn'), titleEn: name(p, 'titleAr', 'titleEn'))],
        categories: [for (final c in cats) (slug: '${c.data['slug'] ?? ''}', titleAr: name(c, 'nameAr', 'nameEn'), titleEn: name(c, 'nameAr', 'nameEn'))],
      ))
        (t.path, context.pick(t.labelAr, t.labelEn)),
    ];
    final taken = {
      for (final x in _lastDocs)
        if (x.id != d?.id && x.data['slug'] is String) x.data['slug'] as String,
    };
    List<(String, String)> optChoices(List<ProgramOption> l) => [for (final o in l) (o.key, context.pick(o.labelAr, o.labelEn))];
    _pushEditor(context, d,
        dynamicChoices: {
          'categories': catChoices,
          // The item's own key stays selectable even if the admin list no
          // longer holds it (a default key, Sentry review).
          'venues': optChoices(ProgramOptions.withUsed(
              programOpts.venues, ['${d?.data['venue'] ?? ''}'], programOpts.venue)),
          'audiences': optChoices(ProgramOptions.withUsed(
              programOpts.audiences, ['${d?.data['audience'] ?? ''}'], programOpts.audience)),
        }, linkTargets: needsLinks ? targets : const [], takenSlugs: taken);
  }

  void _pushEditor(BuildContext context, AdminDoc? d,
      {Map<String, List<(String, String)>> dynamicChoices = const {},
      List<(String, String)> linkTargets = const [],
      Set<String> takenSlugs = const {}}) {
    final label = context.pick(def.labelAr, def.labelEn);
    // The editor may save in several writes (gallery / extraFields go on
    // their own): the first one creates a new document, the rest merge into it.
    var id = d?.id;
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocEditor(
        title: '${context.tr(d == null ? 'add' : 'edit')} — $label',
        fields: def.fields,
        def: def,
        data: d?.data,
        docId: d?.id,
        newDefaults: def.newDefaults,
        onSave: (data) async => id = await widget.repo.save(def.name, id, data),
        media: widget.repo.media,
        dynamicChoices: dynamicChoices,
        linkTargets: linkTargets,
        takenSlugs: takenSlugs,
      ),
    ));
  }
}

/// [def]'s public page, with `?lang=en` when the dashboard is in English.
String publicPathFor(CollectionDef def, {required bool english}) {
  final path = def.publicPath.isEmpty ? '/' : def.publicPath;
  return english ? Uri.parse(path).replace(queryParameters: {'lang': 'en'}).toString() : path;
}

/// Public detail page of an item (PR #13 routes), or null when the item has
/// none: its collection has no detail pages, `detailsEnabled` is explicitly
/// false (missing = on, PR #14), the item is hidden, or it is an inactive clinic
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
  if (kind == DetailKind.clinic && data['active'] == false) return null;
  final path = detailPathFor(kind, id);
  return english ? '$path?lang=en' : path;
}

/// First `order` value minus 10 for [def]'s reorder (BUG-13).
int reorderBase(CollectionDef def) => def.id == 'departedPriests' ? 1000 : 0;

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
