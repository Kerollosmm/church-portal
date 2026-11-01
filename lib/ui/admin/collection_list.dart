import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/media.dart';
import '../../domain/time_format.dart';
import '../../domain/cairo_time.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';
import 'doc_editor.dart';

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
  ListFilter _filter = ListFilter.all;
  late Stream<List<AdminDoc>> _stream = widget.repo.watch(widget.def.name);

  @override
  void didUpdateWidget(covariant CollectionListScreen old) {
    super.didUpdateWidget(old);
    if (old.def.name != widget.def.name || old.repo != widget.repo) {
      _stream = widget.repo.watch(widget.def.name);
    }
  }

  @override
  void dispose() {
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
      backgroundColor: AppColors.cream,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-${def.id}',
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('add')),
      ),
      body: StreamBuilder<List<AdminDoc>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = sortAdminDocs(def, snap.data!.where((d) => def.matches(d.data)).toList());
          final docs = filterAdminDocs(def, all, query: _search.text, filter: _filter);
          final canReorder = def.orderable && _search.text.trim().isEmpty && _filter == ListFilter.all && docs.length > 1;
          return Column(children: [
            _toolbar(context, all.length, docs.length, canReorder),
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
                labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.burgundy),
                onSelected: (_) => setState(() => _filter = f),
              ),
          Text('  ${context.tr('showingCount', {'n': '$shown', 't': '$total'})}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (canReorder)
            Text('  ↕ ${context.tr('dragToReorder')}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ]),
    );
  }

  /// Opens [CollectionDef.publicPath] in a new tab on web (the dashboard stays
  /// open); elsewhere navigates to it in the app.
  void _openOnSite(BuildContext context) {
    final path = def.publicPath.isEmpty ? '/' : def.publicPath;
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
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 8),
      color: hidden ? const Color(0xFFF1ECE4) : Colors.white,
      child: ListTile(
        leading: dragIndex != null
            ? ReorderableDragStartListener(index: dragIndex, child: const Icon(Icons.drag_indicator))
            : null,
        title: Row(children: [
          Flexible(
            child: Text(_title(d),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: hidden ? AppColors.muted : AppColors.ink)),
          ),
          if (hidden) _Tag(context.tr('hidden'), AppColors.muted),
          if (unconfirmed) _Tag(context.tr('unconfirmed'), AppColors.goldText),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sub.isNotEmpty) Text(sub),
          if (updated != null)
            Text(
              context.tr('updatedBy', {'t': fmtDateTime(updated), 'u': d.updatedBy.isEmpty ? '—' : d.updatedBy}),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
        ]),
        onTap: () => _openEditor(context, d),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Single-tap alternative to dragging (WCAG 2.5.7).
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
              onPressed:
                  dragIndex == docs.length - 1 ? null : () => _reorder(context, docs, dragIndex, dragIndex + 1),
            ),
          ],
          if (def.hasVisible)
            IconButton(
              tooltip: context.tr(hidden ? 'show' : 'hide'),
              icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: hidden ? AppColors.muted : AppColors.success),
              onPressed: () => _setVisible(context, d, hidden),
            ),
          IconButton(
            tooltip: context.tr('delete'),
            icon: const Icon(Icons.delete_outline, color: AppColors.alert),
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

  Future<void> _confirmDelete(BuildContext context, AdminDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_title(d)),
        content: Text(context.tr('confirmDelete')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.alert),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deleted = context.tr('deleted');
    final failedMsg = context.tr('deleteFailed', {'e': '{e}'});
    try {
      await widget.repo.delete(def.name, d.id);
      // Best effort: the deleted item's inline image is no longer referenced.
      final media = widget.repo.media;
      for (final id in orphanedMediaIds(d.data['image'], null)) {
        media?.delete(id).catchError((Object _) {});
      }
      messenger.showSnackBar(SnackBar(content: Text(deleted)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failedMsg.replaceAll('{e}', '$e'))));
    }
  }

  void _openEditor(BuildContext context, AdminDoc? d) {
    final label = context.pick(def.labelAr, def.labelEn);
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocEditor(
        title: '${context.tr(d == null ? 'add' : 'edit')} — $label',
        fields: def.fields,
        def: def,
        data: d?.data,
        docId: d?.id,
        newDefaults: def.newDefaults,
        onSave: (data) => widget.repo.save(def.name, d?.id, data),
        media: widget.repo.media,
      ),
    ));
  }
}

/// First `order` value minus 10 for [def]'s reorder (BUG-13).
int reorderBase(CollectionDef def) => def.id == 'departedPriests' ? 1000 : 0;

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsetsDirectional.only(start: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}
