import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/features.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';
import 'doc_editor.dart';

/// Dashboard home: counts, quick links, latest edits.
class OverviewScreen extends StatefulWidget {
  final AdminBackend repo;
  final String role;
  final void Function(String screenId) onOpen;
  const OverviewScreen({super.key, required this.repo, required this.role, required this.onOpen});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// Latest docs per collection (null = still loading / failed).
  final Map<String, List<AdminDoc>?> _docs = {};
  final Set<String> _failed = {};
  AdminDoc? _features;
  bool _featuresLoaded = false;
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    final names = {for (final c in adminCollections) c.name, 'contact_messages'};
    for (final n in names) {
      _subs.add(widget.repo.watch(n).listen(
            (d) => setState(() => _docs[n] = d),
            onError: (_) => setState(() => _failed.add(n)),
          ));
    }
    _subs.add(widget.repo.watchDoc('settings/features').listen(
          (d) => setState(() {
            _features = d;
            _featuresLoaded = true;
          }),
          onError: (_) => setState(() => _failed.add('settings/features')),
        ));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onOpen = widget.onOpen;
    final messages = _docs['contact_messages'];
    final newMessages = messages?.where((d) => d.data['status'] != 'handled').length ?? 0;
    final f = FeatureSettings.fromMap(_features?.data);
    final edited = <(String, AdminDoc)>[
      for (final e in _docs.entries)
        if (e.key != 'contact_messages')
          for (final d in e.value ?? const <AdminDoc>[])
            if (d.updatedAt != null) (e.key, d),
    ]..sort((a, b) => b.$2.updatedAt!.compareTo(a.$2.updatedAt!));
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(context.tr('overviewTitle'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.burgundy)),
        const SizedBox(height: 4),
        Text(context.tr('overviewHint'), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _StatCard(
            icon: Icons.mail_outline,
            label: context.tr('newMessages'),
            value: _failed.contains('contact_messages') ? '—' : (messages == null ? '…' : '$newMessages'),
            color: newMessages > 0 ? AppColors.alert : AppColors.burgundy,
            onTap: () => onOpen('messages'),
          ),
          _StatCard(
            icon: Icons.toggle_on_outlined,
            label: context.tr('sectionsOn'),
            value: _failed.contains('settings/features')
                ? '—'
                : (_featuresLoaded ? '${Sections.all.length - f.disabledCount}/${Sections.all.length}' : '…'),
            onTap: () => onOpen('features'),
          ),
          for (final c in adminCollections) _countCard(context, c),
        ]),
        const SizedBox(height: 20),
        Text(context.tr('quickLinks'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
              avatar: const Icon(Icons.church_outlined, size: 18),
              label: Text(context.tr('churchInfo')),
              onPressed: () => onOpen('church')),
          ActionChip(
              avatar: const Icon(Icons.toggle_on_outlined, size: 18),
              label: Text(context.tr('featuresAndHome')),
              onPressed: () => onOpen('features')),
          ActionChip(
              avatar: const Icon(Icons.campaign_outlined, size: 18),
              label: Text(context.tr('alertsShort')),
              onPressed: () => onOpen('alerts')),
          ActionChip(
              avatar: const Icon(Icons.open_in_new, size: 18),
              label: Text(context.tr('openSite')),
              onPressed: () => openUrl(Uri.base.resolve('/').toString())),
        ]),
        const SizedBox(height: 20),
        Text(context.tr('recentEdits'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (edited.isEmpty)
          Text(context.tr('noRecentEdits'), style: const TextStyle(color: AppColors.muted))
        else
          Card(
            child: Column(children: [
              for (final e in edited.take(8))
                ListTile(
                  dense: true,
                  leading: Icon(adminIcon(_iconFor(e.$1)), color: AppColors.burgundy),
                  title: Text(_titleOf(e.$2), overflow: TextOverflow.ellipsis),
                  subtitle: Text(context.tr('updatedBy', {'t': fmtDateTime(e.$2.updatedAt!), 'u': e.$2.updatedBy})),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _countCard(BuildContext context, CollectionDef def) {
    final all = _docs[def.name];
    final docs = (all ?? const <AdminDoc>[]).where((d) => def.matches(d.data)).toList();
    final hidden = docs.where((d) => d.data['visible'] == false).length;
    final pending = docs.where((d) => d.data['sample'] == true).length;
    final sub = [
      if (hidden > 0) '${context.tr('hidden')}: $hidden',
      if (pending > 0) '${context.tr('unconfirmed')}: $pending',
    ].join(' • ');
    return _StatCard(
      icon: adminIcon(def.icon),
      label: context.pick(def.labelAr, def.labelEn),
      value: _failed.contains(def.name) ? '—' : (all == null ? '…' : '${docs.length}'),
      sub: sub.isEmpty ? null : sub,
      onTap: () => widget.onOpen(def.id),
    );
  }

  static String _iconFor(String col) {
    for (final c in adminCollections) {
      if (c.name == col) return c.icon;
    }
    return 'list';
  }

  static String _titleOf(AdminDoc d) {
    for (final k in ['titleAr', 'nameAr', 'name', 'doctorName', 'titleEn', 'nameEn']) {
      final v = d.data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return d.id;
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final VoidCallback onTap;
  final Color color;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap,
      this.sub,
      this.color = AppColors.burgundy});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: color),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
                Text(label,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}

IconData adminIcon(String name) => switch (name) {
      'alerts' => Icons.campaign_outlined,
      'seasons' => Icons.event_note_outlined,
      'liturgies' => Icons.access_time_outlined,
      'meetings' => Icons.school_outlined,
      'clinics' => Icons.local_hospital_outlined,
      'services' => Icons.volunteer_activism_outlined,
      'activities' => Icons.groups_outlined,
      'priests' => Icons.person_outline,
      'departed' => Icons.local_florist_outlined,
      'saints' => Icons.auto_awesome_outlined,
      'milestones' => Icons.history_edu_outlined,
      _ => Icons.list_alt,
    };

/// settings/church as a form. A newer stored version replaces the form only
/// when it has no unsaved edits; otherwise a banner offers a reload.
class ChurchInfoScreen extends StatefulWidget {
  final AdminBackend repo;
  const ChurchInfoScreen({super.key, required this.repo});

  @override
  State<ChurchInfoScreen> createState() => _ChurchInfoScreenState();
}

class _ChurchInfoScreenState extends State<ChurchInfoScreen> {
  late final Stream<AdminDoc?> _stream = widget.repo.watchDoc(churchInfoDoc.path);
  GlobalKey<DocEditorState> _editorKey = GlobalKey<DocEditorState>();
  AdminDoc? _shown;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final latest = snap.data;
        final changed = !_loaded || latest?.updatedAt != _shown?.updatedAt || (latest == null) != (_shown == null);
        final editor = _editorKey.currentState;
        final dirty = editor != null && editor.dirty && !editor.saving;
        if (changed && !dirty) {
          if (_loaded) _editorKey = GlobalKey<DocEditorState>();
          _shown = latest;
          _loaded = true;
        }
        final stale = changed && dirty;
        final doc = _shown;
        return Column(children: [
          if (stale)
            MaterialBanner(
              content: Text(context.tr('updatedElsewhere')),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    _shown = latest;
                    _editorKey = GlobalKey<DocEditorState>();
                  }),
                  child: Text(context.tr('reload')),
                ),
              ],
            ),
          if (doc?.updatedAt != null)
            Container(
              width: double.infinity,
              color: AppColors.parchment,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(context.tr('updatedBy', {'t': fmtDateTime(doc!.updatedAt!), 'u': doc.updatedBy}),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          Expanded(
            child: DocEditor(
              key: _editorKey,
              title: context.pick(churchInfoDoc.labelAr, churchInfoDoc.labelEn),
              fields: churchInfoDoc.fields,
              data: doc?.data ?? const {},
              popOnSave: false,
              onSave: (data) => widget.repo.saveDoc(churchInfoDoc.path, data),
            ),
          ),
        ]);
      },
    );
  }
}

/// contact_messages inbox: read, mark handled, delete.
class MessagesScreen extends StatefulWidget {
  final AdminBackend repo;
  const MessagesScreen({super.key, required this.repo});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  String _filter = 'new';
  late final Stream<List<AdminDoc>> _stream = widget.repo.watch('contact_messages');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: StreamBuilder<List<AdminDoc>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = [...snap.data!]..sort((a, b) {
              final ta = a.data['createdAt'], tb = b.data['createdAt'];
              if (ta is DateTime && tb is DateTime) return tb.compareTo(ta);
              return ta is DateTime ? -1 : (tb is DateTime ? 1 : 0);
            });
          final list = all.where((d) {
            final handled = d.data['status'] == 'handled';
            return _filter == 'all' || (_filter == 'new' ? !handled : handled);
          }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 6, children: [
                for (final f in ['new', 'handled', 'all'])
                  ChoiceChip(
                    label: Text(context.tr('msg_$f')),
                    selected: _filter == f,
                    showCheckmark: false,
                    labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.burgundy),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(context.tr('noMessages')))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _message(context, list[i]),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _message(BuildContext context, AdminDoc d) {
    final m = d.data;
    final handled = m['status'] == 'handled';
    final created = m['createdAt'];
    final phone = (m['phone'] ?? '').toString();
    final email = (m['email'] ?? '').toString();
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 8),
      color: handled ? const Color(0xFFF4F1EA) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(handled ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                color: handled ? AppColors.muted : AppColors.burgundy),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${m['name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            if (created is DateTime)
              Text(fmtDateTime(created), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          SelectableText('${m['message'] ?? ''}', style: const TextStyle(height: 1.6)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (phone.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.call, size: 16),
                label: Text(phone, textDirection: TextDirection.ltr),
                onPressed: () => callPhone(phone),
              ),
            if (email.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.email_outlined, size: 16),
                label: Text(email, textDirection: TextDirection.ltr),
                onPressed: () => openUrl('mailto:$email'),
              ),
            if (m['lang'] != null) Text('(${m['lang']})', style: const TextStyle(color: AppColors.muted)),
          ]),
          const Divider(height: 18),
          Row(children: [
            TextButton.icon(
              onPressed: () => _setStatus(context, d, handled ? 'new' : 'handled'),
              icon: Icon(handled ? Icons.undo : Icons.check_circle_outline),
              label: Text(context.tr(handled ? 'markNew' : 'markHandled')),
            ),
            const Spacer(),
            IconButton(
              tooltip: context.tr('copy'),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => Clipboard.setData(ClipboardData(text: '${m['name']}\n$phone $email\n${m['message']}')),
            ),
            IconButton(
              tooltip: context.tr('delete'),
              icon: const Icon(Icons.delete_outline, color: AppColors.alert),
              onPressed: () => _delete(context, d),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _setStatus(BuildContext context, AdminDoc d, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('saveFailed', {'e': '{e}'});
    try {
      await widget.repo.update('contact_messages', d.id, {'status': status});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    }
  }

  Future<void> _delete(BuildContext context, AdminDoc d) async {
    final ok = await confirmDialog(context, context.tr('confirmDeleteMessage'));
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deleted = context.tr('deleted');
    final failed = context.tr('deleteFailed', {'e': '{e}'});
    try {
      await widget.repo.delete('contact_messages', d.id);
      messenger.showSnackBar(SnackBar(content: Text(deleted)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    }
  }
}

Future<bool> confirmDialog(BuildContext context, String text, {String? action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.alert),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action ?? context.tr('delete')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Owner-only: list, add, change role, remove admins.
class AdminsScreen extends StatefulWidget {
  final AdminBackend repo;
  final String selfUid;
  const AdminsScreen({super.key, required this.repo, required this.selfUid});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  late final Stream<List<AdminDoc>> _stream = widget.repo.watch('admins');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-admin',
        onPressed: () => _addDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: Text(context.tr('addAdmin')),
      ),
      body: StreamBuilder<List<AdminDoc>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final admins = [...snap.data!]..sort((a, b) => '${a.data['email']}'.compareTo('${b.data['email']}'));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            Card(
              color: AppColors.parchment,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(context.tr('adminsHelp'), style: const TextStyle(height: 1.6)),
              ),
            ),
            const SizedBox(height: 8),
            for (final a in admins) _tile(context, a),
          ]);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, AdminDoc a) {
    final self = a.id == widget.selfUid;
    final role = a.data['role'] == AdminRoles.owner ? AdminRoles.owner : AdminRoles.editor;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(role == AdminRoles.owner ? Icons.workspace_premium_outlined : Icons.edit_note,
            color: AppColors.burgundy),
        title: Text('${a.data['email'] ?? ''}${self ? ' (${context.tr('you')})' : ''}', textDirection: TextDirection.ltr),
        subtitle: SelectableText('UID: ${a.id}', style: const TextStyle(fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<String>(
            value: role,
            onChanged: self
                ? null
                : (v) => v == null ? null : _guard(context, () => widget.repo.setAdmin(a.id, email: '${a.data['email'] ?? ''}', role: v)),
            items: [
              for (final r in AdminRoles.all) DropdownMenuItem(value: r, child: Text(context.tr('role_$r'))),
            ],
          ),
          IconButton(
            tooltip: context.tr('removeAdmin'),
            icon: Icon(Icons.person_remove_outlined, color: self ? AppColors.muted : AppColors.alert),
            onPressed: self
                ? null
                : () async {
                    if (await confirmDialog(context, context.tr('confirmRemoveAdmin'), action: context.tr('removeAdmin')) &&
                        context.mounted) {
                      await _guard(context, () => widget.repo.removeAdmin(a.id));
                    }
                  },
          ),
        ]),
      ),
    );
  }

  Future<void> _guard(BuildContext context, Future<void> Function() op) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = context.tr('saved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    try {
      await op();
      messenger.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    }
  }

  Future<void> _addDialog(BuildContext context) async {
    final uid = TextEditingController();
    final email = TextEditingController();
    var role = AdminRoles.editor;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.tr('addAdmin')),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: uid,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'UID *', helperText: context.tr('uidHelp')),
                  validator: (v) => isValidAdminUid(v ?? '') ? null : context.tr('invalid'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: email,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                      ? null
                      : context.tr('errEmail'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: context.tr('role')),
                  items: [
                    for (final r in AdminRoles.all) DropdownMenuItem(value: r, child: Text(context.tr('role_$r'))),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? AdminRoles.editor),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: Text(context.tr('add')),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      await _guard(context, () => widget.repo.setAdmin(uid.text.trim(), email: email.text.trim(), role: role));
    }
    uid.dispose();
    email.dispose();
  }
}

/// Firebase Auth UIDs are 1–128 chars without '/'.
bool isValidAdminUid(String v) {
  final s = v.trim();
  return s.isNotEmpty && s.length <= 128 && RegExp(r'^[A-Za-z0-9_\-:.]+$').hasMatch(s);
}
