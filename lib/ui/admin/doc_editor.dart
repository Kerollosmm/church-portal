import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/image_processing.dart';
import '../../data/media_repository.dart';
import '../../domain/media.dart';
import '../../domain/time_format.dart';
import '../widgets/item_image.dart';
import 'admin_schema.dart';
import 'admin_validators.dart';

/// Picks an image file and returns its bytes (null = cancelled).
typedef ImageBytesPicker = Future<Uint8List?> Function();

Future<Uint8List?> pickImageFromDevice() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
  return x?.readAsBytes();
}

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

  /// Stores uploaded images (null = image fields accept pasted URLs only).
  final MediaRepository? media;

  /// File picker for image uploads (tests inject bytes).
  final ImageBytesPicker pickImage;

  /// Resize/compress pipeline for uploads (tests may inject a fake).
  final Future<EncodedImage> Function(Uint8List bytes) prepareImage;

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
    this.media,
    this.pickImage = pickImageFromDevice,
    this.prepareImage = prepareUpload,
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

  /// Image fields with a picked, compressed file waiting to be uploaded on save.
  final Map<String, EncodedImage> _pending = {};

  /// Image field currently being resized/compressed.
  String? _processing;

  /// Values as loaded: only fields that differ from these are saved.
  late Map<String, dynamic> _initialValues;

  bool get isNew => widget.data == null;

  /// Unsaved local edits (the church-info screen asks before reloading).
  bool get dirty => _dirty;
  bool get saving => _saving;

  @override
  void initState() {
    super.initState();
    final data = {...?widget.data};
    if (isNew) data.addAll(widget.newDefaults);
    for (final f in widget.fields) {
      _init(f, data[f.key]);
    }
    _initialValues = collect();
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
      case FieldType.image:
        final img = MediaImage.fromMap(v);
        _values[f.key] = img?.toMap();
        _text[f.key] = _ctrl(img?.alt ?? '');
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
        case FieldType.image:
          out[f.key] = _collectImage(f.key);
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

  /// The `image` map with the edited alt text (null = no image). A picked file
  /// that is not uploaded yet is a `pending` marker (replaced on save).
  Map<String, dynamic>? _collectImage(String key) {
    final alt = _text[key]!.text.trim();
    if (_pending.containsKey(key)) return {'source': MediaSource.inline, 'pending': true, if (alt.isNotEmpty) 'alt': alt};
    return MediaImage.fromMap(_values[key])?.copyWith(alt: alt).toMap();
  }

  Iterable<FieldDef> get _imageFields => widget.fields.where((f) => f.type == FieldType.image);

  /// Validates and saves. Returns true on success (visible for tests).
  Future<bool> save() async {
    if (_saving || _processing != null || !_formKey.currentState!.validate()) return false;
    var data = collect();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final docErr = validateDocument(widget.def, data);
    if (docErr != null) {
      messenger?.showSnackBar(SnackBar(content: Text(context.tr(docErr))));
      return false;
    }
    final savedMsg = context.tr('saved');
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    // Existing docs: write only what changed (merge), never stale values.
    var payload = isNew ? data : changedFields(_initialValues, data);
    if (payload.isEmpty && _pending.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(context.tr('noChanges'))));
      setState(() => _dirty = false);
      if (widget.popOnSave && (route?.isCurrent ?? false)) nav.pop();
      return true;
    }
    setState(() => _saving = true);
    // Upload picked images first so the document references real media docs.
    final pendingBefore = Map<String, EncodedImage>.of(_pending);
    final valuesBefore = {for (final f in _imageFields) f.key: _values[f.key]};
    final uploaded = <String>[];
    try {
      for (final e in pendingBefore.entries) {
        final img = await widget.media!.upload(e.value, alt: _text[e.key]!.text.trim());
        uploaded.add(img.mediaId);
        _values[e.key] = img.toMap();
        _pending.remove(e.key);
      }
      if (uploaded.isNotEmpty) {
        data = collect();
        payload = isNew ? data : changedFields(_initialValues, data);
      }
      await widget.onSave(payload);
      // Best effort: drop inline images this edit replaced or removed.
      final orphans = [for (final f in _imageFields) ...orphanedMediaIds(_initialValues[f.key], data[f.key])];
      _initialValues = data;
      _deleteMedia(orphans);
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
      // The document was not saved: remove the images uploaded for it and
      // keep the picked files so the admin can retry.
      _deleteMedia(uploaded);
      _pending
        ..clear()
        ..addAll(pendingBefore);
      _values.addAll(valuesBefore);
      if (mounted) {
        messenger?.showSnackBar(SnackBar(content: Text(context.tr('saveFailed', {'e': '$e'}))));
        setState(() => _saving = false);
      }
      return false;
    }
  }

  void _deleteMedia(List<String> ids) {
    final media = widget.media;
    if (media == null) return;
    for (final id in ids) {
      unawaited(media.delete(id).catchError((Object _) {})); // orphan clean-up is best effort
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
      case FieldType.image:
        return _imageEditor(f);
      default:
        return _textField(f, _text[f.key]!);
    }
  }

  Future<void> _pickImage(FieldDef f) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    String msg(String k) => context.tr(k);
    final tooLarge = msg('imageTooLarge'), invalid = msg('imageInvalid'), empty = msg('imageEmpty');
    final Uint8List? bytes;
    try {
      bytes = await widget.pickImage();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(invalid)));
      return;
    }
    if (bytes == null || !mounted) return;
    if (bytes.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(empty)));
      return;
    }
    setState(() => _processing = f.key);
    try {
      final enc = await widget.prepareImage(bytes);
      final err = validateMediaBytes(enc.length);
      if (err != null) throw const ImageTooLargeException();
      if (!mounted) return;
      setState(() {
        _pending[f.key] = enc;
        _dirty = true;
      });
    } on ImageTooLargeException {
      messenger?.showSnackBar(SnackBar(content: Text(tooLarge)));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(invalid)));
    } finally {
      if (mounted) setState(() => _processing = null);
    }
  }

  Future<void> _askImageUrl(FieldDef f) async {
    final current = MediaImage.fromMap(_values[f.key]);
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _ImageUrlDialog(initial: current?.source == MediaSource.url ? current!.url : ''),
    );
    if (url == null || !mounted) return;
    setState(() {
      _pending.remove(f.key);
      _values[f.key] = MediaImage.url(url).toMap();
      _dirty = true;
    });
  }

  void _removeImage(FieldDef f) => setState(() {
        _pending.remove(f.key);
        _values[f.key] = null;
        _dirty = true;
      });

  Widget _imageEditor(FieldDef f) {
    final pending = _pending[f.key];
    final current = MediaImage.fromMap(_values[f.key]);
    final busy = _processing == f.key;
    final hasImage = pending != null || current != null;
    const placeholder = Icon(Icons.image_outlined, size: 40, color: AppColors.muted);
    final Widget preview = pending != null
        ? Image.memory(pending.bytes, key: const Key('imagePreviewPending'), fit: BoxFit.cover)
        : current != null
            ? MediaImageView(image: current, loader: widget.media?.load, placeholder: const Center(child: placeholder))
            : const Center(child: placeholder);
    final kb = (pending?.length ?? 0) / 1000;
    final status = busy
        ? context.tr('imageProcessing')
        : pending != null
            ? '${context.tr('imagePending')} • ${context.tr('imageSize', {
                'w': '${pending.w}',
                'h': '${pending.h}',
                'kb': kb.toStringAsFixed(0)
              })}'
            : current == null
                ? context.tr('imageNone')
                : (current.isRemote ? current.url : 'media/${current.mediaId}');
    return InputDecorator(
      key: ValueKey('field-${f.key}'),
      decoration: InputDecoration(labelText: _label(f), helperText: context.tr('imageHint'), helperMaxLines: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 96,
              height: 96,
              color: AppColors.parchment,
              child: busy ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : preview,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status,
                  key: const Key('imageStatus'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: const Key('imageUploadBtn'),
                  onPressed: widget.media == null || busy || _saving ? null : () => _pickImage(f),
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(context.tr('imageUpload')),
                ),
                OutlinedButton.icon(
                  key: const Key('imageUrlBtn'),
                  onPressed: busy || _saving ? null : () => _askImageUrl(f),
                  icon: const Icon(Icons.link_rounded),
                  label: Text(context.tr('imageUseUrl')),
                ),
                if (hasImage)
                  TextButton.icon(
                    key: const Key('imageRemoveBtn'),
                    onPressed: busy || _saving ? null : () => _removeImage(f),
                    icon: const Icon(Icons.delete_outline, color: AppColors.alert),
                    label: Text(context.tr('imageRemove'), style: const TextStyle(color: AppColors.alert)),
                  ),
              ]),
              if (widget.media == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.tr('imageUploadUnavailable'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
            ]),
          ),
        ]),
        if (hasImage) ...[
          const SizedBox(height: 10),
          TextField(
            key: const Key('imageAltInput'),
            controller: _text[f.key],
            maxLength: MediaLimits.maxAltLength,
            decoration: InputDecoration(labelText: context.tr('imageAlt'), counterText: ''),
          ),
        ],
      ]),
    );
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
            onPressed: rows.length >= f.maxRows
                ? null
                : () => setState(() {
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

/// Asks for an https image link (owns its controller, so it is disposed
/// only after the dialog's closing animation).
class _ImageUrlDialog extends StatefulWidget {
  final String initial;
  const _ImageUrlDialog({required this.initial});

  @override
  State<_ImageUrlDialog> createState() => _ImageUrlDialogState();
}

class _ImageUrlDialogState extends State<_ImageUrlDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _ok() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('imageUseUrl')),
        content: Form(
          key: _formKey,
          child: TextFormField(
            key: const Key('imageUrlInput'),
            controller: _ctrl,
            autofocus: true,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: context.tr('imageUrlLabel'), hintText: 'https://…'),
            validator: (v) => isValidImageUrl(v ?? '') ? null : context.tr('invalidUrl'),
            onFieldSubmitted: (_) => _ok(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
          FilledButton(key: const Key('imageUrlOk'), onPressed: _ok, child: Text(context.tr('ok'))),
        ],
      );
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
