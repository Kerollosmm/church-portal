import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/coptic_cross.dart';
import 'admin_schema.dart';

/// Hidden /admin area: email/password sign-in, then CRUD editors.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(adminRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const CopticCross(size: 26), const SizedBox(width: 8), Text(context.tr('admin'))]),
        leading: IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/')),
        actions: [
          IconButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            icon: Text(context.isAr ? 'EN' : 'ع',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.goldLight)),
          ),
        ],
      ),
      body: repo == null
          ? Center(child: Text(context.tr('adminUnavailable')))
          : StreamBuilder<User?>(
              stream: repo.authChanges(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final user = snap.data;
                if (user == null) return _LoginForm(repo: repo);
                return FutureBuilder<bool>(
                  key: ValueKey(user.uid),
                  future: repo.isAdmin(user.uid),
                  builder: (context, adm) {
                    if (!adm.hasData) return const Center(child: CircularProgressIndicator());
                    if (adm.data != true) {
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.lock_outline, size: 48, color: AppColors.alert),
                          const SizedBox(height: 8),
                          Text(context.tr('notAdmin')),
                          Text(user.email ?? '', style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: repo.signOut, child: Text(context.tr('signOut'))),
                        ]),
                      );
                    }
                    return _Dashboard(repo: repo, user: user);
                  },
                );
              },
            ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  final AdminRepository repo;
  const _LoginForm({required this.repo});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final failed = context.tr('signInFailed');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.signIn(_email.text, _password.text);
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AutofillGroup(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(context.tr('signIn'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.burgundy)),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                  decoration:
                      InputDecoration(labelText: context.tr('password'), prefixIcon: const Icon(Icons.lock_outline)),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: AppColors.alert)),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(context.tr('signIn')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AdminRepository repo;
  final User user;
  const _Dashboard({required this.repo, required this.user});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: adminCollections.length,
      child: Column(children: [
        Container(
          color: AppColors.parchment,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.verified_user, color: AppColors.success, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(user.email ?? user.uid, overflow: TextOverflow.ellipsis)),
            TextButton.icon(onPressed: repo.signOut, icon: const Icon(Icons.logout), label: Text(context.tr('signOut'))),
          ]),
        ),
        TabBar(
          isScrollable: true,
          labelColor: AppColors.burgundy,
          indicatorColor: AppColors.gold,
          tabs: [for (final c in adminCollections) Tab(text: context.pick(c.labelAr, c.labelEn))],
        ),
        Expanded(
          child: TabBarView(children: [for (final c in adminCollections) _CollectionList(repo: repo, def: c)]),
        ),
      ]),
    );
  }
}

class _CollectionList extends StatelessWidget {
  final AdminRepository repo;
  final CollectionDef def;
  const _CollectionList({required this.repo, required this.def});

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
    if (d.data['seasonKey'] != null) parts.add('${d.data['seasonKey']}');
    if (d.data['active'] == false) parts.add('⛔');
    for (final k in ['startsAt', 'endsAt']) {
      final v = d.data[k];
      if (v is DateTime) parts.add(_fmtDateTime(v));
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('add')),
      ),
      body: StreamBuilder<List<AdminDoc>>(
        stream: repo.watch(def.name),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!;
          if (docs.isEmpty) return Center(child: Text(context.tr('noItems')));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              return Card(
                child: ListTile(
                  title: Text(_title(d), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_subtitle(context, d)),
                  onTap: () => _openEditor(context, d),
                  trailing: IconButton(
                    tooltip: context.tr('delete'),
                    icon: const Icon(Icons.delete_outline, color: AppColors.alert),
                    onPressed: () => _confirmDelete(context, d),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AdminDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.tr('confirmDelete')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (ok == true) await repo.delete(def.name, d.id);
  }

  void _openEditor(BuildContext context, AdminDoc? d) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DocEditor(repo: repo, def: def, doc: d),
    ));
  }
}

String _fmtDateTime(DateTime v) {
  final c = CairoTime.fromInstant(v);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${c.year}-${two(c.month)}-${two(c.day)} ${two(c.hour)}:${two(c.minute)}';
}

String _fmtDate(DateTime v) {
  final c = CairoTime.calendarDate(v);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${c.year}-${two(c.month)}-${two(c.day)}';
}

/// Generic form editor driven by [CollectionDef].
class DocEditor extends StatefulWidget {
  final AdminRepository repo;
  final CollectionDef def;
  final AdminDoc? doc;
  const DocEditor({super.key, required this.repo, required this.def, this.doc});

  @override
  State<DocEditor> createState() => _DocEditorState();
}

class _DocEditorState extends State<DocEditor> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Map<String, dynamic> _values = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data ?? const <String, dynamic>{};
    for (final f in widget.def.fields) {
      final v = data[f.key];
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.time:
          _text[f.key] = TextEditingController(text: v?.toString() ?? '');
        case FieldType.integer:
          _text[f.key] = TextEditingController(text: v?.toString() ?? '');
        case FieldType.dateTime:
          _text[f.key] = TextEditingController(text: v is DateTime ? _fmtDateTime(v) : '');
        case FieldType.date:
          _text[f.key] = TextEditingController(text: v is DateTime ? _fmtDate(v) : '');
        case FieldType.boolean:
          _values[f.key] = v is bool ? v : (widget.doc == null);
        case FieldType.weekday:
          _values[f.key] = v is int ? v : null;
        case FieldType.weekdays:
          _values[f.key] = <int>{...((v as List?) ?? const []).whereType<int>()};
        case FieldType.choice:
          _values[f.key] = (v == null || v.toString().isEmpty)
              ? (f.nullableChoice ? null : (f.options.isNotEmpty ? f.options.first : null))
              : v.toString();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static final _timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  static final _dateTimeRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$');
  static final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  String? _validate(FieldDef f, String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return f.required ? context.tr('required') : null;
    final ok = switch (f.type) {
      FieldType.time => _timeRe.hasMatch(v),
      FieldType.integer => int.tryParse(v) != null,
      FieldType.dateTime => _dateTimeRe.hasMatch(v),
      FieldType.date => _dateRe.hasMatch(v),
      _ => true,
    };
    return ok ? null : context.tr('invalid');
  }

  Map<String, dynamic> _collect() {
    final out = <String, dynamic>{};
    for (final f in widget.def.fields) {
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.time:
          out[f.key] = _text[f.key]!.text.trim();
        case FieldType.integer:
          out[f.key] = int.tryParse(_text[f.key]!.text.trim()) ?? 0;
        case FieldType.dateTime:
          final m = _dateTimeRe.firstMatch(_text[f.key]!.text.trim());
          out[f.key] = m == null
              ? null
              : CairoTime.at(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!) * 60 + int.parse(m[5]!))
                  .toUtc();
        case FieldType.date:
          final m = _dateRe.firstMatch(_text[f.key]!.text.trim());
          out[f.key] = m == null ? null : CairoTime.at(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).toUtc();
        case FieldType.boolean:
        case FieldType.weekday:
        case FieldType.choice:
          out[f.key] = _values[f.key];
        case FieldType.weekdays:
          out[f.key] = (_values[f.key] as Set<int>).toList()..sort();
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final savedMsg = context.tr('saved');
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await widget.repo.save(widget.def.name, widget.doc?.id, _collect());
      messenger.showSnackBar(SnackBar(content: Text(savedMsg)));
      nav.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.tr('saveFailed', {'e': '$e'}))));
        setState(() => _saving = false);
      }
    }
  }

  Widget _field(FieldDef f) {
    final label = context.pick(f.labelAr, f.labelEn) + (f.required ? ' *' : '');
    switch (f.type) {
      case FieldType.text:
      case FieldType.multiline:
      case FieldType.time:
      case FieldType.integer:
      case FieldType.dateTime:
      case FieldType.date:
        final ltr = f.type != FieldType.text && f.type != FieldType.multiline;
        return TextFormField(
          controller: _text[f.key],
          minLines: f.type == FieldType.multiline ? 3 : 1,
          maxLines: f.type == FieldType.multiline ? 8 : 1,
          textDirection: ltr ? TextDirection.ltr : null,
          keyboardType: f.type == FieldType.integer ? TextInputType.number : null,
          validator: (v) => _validate(f, v),
          decoration: InputDecoration(
            labelText: label,
            hintText: switch (f.type) {
              FieldType.time => '06:30',
              FieldType.dateTime => '2027-01-06 20:00',
              FieldType.date => '2027-01-06',
              _ => null,
            },
          ),
        );
      case FieldType.boolean:
        return SwitchListTile(
          title: Text(label),
          value: _values[f.key] as bool,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.weekday:
        return DropdownButtonFormField<int?>(
          initialValue: _values[f.key] as int?,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (var d = 1; d <= 7; d++)
              DropdownMenuItem<int?>(value: d, child: Text(weekdayName(d, arabic: context.isAr))),
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.weekdays:
        final set = _values[f.key] as Set<int>;
        return InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(weekdayName(d, arabic: context.isAr)),
                selected: set.contains(d),
                onSelected: (sel) => setState(() => sel ? set.add(d) : set.remove(d)),
              ),
          ]),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String?>(
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(labelText: label),
          validator: (v) => f.required && (v == null || v.isEmpty) ? context.tr('required') : null,
          items: [
            if (f.nullableChoice) const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final o in f.options) DropdownMenuItem<String?>(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${context.tr(widget.doc == null ? 'add' : 'edit')} — ${context.pick(widget.def.labelAr, widget.def.labelEn)}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(context.tr('save'), style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.doc != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('ID: ${widget.doc!.id}', style: const TextStyle(color: AppColors.muted)),
                  ),
                for (final f in widget.def.fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(context.tr('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

