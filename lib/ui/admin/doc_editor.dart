import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/image_processing.dart';
import '../../data/media_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/media.dart';
import '../../domain/rules.dart' show normalizeDigits;
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

  /// Run-time options of [FieldDef.dynamicOptions] choice fields:
  /// source name → (stored value, label) pairs (e.g. the custom categories).
  final Map<String, List<(String, String)>> dynamicChoices;

  /// Targets offered by [FieldDef.linkPicker] URL fields (ADR-027).
  final List<(String, String)> linkTargets;

  /// Slugs other documents of this collection already use (ADR-027).
  final Set<String> takenSlugs;

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
    this.dynamicChoices = const {},
    this.linkTargets = const [],
    this.takenSlugs = const {},
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

  /// The values before the first attempt of a save that has not completed
  /// yet. A failed later chunk advances [_initialValues] past a cover the
  /// first chunk replaced; its media id is still cleaned up from this
  /// baseline once a retry completes the save.
  Map<String, dynamic>? _saveBaseline;

  /// [FieldType.imageList] fields: photos in display order.
  final Map<String, List<_GalleryEntry>> _gallery = {};

  /// Collapsible group cards (opened when they hold an invalid field).
  final Map<FieldGroup, ExpansibleController> _groupCtl = {
    for (final g in FieldGroup.values)
      if (g != FieldGroup.basic) g: ExpansibleController(),
  };

  /// The document exists: an existing one, or a new one whose first write
  /// succeeded (later writes then send only what changed).
  late bool _persisted = !isNew;

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
          for (final r in (v is List ? v : const []))
            if (r is Map)
              _Row.from(f.subFields, r, _markDirty)
            else if (f.encodedRows && r is String)
              _Row.from(f.subFields, _decodeRow(f, r), _markDirty),
        ];
      case FieldType.image:
        final img = MediaImage.fromMap(v);
        _values[f.key] = img?.toMap();
        _text[f.key] = _ctrl(img?.alt ?? '');
      case FieldType.imageList:
        _gallery[f.key] = [
          for (final e in (v is List ? v : const []))
            if (MediaImage.fromMap(e) case final MediaImage img) _GalleryEntry(img, null, _ctrl(img.alt)),
        ];
    }
  }

  static const _rowSep = '\u001f';

  /// [FieldDef.encodedRows]: sub-field values in order, joined by U+001F.
  static String _encodeRow(FieldDef f, Map<String, dynamic> row) => encodeRowFields(f, row, _rowSep);

  static Map<String, dynamic> _decodeRow(FieldDef f, String s) {
    final parts = s.split(_rowSep);
    return {for (var i = 0; i < f.subFields.length; i++) f.subFields[i].key: i < parts.length ? parts[i] : ''};
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
    for (final list in _gallery.values) {
      for (final g in list) {
        g.alt.dispose();
      }
    }
    for (final c in _groupCtl.values) {
      c.dispose();
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
          out[f.key] = [
            for (final r in _rows[f.key]!) f.encodedRows ? _encodeRow(f, r.collect()) : r.collect(),
          ];
        case FieldType.image:
          out[f.key] = _collectImage(f.key);
        case FieldType.imageList:
          out[f.key] = [for (final g in _gallery[f.key]!) g.collect()];
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

  bool get _hasPendingUploads => _pending.isNotEmpty || _gallery.values.any((l) => l.any((g) => g.pending != null));

  /// Opens every collapsed group holding an invalid field, so its error is
  /// never hidden in a closed card. Returns true when one was opened.
  bool _openInvalidGroups() {
    final bad = <FieldGroup>{};
    for (final f in widget.fields) {
      if (f.group == FieldGroup.basic) continue;
      final c = _text[f.key];
      if (c != null && f.type != FieldType.image && validateFieldValue(f, c.text) != null) bad.add(f.group);
      for (final r in _rows[f.key] ?? const <_Row>[]) {
        if (validateRowAnyOf(f, {for (final e in r.text.entries) e.key: e.value.text}) != null) bad.add(f.group);
        for (final sf in f.subFields) {
          final rc = r.text[sf.key];
          if (rc != null && validateFieldValue(sf, rc.text) != null) bad.add(f.group);
        }
      }
    }
    var opened = false;
    for (final g in bad) {
      final c = _groupCtl[g]!;
      if (!c.isExpanded) {
        c.expand();
        opened = true;
      }
    }
    return opened;
  }

  /// Validates and saves. Returns true on success (visible for tests).
  ///
  /// Writes go one after the other: everything else first (it creates a new
  /// document), then the `gallery`, then the `extraFields` (see
  /// [splitSavePayload]: one write with both lists at their maximum exceeds
  /// the 1,000 expressions Firestore rules evaluate per request). A write
  /// that fails leaves the earlier ones saved; a retry sends only the rest.
  Future<bool> save() async {
    if (_saving || _processing != null) return false;
    if (!_formKey.currentState!.validate()) {
      if (_openInvalidGroups()) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('checkHighlighted'))));
      }
      return false;
    }
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
    var payload = _persisted ? changedFields(_initialValues, data) : data;
    // A new document does not write an unset image style (ADR-023): missing
    // already means "section default", and rules that predate the field
    // keep accepting the save.
    if (!_persisted && payload['imageStyle'] == null) payload = {...payload}..remove('imageStyle');
    if (payload.isEmpty && !_hasPendingUploads) {
      messenger?.showSnackBar(SnackBar(content: Text(context.tr('noChanges'))));
      setState(() => _dirty = false);
      if (widget.popOnSave && (route?.isCurrent ?? false)) nav.pop();
      return true;
    }
    setState(() => _saving = true);
    // Upload picked images first so the document references real media docs.
    final pendingBefore = Map<String, EncodedImage>.of(_pending);
    final valuesBefore = {for (final f in _imageFields) f.key: _values[f.key]};
    final galleryUploads = <_GalleryEntry, EncodedImage>{};
    final uploaded = <String>[];
    final initialBefore = _initialValues;
    final baseline = _saveBaseline ??= _initialValues;
    try {
      for (final e in pendingBefore.entries) {
        final img = await widget.media!.upload(e.value, alt: _text[e.key]!.text.trim());
        uploaded.add(img.mediaId);
        _values[e.key] = img.toMap();
        _pending.remove(e.key);
      }
      for (final list in _gallery.values) {
        for (final g in list) {
          final enc = g.pending;
          if (enc == null) continue;
          final img = await widget.media!.upload(enc, alt: g.alt.text.trim());
          uploaded.add(img.mediaId);
          galleryUploads[g] = enc;
          g
            ..image = img
            ..pending = null;
        }
      }
      if (uploaded.isNotEmpty) {
        data = collect();
        payload = _persisted ? changedFields(_initialValues, data) : data;
      }
      for (final chunk in splitSavePayload(payload)) {
        await widget.onSave(chunk);
        _persisted = true;
        _initialValues = {..._initialValues, ...chunk};
      }
      _initialValues = data;
      // Best effort: drop inline images this edit replaced or removed (an
      // image moved between the cover and the gallery is still referenced).
      // Measured from the first attempt's baseline too, so a cover replaced
      // by an earlier, partly failed attempt of this save is not left behind.
      _deleteMedia({...orphanedDocMediaIds(baseline, data), ...orphanedDocMediaIds(initialBefore, data)}.toList());
      _saveBaseline = null;
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
      // The failed write (and those after it) did not save: remove the images
      // uploaded for them and keep the picked files so the admin can retry.
      // Images an earlier write of this save already stored stay. A timeout
      // is different: Firestore keeps the write queued (offline) and may
      // still commit it, pointing at those images, so they are kept (BUG-13).
      final stored = extractDocMediaIds(_initialValues);
      if (e is! TimeoutException) _deleteMedia([for (final id in uploaded) if (!stored.contains(id)) id]);
      for (final p in pendingBefore.entries) {
        final id = MediaImage.fromMap(_values[p.key])?.ownedMediaId;
        if (id != null && uploaded.contains(id) && stored.contains(id)) continue;
        _pending[p.key] = p.value;
        _values[p.key] = valuesBefore[p.key];
      }
      for (final u in galleryUploads.entries) {
        if (stored.contains(u.key.image?.mediaId)) continue;
        u.key
          ..pending = u.value
          ..image = null;
      }
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

  /// Time / date / date-time fields are read-only and filled from the
  /// pickers (ADR-049): a clock or calendar icon (and a tap on the field)
  /// opens [showTimePicker] as a 12-hour AM/PM picker (ص/م in Arabic) /
  /// [showDatePicker]. Storage stays 24-hour: the text is strictly "HH:mm",
  /// "YYYY-MM-DD" or "YYYY-MM-DD HH:mm" (Cairo wall time, parsed to the same
  /// stored instant as before); [_pickedReading] shows the 12-hour reading.
  static bool _picked(FieldType t) => t == FieldType.time || t == FieldType.date || t == FieldType.dateTime;

  Future<void> _pick(FieldDef f, TextEditingController c) async {
    final now = CairoTime.now();
    Future<(int, int)?> time((int, int)? current) async {
      final init = current ?? (f.type == FieldType.time ? (18, 0) : (now.hour, now.minute));
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: init.$1, minute: init.$2),
        helpText: _label(f),
        builder: (ctx, child) {
          // The theme's containers match the dialog surface, so mark the
          // chosen ص/م (AM/PM) like the chosen hour on the dial.
          final theme = Theme.of(ctx), cs = theme.colorScheme;
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
            child: Theme(
              data: theme.copyWith(
                timePickerTheme: theme.timePickerTheme.copyWith(
                  dayPeriodColor: WidgetStateColor.resolveWith(
                      (s) => s.contains(WidgetState.selected) ? cs.primary : Colors.transparent),
                  dayPeriodTextColor: WidgetStateColor.resolveWith(
                      (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.onSurface),
                ),
              ),
              child: child!,
            ),
          );
        },
      );
      return t == null ? null : (t.hour, t.minute);
    }

    if (f.type == FieldType.time) {
      final t = await time(parseFieldTime(c.text));
      if (t != null && mounted) c.text = formatPickedTime(t.$1, t.$2);
      return;
    }
    final cur = parseFieldDateTime(c.text);
    final initial = cur == null ? DateTime(now.year, now.month, now.day) : DateTime(cur.$1, cur.$2, cur.$3);
    final first = DateTime(2000), last = DateTime(2100, 12, 31);
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      helpText: _label(f),
    );
    if (d == null || !mounted) return;
    if (f.type == FieldType.date) {
      c.text = formatPickedDate(d.year, d.month, d.day);
      return;
    }
    final t = await time(cur == null ? null : (cur.$4, cur.$5));
    if (t == null || !mounted) return;
    c.text = formatPickedDateTime(d.year, d.month, d.day, t.$1, t.$2);
  }

  /// The friendly 12-hour reading of a picked time / date-time field, shown
  /// under it: "٠٦:٣٠ م" / "06:30 PM", with the date first for date-times;
  /// null when blank or not a valid value (the field then shows its hint).
  String? _pickedReading(FieldDef f, String raw) {
    final ar = context.isAr;
    String time(int h, int m) => (ar ? formatTimeArabic : formatTimeLatin)(formatPickedTime(h, m));
    if (f.type == FieldType.time) {
      final t = parseFieldTime(raw);
      return t == null ? null : time(t.$1, t.$2);
    }
    if (f.type != FieldType.dateTime) return null;
    final d = parseFieldDateTime(raw);
    if (d == null || dateTimeRe.firstMatch(normalizeDigits(raw.trim())) == null) return null;
    return '${formatDate(DateTime(d.$1, d.$2, d.$3), arabic: ar)}${ar ? '، ' : ', '}${time(d.$4, d.$5)}';
  }

  Widget? _pickerSuffix(FieldDef f, TextEditingController c) {
    if (!_picked(f.type)) return null;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, v, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (!f.required && v.text.trim().isNotEmpty)
          IconButton(
            key: ValueKey('clear-${f.key}'),
            tooltip: context.tr('clearField'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => c.clear(),
          ),
        IconButton(
          key: ValueKey('pick-${f.key}'),
          tooltip: context.tr(f.type == FieldType.time ? 'pickTime' : 'pickDate'),
          icon: Icon(f.type == FieldType.time ? Icons.access_time_rounded : Icons.calendar_month_rounded),
          onPressed: () => _pick(f, c),
        ),
      ]),
    );
  }

  Widget _textField(FieldDef f, TextEditingController c, {String? Function()? rowError}) {
    if (f.type == FieldType.time || f.type == FieldType.dateTime) {
      // Rebuilds with the value so the 12-hour reading follows each pick.
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (context, v, _) => _textFieldBody(f, c, rowError, _pickedReading(f, v.text)),
      );
    }
    return _textFieldBody(f, c, rowError, null);
  }

  Widget _textFieldBody(FieldDef f, TextEditingController c, String? Function()? rowError, String? reading) {
    final picked = _picked(f.type);
    final ltr = switch (f.type) {
      FieldType.text || FieldType.multiline => false,
      _ => true,
    };
    final hint = [reading ?? '', context.pick(f.hintAr, f.hintEn)].where((s) => s.isNotEmpty).join('\n');
    return TextFormField(
      key: ValueKey('field-${f.key}'),
      controller: c,
      readOnly: picked,
      onTap: picked ? () => _pick(f, c) : null,
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
      validator: (v) =>
          _validate(f, v) ??
          (f.slug && widget.takenSlugs.contains((v ?? '').trim()) ? context.tr('slugTaken') : null) ??
          rowError?.call(),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: _label(f),
        helperText: hint.isEmpty ? null : hint,
        helperMaxLines: reading == null ? 3 : 4,
        suffixIcon: _pickerSuffix(f, c) ?? (f.linkPicker && widget.linkTargets.isNotEmpty
            ? IconButton(
                key: ValueKey('linkPick-${f.key}'),
                tooltip: context.tr('linkPick'),
                icon: const Icon(Icons.link_rounded),
                onPressed: () => _pickLink(c),
              )
            : null),
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

  /// "Pick a page…": custom pages, categories and built-in routes.
  Future<void> _pickLink(TextEditingController c) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('linkPickTitle')),
        children: [
          for (final t in widget.linkTargets)
            SimpleDialogOption(
              key: ValueKey('linkTarget-${t.$1}'),
              onPressed: () => Navigator.pop(ctx, t.$1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(t.$1, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: context.pal.muted)),
              ]),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    c.text = picked;
  }

  Widget _field(FieldDef f) {
    final label = _label(f);
    switch (f.type) {
      case FieldType.boolean:
        // The field's hint under the switch (e.g. `replacesDay`, ADR-050).
        final hint = context.pick(f.hintAr, f.hintEn);
        return SwitchListTile(
          key: ValueKey('field-${f.key}'),
          contentPadding: const EdgeInsetsDirectional.only(start: 4),
          title: Text(label),
          subtitle: hint.isEmpty ? null : Text(hint),
          value: _values[f.key] as bool,
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
          }),
        );
      case FieldType.weekday:
        return DropdownButtonFormField<int?>(
          key: ValueKey('field-${f.key}'),
          isExpanded: true, // long labels ellipsize at 320 px / 200% text
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
                checkmarkColor: context.pal.onBar,
                labelStyle: TextStyle(
                  color: set.contains(d) ? context.pal.onBar : context.pal.primary,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (sel) => setState(() {
                  sel ? set.add(d) : set.remove(d);
                  _dirty = true;
                }),
              ),
          ]),
        );
      case FieldType.choice when f.dynamicOptions.isNotEmpty:
        final opts = widget.dynamicChoices[f.dynamicOptions] ?? const <(String, String)>[];
        final cur = _values[f.key] as String?;
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          isExpanded: true,
          initialValue: cur,
          decoration: InputDecoration(labelText: label),
          validator: (v) => f.required && (v == null || v.isEmpty) ? context.tr('required') : null,
          items: [
            if (f.nullableChoice || cur == null) const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final o in opts) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
            // A value whose option is gone (e.g. a deleted category).
            if (cur != null && !opts.any((o) => o.$1 == cur))
              DropdownMenuItem<String?>(value: cur, child: Text(context.tr('noCategory'))),
          ],
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
          }),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          isExpanded: true, // long labels ellipsize at 320 px / 200% text
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
      case FieldType.imageList:
        return _galleryEditor(f);
      default:
        return _textField(f, _text[f.key]!);
    }
  }

  Future<void> _pickImage(FieldDef f) => _pickFromDevice(f.key, (enc) => _pending[f.key] = enc);

  /// Adds a picked photo to the [FieldType.imageList] field [f] (uploaded on save).
  Future<void> _pickGalleryImage(FieldDef f) =>
      _pickFromDevice(f.key, (enc) => _gallery[f.key]!.add(_GalleryEntry(null, enc, _ctrl(''))));

  Future<void> _addGalleryUrl(FieldDef f) async {
    final url = await showDialog<String>(context: context, builder: (_) => const _ImageUrlDialog(initial: ''));
    if (url == null || !mounted) return;
    setState(() {
      _gallery[f.key]!.add(_GalleryEntry(MediaImage.url(url), null, _ctrl('')));
      _dirty = true;
    });
  }

  /// Picks, resizes and compresses an image, then hands it to [onReady]
  /// (inside setState). [key] marks the field as busy meanwhile.
  Future<void> _pickFromDevice(String key, void Function(EncodedImage enc) onReady) async {
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
    setState(() => _processing = key);
    try {
      final enc = await widget.prepareImage(bytes);
      final err = validateMediaBytes(enc.length);
      if (err != null) throw const ImageTooLargeException();
      if (!mounted) return;
      setState(() {
        onReady(enc);
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
    final placeholder = Icon(Icons.image_outlined, size: 40, color: context.pal.muted);
    final Widget preview = pending != null
        ? Image.memory(pending.bytes, key: const Key('imagePreviewPending'), fit: BoxFit.cover)
        : current != null
            ? MediaImageView(image: current, loader: widget.media?.load, placeholder: Center(child: placeholder))
            : Center(child: placeholder);
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
    // Narrow screens or large text: preview above the status and buttons.
    final stack = MediaQuery.sizeOf(context).width < 420 || MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    final previewBox = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        color: context.pal.surfaceAlt,
        child: busy ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : preview,
      ),
    );
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(status,
          key: const Key('imageStatus'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.pal.muted, fontSize: 12)),
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
            icon: Icon(Icons.delete_outline, color: context.pal.alert),
            label: Text(context.tr('imageRemove'), style: TextStyle(color: context.pal.alert)),
          ),
      ]),
      if (widget.media == null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(context.tr('imageUploadUnavailable'),
              style: TextStyle(color: context.pal.muted, fontSize: 11)),
        ),
    ]);
    return InputDecorator(
      key: ValueKey('field-${f.key}'),
      decoration: InputDecoration(labelText: _label(f), helperText: context.tr('imageHint'), helperMaxLines: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?_hintWarning(f),
        if (stack)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            previewBox,
            const SizedBox(height: 12),
            controls,
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            previewBox,
            const SizedBox(width: 12),
            Expanded(child: controls),
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

  /// A field's own warning (e.g. BR-11 on meetings' photos), shown above
  /// its image controls; null when the field has none.
  Widget? _hintWarning(FieldDef f) {
    final hint = context.pick(f.hintAr, f.hintEn);
    if (hint.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: context.pal.alert, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Text(hint,
              key: ValueKey('fieldHint-${f.key}'),
              style: TextStyle(color: context.pal.alert, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ]),
    );
  }

  static const _groupTitles = {
    FieldGroup.program: 'groupProgram',
    FieldGroup.details: 'groupDetails',
    FieldGroup.media: 'groupMedia',
    FieldGroup.contacts: 'groupContacts',
  };
  static const _groupIcons = {
    FieldGroup.program: Icons.campaign_outlined,
    FieldGroup.details: Icons.article_outlined,
    FieldGroup.media: Icons.photo_library_outlined,
    FieldGroup.contacts: Icons.contact_phone_outlined,
  };

  /// A collapsible card for one detail-page group. Collapsed fields stay
  /// mounted (maintainState) so the form still validates and collects them.
  Widget _groupCard(FieldGroup g) {
    final fields = [for (final f in widget.fields) if (f.group == g) f];
    return Card(
      key: ValueKey('groupCard-${g.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('group-${g.name}'),
        controller: _groupCtl[g],
        maintainState: true,
        leading: Icon(_groupIcons[g], color: context.pal.primary),
        title: Text(context.tr(_groupTitles[g]!),
            style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.primary)),
        subtitle: _pills(g, fields),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
        ],
      ),
    );
  }

  /// Live status pills under a group title ("Enabled", "3 fields", "4 photos").
  Widget _pills(FieldGroup g, List<FieldDef> fields) {
    List<String> labels() {
      switch (g) {
        case FieldGroup.details:
          final rows = [for (final f in fields) if (f.type == FieldType.objectList) ..._rows[f.key]!];
          return [
            if (fields.any((f) => f.key == 'detailsEnabled'))
              context.tr(_values['detailsEnabled'] == true ? 'pillEnabled' : 'pillDisabled'),
            if (rows.isNotEmpty) context.tr('pillFields', {'n': '${rows.length}'}),
          ];
        case FieldGroup.media:
          final photos = [for (final f in fields) if (f.type == FieldType.imageList) ..._gallery[f.key]!].length;
          final cover = fields.any(
              (f) => f.type == FieldType.image && (_pending.containsKey(f.key) || MediaImage.fromMap(_values[f.key]) != null));
          return [
            if (photos > 0) context.tr('pillPhotos', {'n': '$photos'}),
            if (cover) context.tr('pillCover'),
            if (photos == 0 && !cover) context.tr('pillNoPhotos'),
          ];
        case FieldGroup.program:
        case FieldGroup.contacts:
        case FieldGroup.basic:
          final n = [
            for (final f in fields)
              if (_text[f.key] case final TextEditingController c when c.text.trim().isNotEmpty)
                f
              // A chosen venue / audience counts too (CodeRabbit review on PR #32).
              else if (f.type == FieldType.choice && '${_values[f.key] ?? ''}'.isNotEmpty && g == FieldGroup.program)
                f,
          ].length;
          return [context.tr(n > 0 ? 'pillFilled' : 'pillEmpty', {'n': '$n'})];
      }
    }

    Widget wrap() => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [for (final l in labels()) _Pill(l)]),
        );
    // Text counts follow typing (the form only rebuilds on its first edit).
    final controllers = [for (final f in fields) ?_text[f.key]];
    return g == FieldGroup.contacts || g == FieldGroup.program
        ? ListenableBuilder(listenable: Listenable.merge(controllers), builder: (_, _) => wrap())
        : wrap();
  }

  Widget _galleryEditor(FieldDef f) {
    final list = _gallery[f.key]!;
    final busy = _processing == f.key;
    final full = list.length >= f.maxRows;
    final stack = MediaQuery.sizeOf(context).width < 420 || MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    return InputDecorator(
      key: ValueKey('field-${f.key}'),
      decoration: InputDecoration(
        labelText: _label(f),
        helperText: context.tr('galleryHint', {'n': '${f.maxRows}'}),
        helperMaxLines: 4,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?_hintWarning(f),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.tr('galleryEmpty'), style: TextStyle(color: context.pal.muted, fontSize: 12)),
          ),
        for (var i = 0; i < list.length; i++) _galleryItem(list, i, stack),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: const Key('galleryUploadBtn'),
            onPressed: widget.media == null || busy || _saving || full ? null : () => _pickGalleryImage(f),
            icon: const Icon(Icons.upload_rounded),
            label: Text(context.tr('galleryUpload')),
          ),
          OutlinedButton.icon(
            key: const Key('galleryUrlBtn'),
            onPressed: busy || _saving || full ? null : () => _addGalleryUrl(f),
            icon: const Icon(Icons.link_rounded),
            label: Text(context.tr('galleryAddUrl')),
          ),
          Text(context.tr('galleryCount', {'n': '${list.length}', 'max': '${f.maxRows}'}),
              key: const Key('galleryCount'), style: TextStyle(color: context.pal.muted, fontSize: 12)),
          if (busy) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (widget.media == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('imageUploadUnavailable'),
                style: TextStyle(color: context.pal.muted, fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _galleryItem(List<_GalleryEntry> list, int i, bool stack) {
    final g = list[i];
    final placeholder = Center(child: Icon(Icons.image_outlined, size: 32, color: context.pal.muted));
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        color: context.pal.surfaceAlt,
        child: g.pending != null
            ? Image.memory(g.pending!.bytes, key: const Key('galleryPreviewPending'), fit: BoxFit.cover)
            : MediaImageView(image: g.image!, loader: widget.media?.load, placeholder: placeholder),
      ),
    );
    void move(int to) => setState(() {
          list.insert(to, list.removeAt(i));
          _dirty = true;
        });
    final locked = _saving || _processing != null;
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('galleryPhoto', {'n': '${i + 1}'}), style: const TextStyle(fontWeight: FontWeight.w700)),
      TextField(
        key: ValueKey('galleryAlt-$i'),
        controller: g.alt,
        maxLength: MediaLimits.maxAltLength,
        decoration: InputDecoration(labelText: context.tr('imageAlt'), counterText: ''),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(
          key: ValueKey('galleryUp-$i'),
          tooltip: context.tr('moveEarlier'),
          onPressed: i == 0 || locked ? null : () => move(i - 1),
          icon: const Icon(Icons.arrow_upward),
        ),
        IconButton(
          key: ValueKey('galleryDown-$i'),
          tooltip: context.tr('moveLater'),
          onPressed: i == list.length - 1 || locked ? null : () => move(i + 1),
          icon: const Icon(Icons.arrow_downward),
        ),
        TextButton.icon(
          key: ValueKey('galleryRemove-$i'),
          onPressed: locked
              ? null
              : () => setState(() {
                    list.removeAt(i).alt.dispose();
                    _dirty = true;
                  }),
          icon: Icon(Icons.delete_outline, color: context.pal.alert),
          label: Text(context.tr('galleryRemove'), style: TextStyle(color: context.pal.alert)),
        ),
      ]),
    ]);
    return Card(
      key: ObjectKey(g),
      color: context.pal.background,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: stack
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [preview, const SizedBox(height: 8), controls])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                preview,
                const SizedBox(width: 12),
                Expanded(child: controls),
              ]),
      ),
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
            color: context.pal.background,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                for (final sf in f.subFields)
                  if (sf.showWhen == null || sf.showWhen!.value.contains(rows[i].values[sf.showWhen!.key]))
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
                          isExpanded: true,
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
                      _ => _textField(sf, rows[i].text[sf.key]!,
                          rowError: f.rowRequireAnyOf.isNotEmpty && f.rowRequireAnyOf.first == sf.key
                              ? () {
                                  final err = validateRowAnyOf(f, {
                                    for (final e in rows[i].text.entries) e.key: e.value.text,
                                  });
                                  return err == null ? null : context.tr(err);
                                }
                              : f.rowNotBefore?.key == sf.key
                                  ? () {
                                      final err = validateRowOrder(f, {
                                        for (final e in rows[i].text.entries) e.key: e.value.text,
                                      });
                                      return err == null ? null : context.tr(err);
                                    }
                                  : f.rowUniqueKey == sf.key
                                      ? () {
                                          final err = validateRowUnique(
                                              f, [for (final r in rows) r.text[sf.key]?.text ?? ''], i);
                                          return err == null ? null : context.tr(err);
                                        }
                                      : null),
                    },
                  ),
                // Wrap: at 320 px / 200% text the buttons flow onto two lines.
                Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
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
                  ]),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      rows.removeAt(i).dispose();
                      _dirty = true;
                    }),
                    icon: Icon(Icons.delete_outline, color: context.pal.alert),
                    label: Text(context.tr('remove'), style: TextStyle(color: context.pal.alert)),
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
        backgroundColor: context.pal.background,
        appBar: embedded
            ? null
            : AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              key: const Key('editor-save-top'),
              onPressed: _saving ? null : save,
              child: Text(context.tr('save'),
                  style: TextStyle(color: context.pal.onPrimaryAccent, fontWeight: FontWeight.w800)),
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
                      child: SelectableText('ID: ${widget.docId}', style: TextStyle(color: context.pal.muted)),
                    ),
                  for (final f in widget.fields)
                    if (f.group == FieldGroup.basic)
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
                  for (final g in FieldGroup.values)
                    if (g != FieldGroup.basic && widget.fields.any((f) => f.group == g)) _groupCard(g),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('editor-save'),
                    onPressed: _saving ? null : save,
                    icon: _saving
                        ? SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onBar))
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

/// One photo of a [FieldType.imageList] field: a stored image or a picked
/// file waiting to be uploaded on save, plus its alt text.
class _GalleryEntry {
  MediaImage? image;
  EncodedImage? pending;
  final TextEditingController alt;
  _GalleryEntry(this.image, this.pending, this.alt);

  /// The `image` map with the edited alt text; a picked file not uploaded yet
  /// is a `pending` marker (replaced on save).
  Map<String, dynamic> collect() {
    final a = alt.text.trim();
    if (pending != null) return {'source': MediaSource.inline, 'pending': true, if (a.isNotEmpty) 'alt': a};
    return image!.copyWith(alt: a).toMap();
  }
}

/// A small status label under a group title.
class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.pal.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.pal.primary.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.pal.primary, fontWeight: FontWeight.w700)),
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
