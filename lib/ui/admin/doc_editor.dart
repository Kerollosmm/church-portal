import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/time_format.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';

/// Generic form editor driven by [FieldDef]s. Used for collection documents
/// and for the church-info document.
class DocEditor extends StatefulWidget {
  final String title;
  final List<FieldDef> fields;

  /// Existing data (null = new document).
  final Map<String, dynamic>? data;
  final String? docId;

  /// Values a new document starts with.
  final Map<String, Object?> newDefaults;

  /// Collection being edited (cross-field checks); null for single docs.
  final CollectionDef? def;

  /// Persists the collected values. Throwing shows "save failed".
  final Future<void> Function(Map<String, dynamic> data) onSave;

  /// Pop the route after a successful save (false when embedded in a page).
  final bool popOnSave;

  const DocEditor({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.data,
    this.docId,
    this.newDefaults = const {},
    this.def,
    this.popOnSave = true,
  });

  @override
  State<DocEditor> createState() => DocEditorState();
}

class DocEditorState extends State<DocEditor> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  final Map<String, dynamic> _values = {};

  /// objectList rows: field key -> rows of (subKey -> controller / value).
  final Map<String, List<_Row>> _rows = {};
  bool _saving = false;
  bool _dirty = false;

  bool get isNew => widget.data == null;

  @override
  void initState() {
    super.initState();
    final data = {...?widget.data};
    if (isNew) data.addAll(widget.newDefaults);
    for (final f in widget.fields) {
      _init(f, data[f.key]);
    }
  }

  void _init(FieldDef f, Object? v) {
    switch (f.type) {
      case FieldType.text:
      case FieldType.multiline:
      case FieldType.time:
      case FieldType.integer:
      case FieldType.decimal:
      case FieldType.looseDate:
      case FieldType.url:
      case FieldType.phone:
        _text[f.key] = _ctrl(v?.toString() ?? '');
      case FieldType.dateTime:
        _text[f.key] = _ctrl(v is DateTime ? fmtDateTime(v) : '');
      case FieldType.date:
        _text[f.key] = _ctrl(v is DateTime ? fmtDate(v) : '');
      case FieldType.boolean:
        _values[f.key] = v is bool ? v : (isNew ? f.newBool : f.missingBool);
      case FieldType.weekday:
        _values[f.key] = v is int ? v : null;
      case FieldType.weekdays:
        _values[f.key] = <int>{...((v as List?) ?? const []).whereType<int>()};
      case FieldType.choice:
        _values[f.key] = (v == null || v.toString().isEmpty)
            ? (f.nullableChoice ? null : (f.defaultOption ?? (f.options.isNotEmpty ? f.options.first : null)))
            : v.toString();
      case FieldType.objectList:
        _rows[f.key] = [
          for (final r in (v is List ? v : const []).whereType<Map>()) _Row.from(f.subFields, r, _markDirty),
        ];
    }
  }

  TextEditingController _ctrl(String text) => TextEditingController(text: text)..addListener(_markDirty);

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    for (final rows in _rows.values) {
      for (final r in rows) {
        r.dispose();
      }
    }
    super.dispose();
  }

  String? _validate(FieldDef f, String? raw) {
    final err = validateFieldValue(f, raw);
    return err == null ? null : context.tr(err);
  }

  /// Collected document (visible for tests).
  Map<String, dynamic> collect() {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case FieldType.boolean:
        case FieldType.weekday:
        case FieldType.choice:
          out[f.key] = _values[f.key];
        case FieldType.weekdays:
          out[f.key] = (_values[f.key] as Set<int>).toList()..sort();
        case FieldType.objectList:
          out[f.key] = [for (final r in _rows[f.key]!) r.collect()];
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.time:
        case FieldType.looseDate:
        case FieldType.url:
          out[f.key] = _text[f.key]!.text.trim();
        default:
          out[f.key] = parseFieldValue(f, _text[f.key]!.text);
      }
    }
    return out;
  }

  /// Validates and saves. Returns true on success (visible for tests).
  Future<bool> save() async {
    if (_saving || !_formKey.currentState!.validate()) return false;
    final data = collect();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final docErr = validateDocument(widget.def, data);
    if (docErr != null) {
      messenger?.showSnackBar(SnackBar(content: Text(context.tr(docErr))));
      return false;
    }
    final savedMsg = context.tr('saved');
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    setState(() => _saving = true);
    try {
      await widget.onSave(data);
      messenger?.showSnackBar(SnackBar(content: Text(savedMsg)));
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      // The admin may have closed the editor while the write was pending:
      // only pop if this editor is still the top route.
      if (widget.popOnSave && (route?.isCurrent ?? false)) nav.pop();
      return true;
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(SnackBar(content: Text(context.tr('saveFailed', {'e': '$e'}))));
        setState(() => _saving = false);
      }
      return false;
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.tr('discardChanges')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('keepEditing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('discard'))),
        ],
      ),
    );
    return ok == true;
  }

  String _label(FieldDef f) => context.pick(f.labelAr, f.labelEn) + (f.required ? ' *' : '');

  Widget _textField(FieldDef f, TextEditingController c) {
    final ltr = switch (f.type) {
      FieldType.text || FieldType.multiline => false,
      _ => true,
    };
    final hint = context.pick(f.hintAr, f.hintEn);
    return TextFormField(
      key: ValueKey('field-${f.key}'),
      controller: c,
      minLines: f.type == FieldType.multiline ? 3 : 1,
      maxLines: f.type == FieldType.multiline ? 12 : 1,
      textDirection: ltr ? TextDirection.ltr : null,
      keyboardType: switch (f.type) {
        FieldType.integer => TextInputType.number,
        FieldType.decimal => const TextInputType.numberWithOptions(decimal: true, signed: true),
        FieldType.phone => TextInputType.phone,
        FieldType.url => TextInputType.url,
        FieldType.multiline => TextInputType.multiline,
        _ => null,
      },
      validator: (v) => _validate(f, v),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: _label(f),
        helperText: hint.isEmpty ? null : hint,
        hintText: switch (f.type) {
          FieldType.time => '06:30',
          FieldType.dateTime => '2027-01-06 20:00',
          FieldType.date => '2027-01-06',
          FieldType.looseDate => '2009-03-08',
          FieldType.url => f.allowPath ? '/mass-schedule  /  https://…' : 'https://…',
          FieldType.phone => '01012345678',
          _ => null,
        },
      ),
    );
  }

  Widget _field(FieldDef f) {
    final label = _label(f);
    switch (f.type) {
      case FieldType.boolean:
        return SwitchListTile(
          key: ValueKey('field-${f.key}'),
          contentPadding: const EdgeInsetsDirectional.only(start: 4),
          title: Text(label),
          value: _values[f.key] as bool,
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
          }),
        );
      case FieldType.weekday:
        return DropdownButtonFormField<int?>(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key] as int?,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (var d = 1; d <= 7; d++)
              DropdownMenuItem<int?>(value: d, child: Text(weekdayName(d, arabic: context.isAr))),
          ],
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
          }),
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
                onSelected: (sel) => setState(() {
                  sel ? set.add(d) : set.remove(d);
                  _dirty = true;
                }),
              ),
          ]),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(labelText: label),
          validator: (v) => f.required && (v == null || v.isEmpty) ? context.tr('required') : null,
          items: [
            if (f.nullableChoice) const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final o in {...f.options, if (_values[f.key] != null) _values[f.key] as String})
              DropdownMenuItem<String?>(value: o, child: Text(choiceLabel(context, o))),
          ],
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
          }),
        );
      case FieldType.objectList:
        return _objectList(f);
      default:
        return _textField(f, _text[f.key]!);
    }
  }

  Widget _objectList(FieldDef f) {
    final rows = _rows[f.key]!;
    return InputDecorator(
      decoration: InputDecoration(labelText: _label(f)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++)
          Card(
            key: ObjectKey(rows[i]),
            color: AppColors.cream,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                for (final sf in f.subFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: switch (sf.type) {
                      FieldType.boolean => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_label(sf)),
                          value: rows[i].values[sf.key] as bool,
                          onChanged: (v) => setState(() {
                            rows[i].values[sf.key] = v;
                            _dirty = true;
                          }),
                        ),
                      FieldType.choice => DropdownButtonFormField<String>(
                          initialValue: rows[i].values[sf.key] as String?,
                          decoration: InputDecoration(labelText: _label(sf)),
                          items: [
                            for (final o in sf.options)
                              DropdownMenuItem(value: o, child: Text(choiceLabel(context, o))),
                          ],
                          onChanged: (v) => setState(() {
                            rows[i].values[sf.key] = v;
                            _dirty = true;
                          }),
                        ),
                      _ => _textField(sf, rows[i].text[sf.key]!),
                    },
                  ),
                Row(children: [
                  IconButton(
                    tooltip: context.tr('moveUp'),
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                              rows.insert(i - 1, rows.removeAt(i));
                              _dirty = true;
                            }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: context.tr('moveDown'),
                    onPressed: i == rows.length - 1
                        ? null
                        : () => setState(() {
                              rows.insert(i + 1, rows.removeAt(i));
                              _dirty = true;
                            }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      rows.removeAt(i).dispose();
                      _dirty = true;
                    }),
                    icon: const Icon(Icons.delete_outline, color: AppColors.alert),
                    label: Text(context.tr('remove'), style: const TextStyle(color: AppColors.alert)),
                  ),
                ]),
              ]),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              rows.add(_Row.from(f.subFields, const {}, _markDirty, isNew: true));
              _dirty = true;
            }),
            icon: const Icon(Icons.add),
            label: Text(context.tr('addRow')),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final embedded = !widget.popOnSave;
    return PopScope(
      canPop: embedded || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          setState(() => _dirty = false);
          nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: embedded
            ? null
            : AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              key: const Key('editor-save-top'),
              onPressed: _saving ? null : save,
              child: Text(context.tr('save'),
                  style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.docId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText('ID: ${widget.docId}', style: const TextStyle(color: AppColors.muted)),
                    ),
                  for (final f in widget.fields)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('editor-save'),
                    onPressed: _saving ? null : save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(context.tr('save')),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row {
  final Map<String, TextEditingController> text = {};
  final Map<String, Object?> values = {};
  final List<FieldDef> fields;
  _Row(this.fields);

  factory _Row.from(List<FieldDef> fields, Map data, VoidCallback onChange, {bool isNew = false}) {
    final r = _Row(fields);
    for (final f in fields) {
      final v = data[f.key];
      switch (f.type) {
        case FieldType.boolean:
          r.values[f.key] = v is bool ? v : (isNew ? f.newBool : f.missingBool);
        case FieldType.choice:
          final s = v?.toString() ?? '';
          r.values[f.key] =
              f.options.contains(s) ? s : (f.defaultOption ?? (f.options.isNotEmpty ? f.options.first : null));
        default:
          r.text[f.key] = TextEditingController(text: v?.toString() ?? '')..addListener(onChange);
      }
    }
    return r;
  }

  Map<String, dynamic> collect() => {
        for (final f in fields)
          f.key: switch (f.type) {
            FieldType.boolean || FieldType.choice => values[f.key],
            FieldType.phone => normalizePhoneInput(text[f.key]!.text.trim()),
            _ => text[f.key]!.text.trim(),
          },
      };

  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
  }
}

/// Human labels for stored option keys (falls back to the key).
String choiceLabel(BuildContext context, String key) {
  final k = 'opt_$key';
  final t = context.tr(k);
  return t == k ? key : t;
}
