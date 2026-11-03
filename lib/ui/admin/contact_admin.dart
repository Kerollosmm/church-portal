import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/contact_categories.dart';
import 'doc_editor.dart' show choiceLabel;

/// Admin editor of the contact-form categories (`settings/contact`, ADR-028):
/// add, rename, reorder, hide or delete types, choose their behaviour
/// (general / booking / complaint / suggestion), allow anonymous sending for
/// complaints and suggestions, and edit the booking occasions.
class ContactCategoriesScreen extends StatefulWidget {
  final AdminBackend repo;
  const ContactCategoriesScreen({super.key, required this.repo});

  @override
  State<ContactCategoriesScreen> createState() => _ContactCategoriesScreenState();
}

class _ContactCategoriesScreenState extends State<ContactCategoriesScreen> {
  late Stream<AdminDoc?> _stream = widget.repo.watchDoc('settings/contact');
  List<ContactCategory>? _cats;

  /// Ids removed in this editor: a category added afterwards never reuses
  /// one (its old messages keep their own label / "Other" box).
  final Set<String> _retired = {};
  bool _dirty = false;
  bool _saving = false;
  final _form = GlobalKey<FormState>();

  /// Bumped when the list is (re)loaded so the text fields re-read their values.
  int _gen = 0;

  @override
  void didUpdateWidget(covariant ContactCategoriesScreen old) {
    super.didUpdateWidget(old);
    if (old.repo != widget.repo) {
      _stream = widget.repo.watchDoc('settings/contact');
      _cats = null;
    }
  }

  void _edit(int i, ContactCategory c) => setState(() {
        _cats![i] = c;
        _dirty = true;
      });

  /// Orders 10, 20, 30… following the on-screen order.
  List<ContactCategory> _renumbered() =>
      [for (var i = 0; i < _cats!.length; i++) _cats![i].copyWith(order: (i + 1) * 10)];

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('saved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    setState(() => _saving = true);
    try {
      await widget.repo.saveDoc('settings/contact', ContactSettings(_renumbered()).toMap());
      messenger.showSnackBar(SnackBar(content: Text(saved)));
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: _cats == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('saveContactCats'),
              onPressed: _saving || !_dirty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(context.tr('save')),
            ),
      body: StreamBuilder<AdminDoc?>(
        key: ObjectKey(_stream),
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}')));
          }
          if (snap.connectionState == ConnectionState.waiting && _cats == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // First load (or a remote change while nothing is edited here).
          if (_cats == null || !_dirty) {
            final next = ContactSettings.fromMap(snap.data?.data).categories;
            if (_cats == null || !_same(_cats!, next)) {
              _cats = [...next];
              _gen++;
            }
          }
          return _editor(context);
        },
      ),
    );
  }

  static bool _same(List<ContactCategory> a, List<ContactCategory> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i].toMap(), y = b[i].toMap();
      if (a[i].slot != b[i].slot || x.toString() != y.toString()) return false;
    }
    return true;
  }

  Widget _editor(BuildContext context) {
    final cats = _cats!;
    final full = cats.length >= contactMaxCategories;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        Text(context.tr('contactCatsHint'), style: const TextStyle(color: AppColors.muted, height: 1.6)),
        const SizedBox(height: 12),
        for (var i = 0; i < cats.length; i++) _card(context, i, cats[i]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('addContactCat'),
            onPressed: full
                ? null
                : () => setState(() {
                      // A fresh stable id, never one removed in this editor.
                      final id = ContactSettings(cats).newId(retired: _retired)!;
                      cats.add(ContactCategory(slot: id, labelAr: '', order: (cats.length + 1) * 10));
                      _dirty = true;
                    }),
            icon: const Icon(Icons.add),
            label: Text(context.tr('addContactCat')),
          ),
        ),
      ]),
    );
  }

  Widget _card(BuildContext context, int i, ContactCategory c) {
    final cats = _cats!;
    String? req(String? v, int max) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return context.tr('required');
      return t.length > max ? context.tr('tooLong') : null;
    }

    String? opt(String? v, int max) => (v ?? '').trim().length > max ? context.tr('tooLong') : null;
    return Card(
      key: ValueKey('contactCat-${c.slot}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            key: ValueKey('catLabelAr-${c.slot}-$_gen'),
            initialValue: c.labelAr,
            decoration: InputDecoration(labelText: '${context.tr('labelAr')} *'),
            validator: (v) => req(v, contactLabelMax),
            onChanged: (v) => _edit(i, cats[i].copyWith(labelAr: v.trim())),
          ),
          TextFormField(
            key: ValueKey('catLabelEn-${c.slot}-$_gen'),
            initialValue: c.labelEn,
            decoration: InputDecoration(labelText: context.tr('labelEn')),
            validator: (v) => opt(v, contactLabelMax),
            onChanged: (v) => _edit(i, cats[i].copyWith(labelEn: v.trim())),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('catKind-${c.slot}'),
            isExpanded: true,
            initialValue: c.kind,
            decoration: InputDecoration(labelText: context.tr('kindLabel')),
            items: [
              for (final k in ContactKinds.all) DropdownMenuItem(value: k, child: Text(choiceLabel(context, k))),
            ],
            onChanged: (v) => v == null
                ? null
                : _edit(
                    i,
                    cats[i].copyWith(
                        kind: v,
                        anonymous: ContactKinds.anonymousCapable.contains(v) && cats[i].anonymous,
                        subtypes: v == ContactKinds.booking ? cats[i].subtypes : const [])),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('catShownOnForm')),
            value: c.on,
            onChanged: (v) => _edit(i, cats[i].copyWith(on: v)),
          ),
          if (ContactKinds.anonymousCapable.contains(c.kind))
            SwitchListTile(
              key: ValueKey('catAnon-${c.slot}'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('catAllowAnon')),
              value: c.anonymous,
              onChanged: (v) => _edit(i, cats[i].copyWith(anonymous: v)),
            ),
          if (c.isBooking) ...[
            const SizedBox(height: 4),
            Text(context.tr('subtypesLabel'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (var j = 0; j < c.subtypes.length; j++)
              Row(key: ValueKey('sub-${c.slot}-${c.subtypes[j].key}'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('subAr-${c.slot}-${c.subtypes[j].key}-$_gen'),
                    initialValue: c.subtypes[j].labelAr,
                    decoration: InputDecoration(labelText: '${context.tr('labelAr')} *'),
                    validator: (v) => req(v, subtypeLabelMax),
                    onChanged: (v) {
                      final subs = [...cats[i].subtypes];
                      subs[j] = ContactSubtype(subs[j].key, v.trim().replaceAll('|', '/'), subs[j].labelEn);
                      _edit(i, cats[i].copyWith(subtypes: subs));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('subEn-${c.slot}-${c.subtypes[j].key}-$_gen'),
                    initialValue: c.subtypes[j].labelEn,
                    decoration: InputDecoration(labelText: context.tr('labelEn')),
                    validator: (v) => opt(v, subtypeLabelMax),
                    onChanged: (v) {
                      final subs = [...cats[i].subtypes];
                      subs[j] = ContactSubtype(subs[j].key, subs[j].labelAr, v.trim().replaceAll('|', '/'));
                      _edit(i, cats[i].copyWith(subtypes: subs));
                    },
                  ),
                ),
                IconButton(
                  tooltip: context.tr('remove'),
                  icon: const Icon(Icons.close, color: AppColors.alert),
                  onPressed: () => _edit(i, cats[i].copyWith(subtypes: [...cats[i].subtypes]..removeAt(j))),
                ),
              ]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('addSub-${c.slot}'),
                onPressed: c.subtypes.length >= contactMaxSubtypes
                    ? null
                    : () => _edit(
                        i,
                        cats[i].copyWith(subtypes: [
                          ...cats[i].subtypes,
                          ContactSubtype(newSubtypeKey(cats[i].subtypes.map((s) => s.key)), '', ''),
                        ])),
                icon: const Icon(Icons.add),
                label: Text(context.tr('addSubtype')),
              ),
            ),
          ],
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: context.tr('moveUp'),
                onPressed: i == 0
                    ? null
                    : () => setState(() {
                          cats.insert(i - 1, cats.removeAt(i));
                          _dirty = true;
                        }),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: context.tr('moveDown'),
                onPressed: i == cats.length - 1
                    ? null
                    : () => setState(() {
                          cats.insert(i + 1, cats.removeAt(i));
                          _dirty = true;
                        }),
                icon: const Icon(Icons.arrow_downward),
              ),
            ]),
            TextButton.icon(
              key: ValueKey('removeCat-${c.slot}'),
              onPressed: cats.length <= 1
                  ? null
                  : () => setState(() {
                        _retired.add(cats.removeAt(i).slot);
                        _dirty = true;
                      }),
              icon: const Icon(Icons.delete_outline, color: AppColors.alert),
              label: Text(context.tr('remove'), style: const TextStyle(color: AppColors.alert)),
            ),
          ]),
        ]),
      ),
    );
  }
}
