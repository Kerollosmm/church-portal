import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../data/image_processing.dart';
import '../../data/media_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/custom_content.dart'
    show BlockTypes, CustomPage, ListStyles, PageBlock, PagePlacements, listBlockMaxItems;
import '../../domain/media.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart' show normalizeDigits, toArabicDigits;
import '../../domain/schedule.dart' show liturgiesHiddenBy;
import '../../domain/time_format.dart';
import '../../domain/today.dart' show DayEvent;
import '../widgets/item_image.dart';
import 'admin_schema.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';
import 'block_editors.dart';
import 'page_preview.dart';
import 'screen_header.dart';
import 'state_switch.dart';
import 'unsaved_bar.dart';
import 'unsaved_guard.dart';

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
  final String help;
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

  /// Optional guarded save for existing documents: receives [data] and the
  /// `updatedAt` timestamp currently loaded in the editor, and returns the
  /// document's new `updatedAt` after the write. When provided and [_persisted]
  /// is true, [save] calls this instead of [onSave].
  final Future<DateTime?> Function(Map<String, dynamic> data, DateTime? expectedUpdatedAt)? onSaveFresh;

  /// Optional live stream of this existing document so edits made elsewhere
  /// surface the "updated elsewhere" banner with a reload action.
  final Stream<AdminDoc?> Function()? watchDoc;

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

  /// Existing collection documents for live cross-document previews.
  final List<AdminDoc> existingDocs;

  /// Active/inactive seasons so seasonal liturgies preview override accurately.
  final List<Season> seasons;

  /// Services (`liturgies`) loaded when editing an existing season so a key
  /// change warns about affected services and can move them in the same batch.
  final List<AdminDoc> linkedServices;

  /// Optional atomic batch save used when moving services on season key change.
  final Future<void> Function(Map<String, dynamic> seasonData, String fromKey, String toKey, List<String> serviceIds)?
      onSaveWithMovedServices;

  /// Whether English translation fields are shown in the form (P2-27b).
  final bool englishEnabled;

  /// Optional dismissible informational notice shown at the top of the form.
  final String? initialNotice;

  /// Optional messenger on the caller list screen so the post-save SnackBar
  /// queues on the caller's [ScaffoldMessenger] when [popOnSave] pops back.
  final ScaffoldMessengerState? popMessenger;

  const DocEditor({
    super.key,
    required this.title,
    this.help = '',
    required this.fields,
    required this.onSave,
    this.onSaveFresh,
    this.watchDoc,
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
    this.existingDocs = const [],
    this.seasons = const [],
    this.linkedServices = const [],
    this.onSaveWithMovedServices,
    this.englishEnabled = true,
    this.initialNotice,
    this.popMessenger,
  });

  @override
  State<DocEditor> createState() => DocEditorState();
}

class DocEditorState extends State<DocEditor> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final Map<String, TextEditingController> _text = {};
  final Map<String, dynamic> _values = {};
  final Map<String, GlobalKey> _fieldKeys = {};
  final Map<String, FocusNode> _focusNodes = {};

  /// objectList rows: field key -> rows of (subKey -> controller / value).
  final Map<String, List<_Row>> _rows = {};
  bool _saving = false;
  bool _dirty = false;
  bool _pendingReset = false;
  bool _showErrorSummary = false;
  bool _initializing = false;
  int _resetEpoch = 0;
  _FieldErrorEntry? _pendingErrorFocus;
  int _pendingFocusSteps = 0;
  double? _lastMaxScrollExtent;
  Timer? _errorFocusTimer;
  String? _saveError;
  late String? _notice = widget.initialNotice;

  /// Image fields with a picked, compressed file waiting to be uploaded on save.
  final Map<String, EncodedImage> _pending = {};

  /// Image field currently being resized/compressed.
  String? _processing;

  /// Values as loaded: only fields that differ from these are saved.
  late Map<String, dynamic> _initialValues;
  final Map<String, String> _rawInitialTimeText = {};
  bool _hasInitialValues = false;

  /// The values before the first attempt of a save that has not completed
  /// yet. A failed later chunk advances [_initialValues] past a cover the
  /// first chunk replaced; its media id is still cleaned up from this
  /// baseline once a retry completes the save.
  Map<String, dynamic>? _saveBaseline;

  /// [FieldType.imageList] fields: photos in display order.
  final Map<String, List<_GalleryEntry>> _gallery = {};

  /// Collapsible group cards (opened when an error entry is tapped).
  final Map<FieldGroup, ExpansibleController> _groupCtl = {
    for (final g in FieldGroup.values)
      if (g != FieldGroup.basic) g: ExpansibleController(),
  };
  final ExpansibleController _advancedCtl = ExpansibleController();

  /// [FieldDef.collapsibleRows]: index of the currently expanded row for each field key.
  final Map<String, int?> _expandedRow = {};

  bool _slugEdited = false;
  bool _syncingSlug = false;

  /// The document exists: an existing one, or a new one whose first write
  /// succeeded (later writes then send only what changed).
  late bool _persisted = !isNew;
  late AdminDoc? _shown = isNew ? null : AdminDoc(widget.docId ?? '', widget.data!);
  late DateTime? _loadedUpdatedAt = _shown?.updatedAt;
  AdminDoc? _latestRemote;
  bool _remoteStale = false;
  bool _sawRemoteSnapshot = false;
  StreamSubscription<AdminDoc?>? _remoteSub;

  bool get isNew => widget.data == null;

  /// Unsaved local edits (the church-info screen asks before reloading).
  bool get dirty => _dirty;
  bool get saving => _saving;

  GlobalKey _fieldKey(String id) => _fieldKeys.putIfAbsent(id, () => GlobalKey());
  FocusNode _focusNode(String id) => _focusNodes.putIfAbsent(id, () => FocusNode());

  bool _isShown(FieldDef f, Map<String, Object?> values) =>
      !f.hidden &&
      (widget.englishEnabled || f.lang != 'en') &&
      (f.showWhen == null || f.showWhen!.value.contains(values[f.showWhen!.key]));

  String _blockTypeOf(_Row row) =>
      (row.values['type'] ?? row.text['type']?.text ?? BlockTypes.paragraph).toString();

  @override
  void initState() {
    super.initState();
    _initializing = true;
    try {
      final data = {...?widget.data};
      if (isNew) data.addAll(widget.newDefaults);
      if (widget.fields.any((f) => f.key == 'placement') &&
          (data['placement'] == null || '${data['placement']}'.isEmpty) &&
          data['showInNav'] == true) {
        data['placement'] = PagePlacements.nav;
      }
      for (final f in widget.fields) {
        _init(f, data[f.key]);
      }
      _setupAutoSlug();
      _initialValues = collect();
      if (!isNew) {
        for (final f in widget.fields) {
          if (f.type == FieldType.time && data[f.key] is String) {
            final raw = (data[f.key] as String).trim();
            _initialValues[f.key] = raw;
            _rawInitialTimeText[f.key] = raw;
          }
        }
      }
      _hasInitialValues = true;
    } finally {
      _initializing = false;
    }
    if (!isNew && widget.watchDoc != null) {
      _remoteSub = widget.watchDoc!().listen(_onRemoteDoc, onError: (_) {});
    }
  }

  void _onRemoteDoc(AdminDoc? latest) {
    if (!mounted || isNew) return;
    if (latest == null) {
      // Test fakes that do not mirror collection items in watchDoc emit null
      // on the initial snapshot; ignore that unless the doc had a timestamp or
      // was previously seen on this stream.
      if (!_sawRemoteSnapshot && _shown?.updatedAt == null) return;
      setState(() {
        _latestRemote = null;
        _remoteStale = true;
      });
      return;
    }
    _sawRemoteSnapshot = true;
    final changed = !sameTimestamp(latest.updatedAt, _shown?.updatedAt) ||
        (latest.updatedAt == null && _shown?.updatedAt == null && !sameValue(latest.data, _shown?.data));
    if (!changed) return;
    final echo = _shown != null && isEchoOfEditor(_shown!.data, latest.data, collect());
    if (!_dirty && !_saving || echo) {
      _shown = latest;
      if (!_saving) _loadedUpdatedAt = latest.updatedAt;
      _latestRemote = latest;
      if (!echo) {
        _reloadFromData(latest.data);
      } else if (_remoteStale) {
        setState(() => _remoteStale = false);
      }
      return;
    }
    setState(() {
      _latestRemote = latest;
      _remoteStale = true;
    });
  }

  void _reloadRemote() {
    final doc = _latestRemote;
    if (doc == null || _saving) return;
    _shown = doc;
    _loadedUpdatedAt = doc.updatedAt;
    _reloadFromData(doc.data);
  }

  void _reloadFromData(Map<String, dynamic> source) {
    _resetEpoch++;
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
    _text.clear();
    _values.clear();
    _rows.clear();
    _gallery.clear();
    _pending.clear();
    _rawInitialTimeText.clear();
    _processing = null;
    _showErrorSummary = false;
    _saveError = null;
    _saveBaseline = null;
    _remoteStale = false;
    _initializing = true;
    try {
      final data = {...source};
      if (widget.fields.any((f) => f.key == 'placement') &&
          (data['placement'] == null || '${data['placement']}'.isEmpty) &&
          data['showInNav'] == true) {
        data['placement'] = PagePlacements.nav;
      }
      for (final f in widget.fields) {
        _init(f, data[f.key]);
      }
      _initialValues = collect();
      for (final f in widget.fields) {
        if (f.type == FieldType.time && data[f.key] is String) {
          final raw = (data[f.key] as String).trim();
          _initialValues[f.key] = raw;
          _rawInitialTimeText[f.key] = raw;
        }
      }
    } finally {
      _initializing = false;
    }
    setState(() => _dirty = false);
  }

  @override
  void didUpdateWidget(covariant DocEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.englishEnabled != widget.englishEnabled && _showErrorSummary) {
      _syncErrorSummaryAfterChange();
    }
  }

  void _setupAutoSlug() {
    _slugEdited = false;
    _syncingSlug = false;
    if (!isNew || _persisted) return;
    final slugCtrl = _text['slug'];
    if (slugCtrl == null) return;
    final titleKey = _text.containsKey('nameAr')
        ? 'nameAr'
        : (_text.containsKey('titleAr') ? 'titleAr' : null);
    if (titleKey == null) return;
    final titleCtrl = _text[titleKey]!;
    slugCtrl.addListener(() {
      if (!_syncingSlug) _slugEdited = true;
    });
    void sync() {
      if (!isNew || _persisted || _slugEdited) return;
      final rawTitle = titleCtrl.text.trim();
      final next = rawTitle.isEmpty ? '' : slugFromTitle(rawTitle, taken: widget.takenSlugs);
      if (slugCtrl.text != next) {
        _syncingSlug = true;
        slugCtrl.text = next;
        _syncingSlug = false;
      }
    }
    titleCtrl.addListener(sync);
    if (slugCtrl.text.trim().isEmpty && titleCtrl.text.trim().isNotEmpty) {
      sync();
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
        _text[f.key] = _ctrl(v is DateTime ? fmtDateTime(v) : (v is String ? v : ''));
      case FieldType.date:
        _text[f.key] = _ctrl(v is DateTime ? fmtDate(v) : (v is String ? v : ''));
      case FieldType.boolean:
        _values[f.key] = v is bool ? v : (isNew ? f.newBool : f.missingBool);
      case FieldType.weekday:
        _values[f.key] = v is int ? v : null;
      case FieldType.weekdays:
        _values[f.key] = <int>{...((v as List?) ?? const []).whereType<int>()};
      case FieldType.choices:
        _values[f.key] = <String>{
          for (final o in (v is List ? v : f.defaultValues))
            if (o is String && f.options.contains(o)) o,
        };
      case FieldType.dateList:
        _values[f.key] = <String>{
          for (final o in (v is List ? v : const []))
            if (o is String && isValidDate(o)) o,
        };
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
        if (f.collapsibleRows) {
          final rList = _rows[f.key]!;
          if (rList.isNotEmpty) {
            final donationIdx = rList.indexWhere((r) => _blockTypeOf(r) == BlockTypes.donation);
            _expandedRow[f.key] = donationIdx >= 0 ? donationIdx : 0;
          } else {
            _expandedRow[f.key] = null;
          }
        }
      case FieldType.image:
        final img = MediaImage.fromMap(v);
        // A stored image whose link is not usable any more (e.g. an old doc):
        // keep the raw map so the save is blocked with a clear error instead
        // of dropping the image silently. No data is changed; the doc is only
        // fixed when the admin picks a new link or removes the image.
        _values[f.key] = img?.toMap() ??
            (v is Map && v['url'] is String && (v['url'] as String).trim().isNotEmpty ? Map<String, dynamic>.from(v) : null);
        _text[f.key] = _ctrl(img?.alt ?? (v is Map && v['alt'] is String ? v['alt'] as String : ''));
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
    final map = {for (var i = 0; i < f.subFields.length; i++) f.subFields[i].key: i < parts.length ? parts[i] : ''};
    if (f.key == 'dayEvents') {
      final id = map['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        final d = map['date']?.toString().trim() ?? '';
        final st = map['start']?.toString().trim() ?? '';
        final t = map['titleAr']?.toString().trim() ?? '';
        map['id'] = DayEvent.computeHashId(d, st, t);
      }
    }
    return map;
  }

  TextEditingController _ctrl(String text) => TextEditingController(text: text)..addListener(_markDirty);

  void _clearPendingErrorFocus() {
    _errorFocusTimer?.cancel();
    _errorFocusTimer = null;
    _pendingErrorFocus = null;
    _pendingFocusSteps = 0;
  }

  void _markDirty() {
    if (!_initializing) _clearPendingErrorFocus();
    if (!_initializing && mounted && (!_dirty || _showErrorSummary || _saveError != null || widget.def?.name == 'seasons')) {
      setState(() {
        _dirty = true;
        _saveError = null;
        if (_showErrorSummary && _collectErrors().isEmpty) {
          _showErrorSummary = false;
        }
      });
    }
  }

  void _syncErrorSummaryAfterChange() {
    if (_showErrorSummary && _collectErrors().isEmpty) {
      _showErrorSummary = false;
    }
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    _errorFocusTimer?.cancel();
    _scroll.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
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
    _advancedCtl.dispose();
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
      if (f.showWhen != null && !f.showWhen!.value.contains(_values[f.showWhen!.key])) {
        if (f.key == 'categoryId') {
          out[f.key] = _values['categoryId'] ?? '';
        } else {
          out[f.key] = f.type == FieldType.choice ? '' : null;
        }
        continue;
      }
      if (_hasInitialValues && !widget.englishEnabled && f.lang == 'en') {
        out[f.key] = _initialValues[f.key];
        continue;
      }
      switch (f.type) {
        case FieldType.boolean:
        case FieldType.weekday:
        case FieldType.choice:
          out[f.key] = _values[f.key];
        case FieldType.weekdays:
          out[f.key] = (_values[f.key] as Set<int>).toList()..sort();
        case FieldType.choices:
          out[f.key] = [for (final o in f.options) if ((_values[f.key] as Set<String>).contains(o)) o];
        case FieldType.dateList:
          out[f.key] = (_values[f.key] as Set<String>).toList()..sort();
        case FieldType.objectList:
          out[f.key] = [
            for (final r in _rows[f.key]!)
              f.encodedRows
                  ? _encodeRow(f, r.collect(englishEnabled: widget.englishEnabled))
                  : r.collect(englishEnabled: widget.englishEnabled),
          ];
        case FieldType.image:
          out[f.key] = _collectImage(f.key);
        case FieldType.imageList:
          out[f.key] = [for (final g in _gallery[f.key]!) g.collect()];
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.looseDate:
        case FieldType.url:
          out[f.key] = _text[f.key]!.text.trim();
        case FieldType.time:
          final cur = _text[f.key]!.text.trim();
          final rawInitial = _rawInitialTimeText[f.key];
          out[f.key] = (_hasInitialValues && !isNew && rawInitial != null && cur == rawInitial)
              ? rawInitial
              : parseFieldValue(f, cur);
        default:
          out[f.key] = parseFieldValue(f, _text[f.key]!.text);
      }
    }
    if (out.containsKey('placement')) {
      out['showInNav'] = out['placement'] == PagePlacements.nav;
    }
    return out;
  }

  /// The `image` map with the edited alt text (null = no image). A picked file
  /// that is not uploaded yet is a `pending` marker (replaced on save).
  /// A stored image whose link is not usable any more is kept as its raw map
  /// so [validateDocument] blocks the save with a clear error instead of
  /// dropping the image silently.
  Map<String, dynamic>? _collectImage(String key) {
    final alt = _text[key]!.text.trim();
    if (_pending.containsKey(key)) return {'source': MediaSource.inline, 'pending': true, if (alt.isNotEmpty) 'alt': alt};
    final raw = _values[key];
    final img = MediaImage.fromMap(raw);
    if (img != null) return img.copyWith(alt: alt).toMap();
    if (raw is Map && raw['url'] is String && (raw['url'] as String).trim().isNotEmpty) {
      return {...Map<String, dynamic>.from(raw), if (alt.isNotEmpty) 'alt': alt};
    }
    return null;
  }

  Iterable<FieldDef> get _imageFields => widget.fields.where((f) => f.type == FieldType.image);

  bool get _hasPendingUploads => _pending.isNotEmpty || _gallery.values.any((l) => l.any((g) => g.pending != null));

  String _plainLabel(FieldDef f) => context.pick(f.labelAr, f.labelEn);

  List<ListBlockIssue> _listIssuesForRow(_Row r) => validateListBlock(
        arItems: [for (final it in r.listItems) it.arCtrl.text],
        enItems: widget.englishEnabled ? [for (final it in r.listItems) it.enCtrl.text] : const [],
        style: r.listStyle,
      );

  String? _listBlockErrorText(_Row r) {
    for (final issue in _listIssuesForRow(r)) {
      if (issue.itemIndex == null) return context.tr(issue.code);
    }
    return null;
  }

  List<DetailsBlockIssue> _detailsIssuesForRow(_Row r) {
    final d = r.detailsDraft;
    if (d == null) return const [];
    return validateDetailsBlock(
      summaryAr: d.summaryArCtrl.text,
      bodyAr: d.bodyArCtrl.text,
      summaryEn: widget.englishEnabled ? d.summaryEnCtrl.text : '',
      bodyEn: widget.englishEnabled ? d.bodyEnCtrl.text : '',
    );
  }

  /// Collects all invalid currently-shown fields in form order (including those
  /// inside collapsed advanced/group cards so they appear in the error summary).
  List<_FieldErrorEntry> _collectErrors() {
    final out = <_FieldErrorEntry>[];
    final ordered = <FieldDef>[
      for (final f in widget.fields)
        if (f.group == FieldGroup.basic && !f.advanced && _isShown(f, _values)) f,
      for (final f in widget.fields)
        if (f.group == FieldGroup.basic && f.advanced && _isShown(f, _values)) f,
      for (final g in FieldGroup.values)
        if (g != FieldGroup.basic)
          for (final f in widget.fields)
            if (f.group == g && _isShown(f, _values)) f,
    ];
    for (final f in ordered) {
      final group = f.group == FieldGroup.basic ? null : f.group;
      final advanced = f.group == FieldGroup.basic && f.advanced;
      if (f.type == FieldType.objectList) {
        final rows = _rows[f.key] ?? const <_Row>[];
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          final rowMap = {for (final e in r.text.entries) e.key: e.value.text};
          for (final sf in f.subFields) {
            if (!_isShown(sf, r.values)) continue;
            var bad = false;
            if (sf.type == FieldType.choice) {
              bad = sf.required && (r.values[sf.key] == null || '${r.values[sf.key]}'.isEmpty);
            } else if (sf.type != FieldType.boolean && sf.type != FieldType.image && sf.type != FieldType.imageList) {
              final rc = r.text[sf.key];
              final fieldBad = rc != null && validateFieldValue(sf, rc.text) != null;
              final anyOfBad =
                  f.rowRequireAnyOf.isNotEmpty && f.rowRequireAnyOf.first == sf.key && validateRowAnyOf(f, rowMap) != null;
              final orderBad = f.rowNotBefore?.key == sf.key && validateRowOrder(f, rowMap) != null;
              final uniqueBad = f.rowUniqueKey == sf.key &&
                  validateRowUnique(f, [for (final x in rows) x.text[sf.key]?.text ?? ''], i) != null;
              final headingBad = f.key == 'blocks' &&
                  sf.key == 'textAr' &&
                  r.values['type'] == BlockTypes.heading &&
                  (rc?.text ?? '').trim().isEmpty;
              bad = fieldBad || anyOfBad || orderBad || uniqueBad || headingBad;
            }
            if (bad) {
              out.add(_FieldErrorEntry(
                id: '${f.key}-$i-${sf.key}',
                label: '${_plainLabel(f)} (${i + 1}) — ${_plainLabel(sf)}',
                group: group,
                advanced: advanced,
                fieldKey: r.keyFor(sf.key),
                focusNode: r.focusFor(sf.key),
              ));
            }
          }
          if (f.key == 'blocks' && r.values['type'] == BlockTypes.list) {
            for (final issue in _listIssuesForRow(r)) {
              final itemIdx = issue.itemIndex;
              final GlobalKey targetKey;
              final FocusNode targetFocus;
              final String label;
              if (itemIdx != null && itemIdx < r.listItems.length) {
                final item = r.listItems[itemIdx];
                targetKey = issue.isEn ? item.enKey : item.arKey;
                targetFocus = issue.isEn ? item.enFocus : item.arFocus;
                final itemLabel = context.tr(issue.isEn ? 'listItemEnLabel' : 'listItemArLabel');
                label = '${_plainLabel(f)} (${i + 1}) — $itemLabel ${itemIdx + 1}';
              } else {
                targetKey = r.keyFor('list');
                targetFocus = r.focusFor('list');
                label = '${_plainLabel(f)} (${i + 1}) — ${context.tr(issue.code)}';
              }
              out.add(_FieldErrorEntry(
                id: '${f.key}-$i-list-${itemIdx ?? 'block'}-${issue.isEn ? 'en' : 'ar'}-${issue.code}',
                label: label,
                group: group,
                advanced: advanced,
                fieldKey: targetKey,
                focusNode: targetFocus,
              ));
            }
          }
          if (f.key == 'blocks' && r.values['type'] == BlockTypes.details) {
            final d = r.detailsDraft;
            if (d != null) {
              for (final issue in _detailsIssuesForRow(r)) {
                final GlobalKey targetKey;
                final FocusNode targetFocus;
                final String fieldLabelKey;
                if (issue.field == 'summary') {
                  targetKey = issue.isEn ? d.summaryEnKey : d.summaryArKey;
                  targetFocus = issue.isEn ? d.summaryEnFocus : d.summaryArFocus;
                  fieldLabelKey = issue.isEn ? 'detailsSummaryEnLabel' : 'detailsSummaryArLabel';
                } else {
                  targetKey = issue.isEn ? d.bodyEnKey : d.bodyArKey;
                  targetFocus = issue.isEn ? d.bodyEnFocus : d.bodyArFocus;
                  fieldLabelKey = issue.isEn ? 'detailsBodyEnLabel' : 'detailsBodyArLabel';
                }
                out.add(_FieldErrorEntry(
                  id: '${f.key}-$i-details-${issue.field ?? 'block'}-${issue.isEn ? 'en' : 'ar'}-${issue.code}',
                  label: context
                      .tr('detailsErrorSummaryLabel')
                      .replaceAll('{n}', '${i + 1}')
                      .replaceAll('{field}', context.tr(fieldLabelKey)),
                  group: group,
                  advanced: advanced,
                  fieldKey: targetKey,
                  focusNode: targetFocus,
                ));
              }
            }
          }
        }
        continue;
      }
      if (f.type == FieldType.choice) {
        if (f.required && (_values[f.key] == null || '${_values[f.key]}'.isEmpty)) {
          out.add(_FieldErrorEntry(
            id: f.key,
            label: _plainLabel(f),
            group: group,
            advanced: advanced,
            fieldKey: _fieldKey(f.key),
            focusNode: _focusNode(f.key),
          ));
        }
        continue;
      }
      if (f.type == FieldType.image) {
        // A stored cover link that is not usable any more: block the save and
        // point at the field, where the admin can fix the link or remove the
        // image. The image itself is never dropped silently.
        // A staged replacement upload makes the stored link irrelevant: the
        // save uploads it first and replaces the stored value, so it must
        // not block the save (CodeRabbit + Sentry review on PR #86).
        if (invalidImageUrl(_values[f.key]) != null && !_pending.containsKey(f.key)) {
          out.add(_FieldErrorEntry(
            id: f.key,
            label: '${_plainLabel(f)} — ${context.tr('invalidCoverImage')}',
            group: group,
            advanced: advanced,
            fieldKey: _fieldKey(f.key),
            focusNode: _focusNode(f.key),
          ));
        }
        continue;
      }
      final c = _text[f.key];
      if (c != null && f.type != FieldType.image) {
        final fieldErr = validateFieldValue(f, c.text);
        final slugTaken = fieldErr == null && f.slug && widget.takenSlugs.contains(c.text.trim());
        if (fieldErr != null || slugTaken) {
          out.add(_FieldErrorEntry(
            id: f.key,
            label: slugTaken ? '${_plainLabel(f)} — ${context.tr('slugTaken')}' : _plainLabel(f),
            group: group,
            advanced: advanced,
            fieldKey: _fieldKey(f.key),
            focusNode: _focusNode(f.key),
          ));
        }
      }
    }
    return out;
  }

  void _applyErrorFocus(_FieldErrorEntry entry, {required bool animate}) {
    if (!mounted) return;
    _formKey.currentState?.validate();
    final ctx = entry.fieldKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
        alignment: 0.25,
      );
    }
    if (entry.focusNode.canRequestFocus) {
      entry.focusNode.requestFocus();
    }
  }

  void _focusErrorEntry(_FieldErrorEntry entry) {
    var expanded = false;
    if (entry.advanced && !_advancedCtl.isExpanded) {
      _advancedCtl.expand();
      expanded = true;
    } else if (entry.group != null) {
      final ctl = _groupCtl[entry.group];
      if (ctl != null && !ctl.isExpanded) {
        ctl.expand();
        expanded = true;
      }
    }
    for (final f in widget.fields) {
      if (f.collapsibleRows) {
        final rows = _rows[f.key] ?? const <_Row>[];
        for (var idx = 0; idx < rows.length; idx++) {
          if (rows[idx].ownsFocusNode(entry.focusNode) ||
              rows[idx].ownsFieldKey(entry.fieldKey)) {
            if (_expandedRow[f.key] != idx) {
              _expandedRow[f.key] = idx;
              expanded = true;
            }
            break;
          }
        }
      }
    }
    if (expanded) {
      _clearPendingErrorFocus();
      _pendingErrorFocus = entry;
      _pendingFocusSteps = 20;
      _lastMaxScrollExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : null;
      _errorFocusTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) _clearPendingErrorFocus();
      });
      setState(() {});
    } else {
      _clearPendingErrorFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyErrorFocus(entry, animate: !expanded);
    });
  }

  Widget _noticeBanner(BuildContext context, String notice) {
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const Key('editor-initial-notice'),
        color: context.pal.primary.withValues(alpha: 0.08),
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.pal.primary.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: context.pal.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notice,
                  style: TextStyle(color: context.pal.ink, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const Key('editor-initial-notice-dismiss'),
                icon: Icon(Icons.close, color: context.pal.muted, size: 18),
                onPressed: () => setState(() => _notice = null),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveErrorBanner(BuildContext context, String error) {
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const Key('editor-save-error'),
        color: context.pal.alert.withValues(alpha: 0.08),
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.pal.alert.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: context.pal.alert, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  style: TextStyle(color: context.pal.alert, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.pal.alert, size: 18),
                onPressed: () => setState(() => _saveError = null),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seasonOverlapWarningBanner(BuildContext context, List<AdminDoc> overlapping) {
    final names = [
      for (final o in overlapping)
        (() {
          final v = context.pick('${o.data['nameAr'] ?? ''}', '${o.data['nameEn'] ?? ''}').trim();
          return v.isEmpty ? o.id : v;
        })(),
    ].join(context.isAr ? '، ' : ', ');
    return Card(
      key: const Key('season-overlap-warning'),
      color: context.pal.goldText.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.pal.goldText.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: context.pal.goldText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('seasonOverlapWarning', {'names': names}),
                style: TextStyle(color: context.pal.ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorSummaryCard(BuildContext context, List<_FieldErrorEntry> errors) {
    final n = errors.length;
    final title = switch (n) {
      1 => context.tr('errSummaryOne'),
      2 => context.tr('errSummaryTwo'),
      >= 3 && <= 10 => context.tr('errSummaryFew', {'n': '$n'}),
      _ => context.tr('errSummaryMany', {'n': '$n'}),
    };
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const Key('editor-error-summary'),
        color: context.pal.alert.withValues(alpha: 0.08),
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.pal.alert.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: context.pal.alert, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(color: context.pal.alert, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final e in errors)
                InkWell(
                  key: ValueKey('error-summary-${e.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _focusErrorEntry(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_forward_rounded, size: 16, color: context.pal.alert),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.label,
                            style: TextStyle(
                              color: context.pal.ink,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
    setState(() => _saveError = null);
    final errors = _collectErrors();
    final valid = _formKey.currentState!.validate();
    if (!valid || errors.isNotEmpty) {
      _clearPendingErrorFocus();
      setState(() => _showErrorSummary = true);
      _FieldErrorEntry? detailsErr;
      for (final e in errors) {
        if (e.id.contains('-details-')) {
          detailsErr = e;
          break;
        }
      }
      if (detailsErr != null) {
        _focusErrorEntry(detailsErr);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      }
      return false;
    }
    var data = collect();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final docErr = validateDocument(
      widget.def,
      data,
      existingDocs: widget.existingDocs,
      docId: widget.docId,
    );
    if (docErr != null) {
      final msg = context.tr(docErr);
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
      setState(() => _saveError = msg);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
      return false;
    }
    final savedMsg = context.tr('saved');
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    bool willPop() => widget.popOnSave && (route?.isCurrent ?? false);
    ScaffoldMessengerState? targetMessenger() =>
        (willPop() && (widget.popMessenger?.mounted ?? false)) ? widget.popMessenger : messenger;
    // Existing docs: write only what changed (merge), never stale values.
    var payload = _persisted ? changedFields(_initialValues, data) : data;
    // A new document does not write an unset image style (ADR-023): missing
    // already means "section default", and rules that predate the field
    // keep accepting the save.
    if (!_persisted && payload['imageStyle'] == null) payload = {...payload}..remove('imageStyle');
    if (payload.isEmpty && !_hasPendingUploads) {
      targetMessenger()?.showSnackBar(SnackBar(content: Text(context.tr('noChanges'))));
      setState(() => _dirty = false);
      if (willPop()) nav.pop();
      return true;
    }
    var moveServices = false;
    var oldSeasonKey = '';
    var newSeasonKey = '';
    var affectedServiceIds = const <String>[];
    if (widget.def?.name == 'seasons' && !isNew && _persisted) {
      oldSeasonKey = _initialValues['key']?.toString() ?? '';
      newSeasonKey = data['key']?.toString() ?? '';
      if (oldSeasonKey.isNotEmpty && newSeasonKey.isNotEmpty && newSeasonKey != oldSeasonKey) {
        affectedServiceIds = [
          for (final s in widget.linkedServices)
            if (!isSoftDeleted(s.data) && s.data['seasonKey'] == oldSeasonKey) s.id,
        ];
        if (affectedServiceIds.isNotEmpty) {
          final choice = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              key: const Key('seasonKeyChangeDialog'),
              title: Text(context.tr('seasonKeyChangeTitle')),
              content: Text(context.tr('seasonKeyChangeBody', {
                'c': '${affectedServiceIds.length}',
                'old': choiceLabel(context, oldSeasonKey),
                'new': choiceLabel(context, newSeasonKey),
              })),
              actions: [
                TextButton(
                  key: const Key('seasonKeyChange-cancel'),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('cancel')),
                ),
                TextButton(
                  key: const Key('seasonKeyChange-keep'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('seasonKeyChangeKeepBtn')),
                ),
                if (widget.onSaveWithMovedServices != null)
                  FilledButton(
                    key: const Key('seasonKeyChange-move'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(context.tr('seasonKeyChangeMoveBtn')),
                  ),
              ],
            ),
          );
          if (choice == null || !mounted) return false;
          moveServices = choice && widget.onSaveWithMovedServices != null;
        }
      }
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
      if (moveServices) {
        await widget.onSaveWithMovedServices!(payload, oldSeasonKey, newSeasonKey, affectedServiceIds);
        _persisted = true;
        _initialValues = {..._initialValues, ...payload};
      } else {
        for (final chunk in splitSavePayload(payload)) {
          if (_persisted && widget.onSaveFresh != null) {
            _loadedUpdatedAt = await widget.onSaveFresh!(chunk, _loadedUpdatedAt);
          } else {
            await widget.onSave(chunk);
          }
          _persisted = true;
          _initialValues = {..._initialValues, ...chunk};
        }
      }
      _initialValues = data;
      _remoteStale = false;
      for (final f in widget.fields) {
        if (f.type == FieldType.time && data[f.key] is String) {
          _rawInitialTimeText[f.key] = (data[f.key] as String).trim();
        }
      }
      // Best effort: drop inline images this edit replaced or removed (an
      // image moved between the cover and the gallery is still referenced).
      // Measured from the first attempt's baseline too, so a cover replaced
      // by an earlier, partly failed attempt of this save is not left behind.
      _deleteMedia({...orphanedDocMediaIds(baseline, data), ...orphanedDocMediaIds(initialBefore, data)}.toList());
      _saveBaseline = null;
      targetMessenger()?.showSnackBar(SnackBar(content: Text(savedMsg)));
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _dirty = false;
        _showErrorSummary = false;
        _saveError = null;
      });
      if (_pendingReset) {
        _pendingReset = false;
        _resetToInitial();
      }
      // The admin may have closed the editor while the write was pending:
      // only pop if this editor is still the top route.
      if (willPop()) nav.pop();
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
        final errText = context.tr('saveFailed', {'e': formatAdminError(e, isAr: context.isAr)});
        messenger?.showSnackBar(SnackBar(content: Text(errText)));
        setState(() {
          _saving = false;
          _saveError = errText;
        });
        if (_pendingReset) {
          _pendingReset = false;
          _resetToInitial();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
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
    return confirmDiscardChanges(context);
  }

  void _resetToInitial() {
    if (_saving) {
      _pendingReset = true;
      return;
    }
    _resetEpoch++;
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
    _text.clear();
    _values.clear();
    _rows.clear();
    _gallery.clear();
    _pending.clear();
    _processing = null;
    _showErrorSummary = false;
    _saveError = null;
    _initializing = true;
    try {
      for (final f in widget.fields) {
        _init(f, _initialValues[f.key]);
      }
      _setupAutoSlug();
    } finally {
      _initializing = false;
    }
    setState(() => _dirty = false);
  }

  Future<void> _handleCancel() async {
    if (widget.popOnSave) {
      Navigator.of(context).maybePop();
    } else {
      final discard = await _confirmDiscard();
      if (discard && mounted) {
        _resetToInitial();
      }
    }
  }

  String _label(FieldDef f) => context.pick(f.labelAr, f.labelEn) + (f.required ? ' *' : '');

  /// Time / date / date-time fields remain directly editable and also offer
  /// the pickers via their trailing button: a clock or calendar icon opens
  /// [showTimePicker] as a 12-hour AM/PM picker (ص/م in Arabic) /
  /// [showDatePicker]. Storage stays 24-hour ASCII: strictly "HH:mm",
  /// "YYYY-MM-DD" or "YYYY-MM-DD HH:mm" (Cairo wall time); [_pickedReading]
  /// shows the 12-hour reading.
  static bool _picked(FieldType t) => t == FieldType.time || t == FieldType.date || t == FieldType.dateTime;

  Future<void> _pick(FieldDef f, TextEditingController c) async {
    final epoch = _resetEpoch;
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
      if (t != null && mounted && epoch == _resetEpoch) c.text = formatPickedTime(t.$1, t.$2);
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
    if (d == null || !mounted || epoch != _resetEpoch) return;
    if (f.type == FieldType.date) {
      c.text = formatPickedDate(d.year, d.month, d.day);
      return;
    }
    final t = await time(cur == null ? null : (cur.$4, cur.$5));
    if (t == null || !mounted || epoch != _resetEpoch) return;
    c.text = formatPickedDateTime(d.year, d.month, d.day, t.$1, t.$2);
  }

  /// Year + optional Arabic/English month + optional day picker for
  /// [FieldType.looseDate]; manual typing remains enabled on the field.
  Future<void> _pickLooseDate(FieldDef f, TextEditingController c) async {
    final epoch = _resetEpoch;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _LooseDatePickerDialog(
        title: _label(f),
        initial: parseLooseDate(c.text),
        defaultYear: CairoTime.now().year,
      ),
    );
    if (picked == null || !mounted || epoch != _resetEpoch) return;
    c.text = picked;
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
    final isLoose = f.type == FieldType.looseDate;
    if (!_picked(f.type) && !isLoose) return null;
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
          onPressed: () => isLoose ? _pickLooseDate(f, c) : _pick(f, c),
        ),
      ]),
    );
  }

  Widget _textField(FieldDef f, TextEditingController c, {String? Function()? rowError, FocusNode? focusNode}) {
    if (f.type == FieldType.time || f.type == FieldType.dateTime) {
      // Rebuilds with the value so the 12-hour reading follows each pick.
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (context, v, _) => _textFieldBody(f, c, rowError, _pickedReading(f, v.text), focusNode),
      );
    }
    return _textFieldBody(f, c, rowError, null, focusNode);
  }

  Widget _textFieldBody(
      FieldDef f, TextEditingController c, String? Function()? rowError, String? reading, FocusNode? focusNode) {
    final ltr = switch (f.type) {
      FieldType.text || FieldType.multiline => false,
      _ => true,
    };
    final fieldHint = context.pick(f.hintAr, f.hintEn);
    final looseHint = f.type == FieldType.looseDate && fieldHint.isEmpty ? context.tr('looseDateHint') : '';
    final hint = [reading ?? '', fieldHint, looseHint].where((s) => s.isNotEmpty).join('\n');
    return TextFormField(
      key: ValueKey('field-${f.key}'),
      controller: c,
      focusNode: focusNode,
      readOnly: false,
      onTap: null,
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
        helperStyle: hint.isEmpty ? null : TextStyle(fontSize: 13.5, color: context.pal.muted, height: 1.4),
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
    final epoch = _resetEpoch;
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
    if (picked == null || !mounted || epoch != _resetEpoch) return;
    c.text = picked;
  }

  /// One dropdown option: its label, plus its one-line hint underneath when
  /// the field defines one (`opt_<field>_<option>_hint`), so each choice
  /// explains itself while picking.
  Widget _choiceOptionChild(FieldDef f, String option) {
    final hint = fieldChoiceHint(context, f, option);
    final label = Text(fieldChoiceLabel(context, f, option));
    if (hint.isEmpty) return label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: context.pal.muted),
        ),
      ],
    );
  }

  (String on, String off) _switchLabels(BuildContext context, FieldDef f) {
    return switch (f.key) {
      'visible' => (context.tr('switch_visible'), context.tr('switch_hidden')),
      'sample' => (context.tr('switch_sample'), context.tr('switch_confirmed')),
      'active' => (context.tr('switch_active'), context.tr('switch_stopped')),
      'replacesDay' => (context.tr('switch_replaces_on'), context.tr('switch_replaces_off')),
      'showInNav' => (context.tr('switch_nav_on'), context.tr('switch_nav_off')),
      'featured' => (context.tr('switch_featured_on'), context.tr('switch_featured_off')),
      _ => (context.tr('switch_enabled'), context.tr('switch_disabled')),
    };
  }

  Widget _replacesDayPreview(BuildContext context) {
    final normDate = normalizeDigits((_text['date']?.text ?? '').trim());
    final dateParts = isValidDate(normDate) ? parseFieldDateTime(normDate) : null;
    final parsedDate = dateParts == null ? null : CairoTime.at(dateParts.$1, dateParts.$2, dateParts.$3).toUtc();
    String normalizeTime(String? raw) {
      final v = (raw ?? '').trim();
      final t = v.isEmpty ? null : parseFieldTime(v);
      return t == null ? v : formatPickedTime(t.$1, t.$2);
    }
    final rawWeekday = _values['weekday'];
    final weekday = rawWeekday is int ? rawWeekday : null;

    final rawSeasonKey = _values['seasonKey'];
    final seasonKey = rawSeasonKey is String && rawSeasonKey.isNotEmpty ? rawSeasonKey : null;

    final replacing = Liturgy(
      id: widget.docId ?? 'draft',
      type: _values['type'] is String && (_values['type'] as String).isNotEmpty
          ? _values['type'] as String
          : (_text['type']?.text.trim().isNotEmpty == true ? _text['type']!.text.trim() : 'mass'),
      nameAr: _text['nameAr']?.text.trim() ?? '',
      nameEn: _text['nameEn']?.text.trim() ?? '',
      weekday: weekday,
      date: parsedDate,
      start: normalizeTime(_text['start']?.text),
      end: normalizeTime(_text['end']?.text),
      seasonKey: seasonKey,
      replacesDay: true,
      visible: _values['visible'] != false,
      sample: _values['sample'] == true,
    );

    final allLiturgies = [
      for (final d in widget.existingDocs)
        if (!isSoftDeleted(d.data)) Liturgy.fromMap(d.id, d.data),
    ];
    final hiddenLiturgies = liturgiesHiddenBy(replacing, allLiturgies, seasons: widget.seasons);

    final String heading;
    if (replacing.date != null) {
      final d = CairoTime.calendarDate(replacing.date!);
      final w = weekdayName(d.weekday, arabic: context.isAr);
      final dt = formatDate(d, arabic: context.isAr);
      heading = context.tr('replacesPreviewHeadingDate', {'d': '$w $dt'});
    } else if (replacing.weekday != null) {
      final w = weekdayName(replacing.weekday, arabic: context.isAr);
      heading = context.tr('replacesPreviewHeadingWeekday', {'w': w});
    } else {
      heading = context.tr('replacesPreviewHeadingFallback');
    }

    final String emptyNote;
    if (!replacing.visible) {
      emptyNote = context.tr('replacesPreviewHidden');
    } else if (replacing.date == null && replacing.weekday == null) {
      emptyNote = context.tr('replacesPreviewNoDay');
    } else {
      emptyNote = context.tr('replacesPreviewEmpty');
    }

    return Card(
      key: const ValueKey('replacesDayPreview'),
      color: context.pal.surfaceAlt.withValues(alpha: 0.5),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.pal.goldText.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: context.pal.goldText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    heading,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: context.pal.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hiddenLiturgies.isEmpty)
              Text(emptyNote, style: TextStyle(color: context.pal.muted, fontSize: 12))
            else
              for (final l in hiddenLiturgies)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          context.pick(l.nameAr, l.nameEn),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        context.isAr ? formatRangeArabic(l.start, l.end) : formatRangeLatin(l.start, l.end),
                        style: TextStyle(fontSize: 12, color: context.pal.muted),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _field(FieldDef f) => KeyedSubtree(
        key: _fieldKey(f.key),
        child: _fieldBody(f),
      );

  Widget _fieldBody(FieldDef f) {
    final label = _label(f);
    switch (f.type) {
      case FieldType.boolean:
        // The field's hint under the switch (e.g. `replacesDay`, ADR-050).
        final hint = context.pick(f.hintAr, f.hintEn);
        final (onLabel, offLabel) = _switchLabels(context, f);
        final sw = AdminStateSwitch(
          key: ValueKey('field-${f.key}'),
          contentPadding: const EdgeInsetsDirectional.only(start: 4),
          title: Text(label),
          subtitle: hint.isEmpty ? null : Text(hint),
          value: _values[f.key] as bool,
          onLabel: onLabel,
          offLabel: offLabel,
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
            _saveError = null;
          }),
        );
        if (f.key == 'replacesDay' && _values['replacesDay'] == true) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sw,
              ListenableBuilder(
                listenable: Listenable.merge([
                  for (final k in const ['date', 'start', 'end', 'nameAr', 'nameEn', 'type'])
                    if (_text[k] != null) _text[k]!,
                ]),
                builder: (context, _) => _replacesDayPreview(context),
              ),
            ],
          );
        }
        return sw;
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
            _saveError = null;
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
                  _saveError = null;
                }),
              ),
          ]),
        );
      case FieldType.choices:
        final set = _values[f.key] as Set<String>;
        return InputDecorator(
          key: ValueKey('field-${f.key}'),
          decoration: InputDecoration(
            labelText: label,
            helperText: context.pick(f.hintAr, f.hintEn).isEmpty ? null : context.pick(f.hintAr, f.hintEn),
            helperMaxLines: 4,
          ),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in f.options)
              FilterChip(
                key: ValueKey('choice-${f.key}-$o'),
                label: Text(choiceLabel(context, o)),
                selected: set.contains(o),
                checkmarkColor: context.pal.onBar,
                labelStyle: TextStyle(
                  color: set.contains(o) ? context.pal.onBar : context.pal.primary,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (sel) => setState(() {
                  sel ? set.add(o) : set.remove(o);
                  _dirty = true;
                }),
              ),
          ]),
        );
      case FieldType.dateList:
        return _dateListEditor(f, label);
      case FieldType.choice when f.dynamicOptions.isNotEmpty:
        final opts = widget.dynamicChoices[f.dynamicOptions] ?? const <(String, String)>[];
        final cur = _values[f.key] as String?;
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          focusNode: _focusNode(f.key),
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
            _syncErrorSummaryAfterChange();
          }),
        );
      case FieldType.choice:
        // The closed button is 24 px tall (`DropdownButtonFormField`
        // defaults to `isDense`), so a two-line option cannot render there:
        // when a field defines per-option hints, the closed button shows
        // the plain one-line label while the open menu shows label + hint.
        final choiceItems = <DropdownMenuItem<String?>>[
          if (f.nullableChoice) const DropdownMenuItem<String?>(value: null, child: Text('—')),
          for (final o in {...f.options, if (_values[f.key] != null) _values[f.key] as String})
            DropdownMenuItem<String?>(value: o, child: _choiceOptionChild(f, o)),
        ];
        final hasChoiceHints =
            f.options.any((o) => fieldChoiceHint(context, f, o).isNotEmpty);
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          focusNode: _focusNode(f.key),
          isExpanded: true, // long labels ellipsize at 320 px / 200% text
          initialValue: _values[f.key] as String?,
          decoration: InputDecoration(
            labelText: label,
            helperText: context.pick(f.hintAr, f.hintEn).isEmpty ? null : context.pick(f.hintAr, f.hintEn),
            helperMaxLines: 4,
            helperStyle: context.pick(f.hintAr, f.hintEn).isEmpty
                ? null
                : TextStyle(fontSize: 13.5, color: context.pal.muted, height: 1.4),
          ),
          validator: (v) => f.required && (v == null || v.isEmpty) ? context.tr('required') : null,
          items: choiceItems,
          selectedItemBuilder: hasChoiceHints
              ? (context) => [
                    for (final item in choiceItems)
                      item.value == null
                          ? const Text('—')
                          : Text(fieldChoiceLabel(context, f, item.value!)),
                  ]
              : null,
          onChanged: (v) => setState(() {
            _values[f.key] = v;
            _dirty = true;
            _syncErrorSummaryAfterChange();
          }),
        );
      case FieldType.objectList:
        return _objectList(f);
      case FieldType.image:
        return _imageEditor(f);
      case FieldType.imageList:
        return _galleryEditor(f);
      default:
        return _textField(f, _text[f.key]!, focusNode: _focusNode(f.key));
    }
  }

  /// [FieldType.dateList]: one chip per date (× removes it) and an «add a
  /// date» chip that opens the date picker (ADR-051).
  Widget _dateListEditor(FieldDef f, String label) {
    final set = _values[f.key] as Set<String>;
    final dates = set.toList()..sort();
    final hint = context.pick(f.hintAr, f.hintEn);
    return InputDecorator(
      key: ValueKey('field-${f.key}'),
      decoration: InputDecoration(labelText: label, helperText: hint.isEmpty ? null : hint, helperMaxLines: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final d in dates)
          InputChip(
            key: ValueKey('date-${f.key}-$d'),
            label: Text(_dateChipLabel(d)),
            onDeleted: () => setState(() {
              set.remove(d);
              _dirty = true;
            }),
            deleteButtonTooltipMessage: context.tr('delete'),
          ),
        if (set.length < f.maxRows)
          ActionChip(
            key: ValueKey('dateAdd-${f.key}'),
            avatar: Icon(Icons.add_rounded, size: 18, color: context.pal.primary),
            label: Text(context.tr('addDate')),
            onPressed: () async {
              final epoch = _resetEpoch;
              final now = CairoTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(now.year, now.month, now.day),
                firstDate: DateTime(2000),
                // The rules accept 20xx years only (validReplaceDates; CodeRabbit on PR #44).
                lastDate: DateTime(2099, 12, 31),
                helpText: label,
              );
              if (picked == null || !mounted || epoch != _resetEpoch) return;
              setState(() {
                set.add(formatPickedDate(picked.year, picked.month, picked.day));
                _dirty = true;
              });
            },
          ),
      ]),
    );
  }

  /// «١٢ يوليو ٢٠٢٧» / "12 July 2027" for a stored 'YYYY-MM-DD'.
  String _dateChipLabel(String ymd) {
    final m = dateRe.firstMatch(ymd);
    if (m == null) return ymd;
    return formatDate(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)), arabic: context.isAr);
  }

  Future<void> _pickImage(FieldDef f) => _pickFromDevice(f.key, (enc) => _pending[f.key] = enc);

  /// Adds a picked photo to the [FieldType.imageList] field [f] (uploaded on save).
  Future<void> _pickGalleryImage(FieldDef f) =>
      _pickFromDevice(f.key, (enc) => _gallery[f.key]!.add(_GalleryEntry(null, enc, _ctrl(''))));

  Future<void> _addGalleryUrl(FieldDef f) async {
    final epoch = _resetEpoch;
    final url = await showDialog<String>(context: context, builder: (_) => const _ImageUrlDialog(initial: ''));
    if (url == null || !mounted || epoch != _resetEpoch) return;
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
    final epoch = _resetEpoch;
    final Uint8List? bytes;
    try {
      bytes = await widget.pickImage();
    } catch (e) {
      if (mounted && epoch == _resetEpoch) {
        messenger?.showSnackBar(SnackBar(content: Text(invalid)));
      }
      return;
    }
    if (bytes == null || !mounted || epoch != _resetEpoch) return;
    if (bytes.isEmpty) {
      if (mounted && epoch == _resetEpoch) {
        messenger?.showSnackBar(SnackBar(content: Text(empty)));
      }
      return;
    }
    setState(() => _processing = key);
    try {
      final enc = await widget.prepareImage(bytes);
      final err = validateMediaBytes(enc.length);
      if (err != null) throw const ImageTooLargeException();
      if (!mounted || epoch != _resetEpoch) return;
      setState(() {
        onReady(enc);
        _dirty = true;
      });
    } on ImageTooLargeException {
      if (mounted && epoch == _resetEpoch) {
        messenger?.showSnackBar(SnackBar(content: Text(tooLarge)));
      }
    } catch (_) {
      if (mounted && epoch == _resetEpoch) {
        messenger?.showSnackBar(SnackBar(content: Text(invalid)));
      }
    } finally {
      if (mounted && epoch == _resetEpoch && _processing == key) setState(() => _processing = null);
    }
  }

  Future<void> _askImageUrl(FieldDef f) async {
    final current = MediaImage.fromMap(_values[f.key]);
    // A stored link that is not usable any more is offered back for editing,
    // so fixing it does not mean retyping it from scratch.
    final initial = current?.source == MediaSource.url ? current!.url : (invalidImageUrl(_values[f.key]) ?? '');
    final epoch = _resetEpoch;
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _ImageUrlDialog(initial: initial),
    );
    if (url == null || !mounted || epoch != _resetEpoch) return;
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
    // A stored link that is not usable any more: the field shows the error
    // (not an empty placeholder) and keeps both fixes available — a new link
    // or removing the image.
    final invalidUrl = current == null ? invalidImageUrl(_values[f.key]) : null;
    final busy = _processing == f.key;
    final hasImage = pending != null || current != null || invalidUrl != null;
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
            : invalidUrl != null
                ? context.tr('invalidCoverImage')
                : current == null
                    ? context.tr('imageNone')
                    : (current.isRemote ? current.url : 'media/${current.mediaId}');
    // Narrow screens or large text: preview above the status and buttons.
    final stack = MediaQuery.sizeOf(context).width < 420 || MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;    final previewBox = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        color: context.pal.surfaceAlt,
        child: busy ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : preview,
      ),
    );
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // A staged replacement means the stored bad link is no longer the
      // state: the status shows the pending upload, not the error.
      Text(status,
          key: const Key('imageStatus'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: invalidUrl != null && pending == null ? context.pal.alert : context.pal.muted, fontSize: 12, fontWeight: invalidUrl != null && pending == null ? FontWeight.w700 : null)),
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
    FieldGroup.location: 'groupLocation',
    FieldGroup.contacts: 'groupContacts',
    FieldGroup.hero: 'groupHero',
    FieldGroup.history: 'groupHistory',
  };
  static const _groupIcons = {
    FieldGroup.program: Icons.campaign_outlined,
    FieldGroup.details: Icons.article_outlined,
    FieldGroup.media: Icons.photo_library_outlined,
    FieldGroup.location: Icons.place_outlined,
    FieldGroup.contacts: Icons.contact_phone_outlined,
    FieldGroup.hero: Icons.auto_stories_outlined,
    FieldGroup.history: Icons.history_edu_outlined,
  };

  /// A collapsible card for one detail-page group. Collapsed fields stay
  /// mounted (maintainState) so the form still validates and collects them.
  Widget _groupCard(FieldGroup g) {
    final fields = [for (final f in widget.fields) if (f.group == g && _isShown(f, _values)) f];
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
          final cover = widget.fields.any(
              (f) => f.type == FieldType.image && (_pending.containsKey(f.key) || MediaImage.fromMap(_values[f.key]) != null));
          return [
            if (photos > 0) context.tr('pillPhotos', {'n': '$photos'}),
            if (cover) context.tr('pillCover'),
            if (photos == 0 && !cover) context.tr('pillNoPhotos'),
          ];
        case FieldGroup.program:
        case FieldGroup.location:
        case FieldGroup.contacts:
        case FieldGroup.hero:
        case FieldGroup.history:
        case FieldGroup.basic:
          final n = [
            for (final f in fields)
              if (_text[f.key] case final TextEditingController c when c.text.trim().isNotEmpty)
                f
              else if (f.type == FieldType.objectList && (_rows[f.key]?.isNotEmpty ?? false))
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
    return switch (g) {
      FieldGroup.program ||
      FieldGroup.location ||
      FieldGroup.contacts ||
      FieldGroup.hero ||
      FieldGroup.history =>
        ListenableBuilder(listenable: Listenable.merge(controllers), builder: (_, _) => wrap()),
      _ => wrap(),
    };
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

  String? _blockSnippet(_Row row) {
    final type = _blockTypeOf(row);
    if (type == BlockTypes.list) {
      return blockSnippetSummary(
        type: type,
        textAr: [for (final it in row.listItems) it.arCtrl.text].join(PageBlock.listSeparator),
        textEn: [
          for (final it in row.listItems)
            widget.englishEnabled ? it.enCtrl.text : it.initialEn,
        ].join(PageBlock.listSeparator),
        account: row.listStyle,
        isAr: context.isAr,
      );
    }
    if (type == BlockTypes.details) {
      final d = row.detailsDraft;
      if (d == null) return '';
      final encoded = PageBlock.details(
        summaryAr: d.summaryArCtrl.text,
        bodyAr: d.bodyArCtrl.text,
        summaryEn: widget.englishEnabled ? d.summaryEnCtrl.text : d.initialSummaryEn,
        bodyEn: widget.englishEnabled ? d.bodyEnCtrl.text : d.initialBodyEn,
      );
      return blockSnippetSummary(
        type: type,
        textAr: encoded.textAr,
        textEn: encoded.textEn,
        isAr: context.isAr,
      );
    }
    return blockSnippetSummary(
      type: type,
      textAr: row.text['textAr']?.text ?? (row.values['textAr']?.toString() ?? ''),
      textEn: row.text['textEn']?.text ?? (row.values['textEn']?.toString() ?? ''),
      url: row.text['url']?.text ?? (row.values['url']?.toString() ?? ''),
      account: row.text['account']?.text ?? (row.values['account']?.toString() ?? ''),
      instapay: row.text['instapay']?.text ?? (row.values['instapay']?.toString() ?? ''),
      wallet: row.text['wallet']?.text ?? (row.values['wallet']?.toString() ?? ''),
      isAr: context.isAr,
    );
  }

  void _moveObjectRow(FieldDef f, int index, int delta) {
    final rows = _rows[f.key]!;
    final target = index + delta;
    if (target < 0 || target >= rows.length) return;
    setState(() {
      final moved = rows.removeAt(index);
      rows.insert(target, moved);
      if (f.collapsibleRows) {
        final expanded = _expandedRow[f.key];
        if (expanded == index) {
          _expandedRow[f.key] = target;
        } else if (expanded == target) {
          _expandedRow[f.key] = index;
        }
      }
      _dirty = true;
    });
  }

  void _removeObjectRow(FieldDef f, int index) {
    final rows = _rows[f.key]!;
    setState(() {
      final removed = rows.removeAt(index);
      if (_pendingErrorFocus != null && removed.ownsFocusNode(_pendingErrorFocus!.focusNode)) {
        _clearPendingErrorFocus();
      }
      removed.dispose();
      if (f.collapsibleRows) {
        final expanded = _expandedRow[f.key];
        if (expanded == index) {
          _expandedRow[f.key] = null;
        } else if (expanded != null && expanded > index) {
          _expandedRow[f.key] = expanded - 1;
        }
      }
      _dirty = true;
      _syncErrorSummaryAfterChange();
    });
  }

  Widget _objectList(FieldDef f) {
    final rows = _rows[f.key]!;
    return InputDecorator(
      decoration: InputDecoration(labelText: _label(f)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++)
          if (f.collapsibleRows && _expandedRow[f.key] != i)
            Card(
              key: ObjectKey(rows[i]),
              color: context.pal.background,
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _expandedRow[f.key] = i),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: context.pal.muted),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.pal.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                choiceLabel(context, _blockTypeOf(rows[i])),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: context.pal.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Builder(builder: (context) {
                              final snippet = _blockSnippet(rows[i]);
                              if (snippet == null) return const SizedBox.shrink();
                              final isEmpty = snippet.isEmpty;
                              return Text(
                                isEmpty ? context.tr('emptyBlockSnippet') : '· $snippet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isEmpty ? context.pal.muted : context.pal.ink,
                                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: context.tr('moveUp'),
                                icon: const Icon(Icons.arrow_upward, size: 20),
                                onPressed: i == 0 ? null : () => _moveObjectRow(f, i, -1),
                              ),
                              IconButton(
                                tooltip: context.tr('moveDown'),
                                icon: const Icon(Icons.arrow_downward, size: 20),
                                onPressed: i == rows.length - 1 ? null : () => _moveObjectRow(f, i, 1),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: context.tr('remove'),
                                icon: Icon(Icons.delete_outline, color: context.pal.alert, size: 20),
                                onPressed: () => _removeObjectRow(f, i),
                              ),
                              IconButton(
                                tooltip: context.tr('expandBlock'),
                                icon: const Icon(Icons.expand_more, size: 20),
                                onPressed: () => setState(() => _expandedRow[f.key] = i),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              key: ObjectKey(rows[i]),
              color: context.pal.background,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  if (f.collapsibleRows)
                    InkWell(
                      onTap: () => setState(() => _expandedRow[f.key] = null),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              '${i + 1}.',
                              style: TextStyle(fontWeight: FontWeight.bold, color: context.pal.muted),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.pal.surfaceAlt,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  choiceLabel(context, _blockTypeOf(rows[i])),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: context.pal.primary, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: context.tr('collapseBlock'),
                              icon: const Icon(Icons.expand_less, size: 20),
                              onPressed: () => setState(() => _expandedRow[f.key] = null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final sf in f.subFields)
                    if (_isShown(sf, rows[i].values))
                    KeyedSubtree(
                      key: rows[i].keyFor(sf.key),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: switch (sf.type) {
                          FieldType.boolean => AdminStateSwitch(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_label(sf)),
                              value: rows[i].values[sf.key] as bool,
                              onLabel: _switchLabels(context, sf).$1,
                              offLabel: _switchLabels(context, sf).$2,
                              onChanged: (v) => setState(() {
                                rows[i].values[sf.key] = v;
                                _dirty = true;
                              }),
                            ),
                          FieldType.choice => DropdownButtonFormField<String>(
                              focusNode: rows[i].focusFor(sf.key),
                              isExpanded: true,
                              initialValue: rows[i].values[sf.key] as String?,
                              decoration: InputDecoration(labelText: _label(sf)),
                              items: [
                                for (final o in sf.options)
                                  DropdownMenuItem(value: o, child: Text(choiceLabel(context, o))),
                              ],
                              onChanged: (v) => setState(() {
                                rows[i].values[sf.key] = v;
                                if (f.key == 'blocks' &&
                                    sf.key == 'type' &&
                                    v == BlockTypes.list &&
                                    rows[i].listItems.isEmpty) {
                                  rows[i].listStyle = ListStyles.bullet;
                                  rows[i].listItems.add(ListItemDraft.from());
                                }
                                if (f.key == 'blocks' &&
                                    sf.key == 'type' &&
                                    v == BlockTypes.details) {
                                  rows[i].detailsDraft ??= DetailsDraft.from();
                                }
                                _dirty = true;
                                _syncErrorSummaryAfterChange();
                              }),
                            ),
                          _ => _textField(sf, rows[i].text[sf.key]!,
                              focusNode: rows[i].focusFor(sf.key),
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
                                          : f.key == 'blocks' &&
                                                  sf.key == 'textAr' &&
                                                  rows[i].values['type'] == BlockTypes.heading
                                              ? () {
                                                  final err = validateHeadingBlock({
                                                    for (final e in rows[i].text.entries) e.key: e.value.text,
                                                  }, rows[i].values['type'] as String? ?? '');
                                                  return err == null ? null : context.tr(err);
                                                }
                                              : null),
                        },
                      ),
                    ),
                  if (f.key == 'blocks' && rows[i].values['type'] == BlockTypes.list)
                    KeyedSubtree(
                      key: rows[i].keyFor('list'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListBlockEditor(
                          blockIndex: i,
                          style: rows[i].listStyle,
                          items: rows[i].listItems,
                          englishEnabled: widget.englishEnabled,
                          onStyleChanged: (style) => setState(() {
                            rows[i].listStyle = style;
                            _dirty = true;
                            _syncErrorSummaryAfterChange();
                          }),
                          onChanged: _markDirty,
                          onAddItem: () {
                            if (rows[i].listItems.length >= listBlockMaxItems) return;
                            final draft = ListItemDraft.from();
                            setState(() {
                              rows[i].listItems.add(draft);
                              _dirty = true;
                              _syncErrorSummaryAfterChange();
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && draft.arFocus.canRequestFocus) {
                                draft.arFocus.requestFocus();
                              }
                            });
                          },
                          onRemoveItem: (itemIdx) => setState(() {
                            final removed = rows[i].listItems.removeAt(itemIdx);
                            if (_pendingErrorFocus != null &&
                                (identical(removed.arFocus, _pendingErrorFocus!.focusNode) ||
                                    identical(removed.enFocus, _pendingErrorFocus!.focusNode))) {
                              _clearPendingErrorFocus();
                            }
                            removed.dispose();
                            _dirty = true;
                            _syncErrorSummaryAfterChange();
                          }),
                          onMoveItem: (from, to) => setState(() {
                            final moved = rows[i].listItems.removeAt(from);
                            rows[i].listItems.insert(to, moved);
                            _dirty = true;
                            _syncErrorSummaryAfterChange();
                          }),
                          itemErrorText: _showErrorSummary
                              ? (itemIdx, isEn) {
                                  for (final issue in _listIssuesForRow(rows[i])) {
                                    if (issue.itemIndex == itemIdx && issue.isEn == isEn) {
                                      return context.tr(issue.code);
                                    }
                                  }
                                  return null;
                                }
                              : null,
                          blockErrorText: _showErrorSummary ? _listBlockErrorText(rows[i]) : null,
                        ),
                      ),
                    ),
                  if (f.key == 'blocks' &&
                      rows[i].values['type'] == BlockTypes.details &&
                      rows[i].detailsDraft != null)
                    KeyedSubtree(
                      key: rows[i].keyFor('details'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DetailsBlockEditor(
                          blockIndex: i,
                          draft: rows[i].detailsDraft!,
                          englishEnabled: widget.englishEnabled,
                          onChanged: _markDirty,
                          fieldErrorText: _showErrorSummary
                              ? (field, isEn) {
                                  for (final issue in _detailsIssuesForRow(rows[i])) {
                                    if (issue.field == field && issue.isEn == isEn) {
                                      return context.tr(issue.code);
                                    }
                                  }
                                  return null;
                                }
                              : null,
                        ),
                      ),
                    ),
                  // Wrap: at 320 px / 200% text the buttons flow onto two lines.
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: context.tr('moveUp'),
                      onPressed: i == 0 ? null : () => _moveObjectRow(f, i, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: context.tr('moveDown'),
                      onPressed: i == rows.length - 1 ? null : () => _moveObjectRow(f, i, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    ]),
                    TextButton.icon(
                      onPressed: () => _removeObjectRow(f, i),
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
                      if (f.collapsibleRows) {
                        _expandedRow[f.key] = rows.length - 1;
                      }
                      _dirty = true;
                    }),
            icon: const Icon(Icons.add),
            label: Text(context.tr('addRow')),
          ),
        ),
      ]),
    );
  }

  Widget _advancedCard(List<FieldDef> fields) {
    return Card(
      key: const ValueKey('groupCard-advanced'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('group-advanced'),
        controller: _advancedCtl,
        maintainState: true,
        leading: Icon(Icons.tune_rounded, color: context.pal.primary),
        title: Text(context.tr('advancedOptions'),
            style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.primary)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
        ],
      ),
    );
  }

  bool get _canPreviewPage => widget.def?.name == 'pages' && widget.popOnSave;

  void _openPagePreview() {
    final collected = collect();
    final page = CustomPage.fromMap(widget.docId ?? 'preview', collected);
    final pendingHero = _pending['image'];
    final pendingAlt = _text['image']?.text.trim() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PagePreviewScreen(
          page: page,
          pendingHeroBytes: pendingHero?.bytes,
          pendingHeroAlt: pendingAlt,
          media: widget.media,
          englishEnabled: widget.englishEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final embedded = !widget.popOnSave;
    final narrowTopBar = MediaQuery.sizeOf(context).width < 480;
    final advancedFields = [
      for (final f in widget.fields)
        if (f.group == FieldGroup.basic && f.advanced && _isShown(f, _values)) f,
    ];
    final summaryErrors = _showErrorSummary ? _collectErrors() : const <_FieldErrorEntry>[];
    final saveButton = FilledButton.icon(
      key: const Key('editor-save'),
      onPressed: _saving ? null : save,
      icon: _saving
          ? SizedBox.square(
              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onBar))
          : const Icon(Icons.save),
      label: Text(context.tr(_saving ? 'saving' : 'save')),
    );
    return UnsavedGuard(
      dirty: _dirty,
      handlePop: widget.popOnSave,
      onBrowserBackDiscard: widget.popOnSave ? null : _resetToInitial,
      child: Scaffold(
        backgroundColor: context.pal.background,
        appBar: embedded
            ? null
            : AppBar(
                title: Text(widget.title),
                actions: [
                  if (_canPreviewPage)
                    narrowTopBar
                        ? IconButton(
                            key: const Key('editor-preview-top'),
                            tooltip: context.tr('previewPage'),
                            onPressed: _saving ? null : _openPagePreview,
                            icon: Icon(Icons.visibility_outlined, color: context.pal.onPrimaryAccent),
                          )
                        : TextButton.icon(
                            key: const Key('editor-preview-top'),
                            onPressed: _saving ? null : _openPagePreview,
                            icon: Icon(Icons.visibility_outlined, size: 18, color: context.pal.onPrimaryAccent),
                            label: Text(
                              context.tr('previewPage'),
                              style: TextStyle(color: context.pal.onPrimaryAccent, fontWeight: FontWeight.w700),
                            ),
                          ),
                  TextButton(
                    key: const Key('editor-save-top'),
                    onPressed: _saving ? null : save,
                    child: Text(context.tr(_saving ? 'saving' : 'save'),
                        style: TextStyle(color: context.pal.onPrimaryAccent, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
        bottomNavigationBar: UnsavedBar(
          dirty: _dirty,
          saving: _saving,
          onSave: save,
          onCancel: _handleCancel,
        ),
        body: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (n) {
                  final target = _pendingErrorFocus;
                  if (target == null) return false;
                  if (_lastMaxScrollExtent == n.metrics.maxScrollExtent) return false;
                  _lastMaxScrollExtent = n.metrics.maxScrollExtent;
                  if (_pendingFocusSteps <= 0) {
                    _clearPendingErrorFocus();
                    return false;
                  }
                  _pendingFocusSteps--;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_pendingErrorFocus == target) {
                      _applyErrorFocus(target, animate: false);
                    }
                  });
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (embedded && (widget.title.isNotEmpty || widget.help.isNotEmpty))
                        AdminScreenHeader(
                          title: widget.title,
                          help: widget.help,
                          padding: const EdgeInsets.only(bottom: 12),
                        ),
                      if (_remoteStale)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: MaterialBanner(
                            content: Text(context.tr('updatedElsewhere')),
                            actions: [
                              TextButton(
                                onPressed: _latestRemote == null ? null : _reloadRemote,
                                child: Text(context.tr('reload')),
                              ),
                            ],
                          ),
                        ),
                      if (_notice != null && _notice!.isNotEmpty) _noticeBanner(context, _notice!),
                      if (_saveError != null) _saveErrorBanner(context, _saveError!),
                      if (summaryErrors.isNotEmpty) _errorSummaryCard(context, summaryErrors),
                      for (final f in widget.fields)
                        if (f.group == FieldGroup.basic && !f.advanced && _isShown(f, _values))
                          Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
                      if (advancedFields.isNotEmpty) _advancedCard(advancedFields),
                      for (final g in FieldGroup.values)
                        if (g != FieldGroup.basic && widget.fields.any((f) => f.group == g && _isShown(f, _values)))
                          _groupCard(g),
                      if (widget.def?.name == 'seasons' && _hasInitialValues) ...[
                        if (overlappingActiveSeasons(
                              collect(),
                              existingDocs: widget.existingDocs,
                              docId: widget.docId,
                            )
                            case final overlapping when overlapping.isNotEmpty)
                          _seasonOverlapWarningBanner(context, overlapping),
                      ],
                      const SizedBox(height: 8),
                      if (_canPreviewPage)
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('editor-preview'),
                              onPressed: _saving ? null : _openPagePreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(context.tr('previewPage')),
                            ),
                            saveButton,
                          ],
                        )
                      else
                        saveButton,
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldErrorEntry {
  final String id;
  final String label;
  final FieldGroup? group;
  final bool advanced;
  final GlobalKey fieldKey;
  final FocusNode focusNode;
  const _FieldErrorEntry({
    required this.id,
    required this.label,
    required this.fieldKey,
    required this.focusNode,
    this.group,
    this.advanced = false,
  });
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
  final Map<String, FocusNode> focus = {};
  final Map<String, GlobalKey> keys = {};
  final Map<String, dynamic> initial = {};
  final List<FieldDef> fields;
  late final bool _hasTypeField = fields.any((f) => f.key == 'type');
  String listStyle = ListStyles.bullet;
  final List<ListItemDraft> listItems = [];
  DetailsDraft? detailsDraft;
  _Row(this.fields);

  FocusNode focusFor(String k) => focus.putIfAbsent(k, () => FocusNode());
  GlobalKey keyFor(String k) => keys.putIfAbsent(k, () => GlobalKey());

  bool ownsFocusNode(FocusNode node) =>
      focus.values.contains(node) ||
      listItems.any((it) => identical(it.arFocus, node) || identical(it.enFocus, node)) ||
      (detailsDraft?.ownsFocusNode(node) ?? false);

  bool ownsFieldKey(GlobalKey key) =>
      keys.values.contains(key) ||
      listItems.any((it) => identical(it.arKey, key) || identical(it.enKey, key)) ||
      (detailsDraft?.ownsFieldKey(key) ?? false);

  factory _Row.from(List<FieldDef> fields, Map data, VoidCallback onChange, {bool isNew = false}) {
    final r = _Row(fields);
    for (final f in fields) {
      var v = data[f.key];
      if (isNew && f.key == 'id' && f.hidden && (v == null || v.toString().trim().isEmpty)) {
        v = DayEvent.generateRandomId();
      }
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
    final blockType = r._hasTypeField ? r.values['type'] : null;
    if (blockType == BlockTypes.list) {
      r.listStyle = (data['account']?.toString() == ListStyles.numbered)
          ? ListStyles.numbered
          : ListStyles.bullet;
      final rawAr = data['textAr']?.toString() ?? '';
      final rawEn = data['textEn']?.toString() ?? '';
      final arParts = rawAr.isEmpty ? const <String>[] : rawAr.split(PageBlock.listSeparator);
      final enParts = rawEn.isEmpty ? const <String>[] : rawEn.split(PageBlock.listSeparator);
      final count = arParts.length > enParts.length ? arParts.length : enParts.length;
      for (var i = 0; i < count; i++) {
        r.listItems.add(ListItemDraft.from(
          ar: i < arParts.length ? arParts[i] : '',
          en: i < enParts.length ? enParts[i] : '',
        ));
      }
      if (isNew && r.listItems.isEmpty) {
        r.listItems.add(ListItemDraft.from());
      }
    }
    if (blockType == BlockTypes.details) {
      final parsed = PageBlock.fromMap(data)?.details;
      r.detailsDraft = DetailsDraft.from(
        summaryAr: parsed?.summaryAr ?? '',
        summaryEn: parsed?.summaryEn ?? '',
        bodyAr: parsed?.bodyAr ?? '',
        bodyEn: parsed?.bodyEn ?? '',
      );
    }
    r.initial.addAll(r.collect());
    return r;
  }

  Map<String, dynamic> collect({bool englishEnabled = true}) {
    final blockType = _hasTypeField ? values['type'] : null;
    if (blockType == BlockTypes.list) {
      return PageBlock.list(
        items: [
          for (final it in listItems)
            (ar: it.arCtrl.text, en: englishEnabled ? it.enCtrl.text : it.initialEn),
        ],
        style: listStyle,
      ).toMap();
    }
    if (blockType == BlockTypes.details) {
      final d = detailsDraft;
      if (d == null) return const PageBlock(type: BlockTypes.details).toMap();
      return PageBlock.details(
        summaryAr: d.summaryArCtrl.text,
        bodyAr: d.bodyArCtrl.text,
        summaryEn: englishEnabled ? d.summaryEnCtrl.text : d.initialSummaryEn,
        bodyEn: englishEnabled ? d.bodyEnCtrl.text : d.initialBodyEn,
      ).toMap();
    }
    return {
      for (final f in fields)
        f.key: (!englishEnabled && f.lang == 'en')
            ? initial[f.key]
            : switch (f.type) {
                FieldType.boolean || FieldType.choice => values[f.key],
                FieldType.phone => normalizePhoneInput(text[f.key]!.text.trim()),
                FieldType.time => parseFieldValue(f, text[f.key]!.text),
                FieldType.date => () {
                    final raw = normalizeDigits(text[f.key]!.text.trim());
                    final d = parseFieldDateTime(raw);
                    return d == null ? raw : formatPickedDate(d.$1, d.$2, d.$3);
                  }(),
                FieldType.dateTime => () {
                    final raw = normalizeDigits(text[f.key]!.text.trim());
                    final d = parseFieldDateTime(raw);
                    return d == null || dateTimeRe.firstMatch(raw) == null
                        ? raw
                        : formatPickedDateTime(d.$1, d.$2, d.$3, d.$4, d.$5);
                  }(),
                _ => text[f.key]!.text.trim(),
              },
    };
  }

  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
    for (final it in listItems) {
      it.dispose();
    }
    detailsDraft?.dispose();
  }
}

/// Human labels for stored option keys (falls back to the key).
String choiceLabel(BuildContext context, String key) {
  final k = 'opt_$key';
  final t = context.tr(k);
  return t == k ? key : t;
}

/// Option label scoped to [f.key] first (`opt_<field>_<option>`), falling back to [choiceLabel].
String fieldChoiceLabel(BuildContext context, FieldDef f, String key) {
  final scopedKey = 'opt_${f.key}_$key';
  final scoped = context.tr(scopedKey);
  return scoped == scopedKey ? choiceLabel(context, key) : scoped;
}

/// Per-option one-line hint (`opt_<field>_<option>_hint`), or '' when the
/// field defines none for this option.
String fieldChoiceHint(BuildContext context, FieldDef f, String key) {
  final hintKey = 'opt_${f.key}_${key}_hint';
  final hint = context.tr(hintKey);
  return hint == hintKey ? '' : hint;
}

class _LooseDatePickerDialog extends StatefulWidget {
  final String title;
  final ({int year, int? month, int? day})? initial;
  final int defaultYear;

  const _LooseDatePickerDialog({
    required this.title,
    required this.initial,
    required this.defaultYear,
  });

  @override
  State<_LooseDatePickerDialog> createState() => _LooseDatePickerDialogState();
}

class _LooseDatePickerDialogState extends State<_LooseDatePickerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dayKey = GlobalKey<FormFieldState<int?>>();
  late final TextEditingController _yearCtrl;
  int? _month;
  int? _day;

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: '${widget.initial?.year ?? widget.defaultYear}');
    _month = widget.initial?.month;
    _day = widget.initial?.day;
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  int? _parsedYear() {
    final y = int.tryParse(normalizeDigits(_yearCtrl.text.trim()));
    if (y == null || y < 1000 || y > 9999) return null;
    return y;
  }

  void _syncDayBounds() {
    if (_month == null) {
      if (_day != null) {
        _day = null;
        _dayKey.currentState?.didChange(null);
      }
      return;
    }
    final y = _parsedYear();
    if (y != null && _day != null) {
      final maxD = daysInMonth(y, _month!);
      if (_day! > maxD) {
        _day = maxD;
        _dayKey.currentState?.didChange(_day);
      }
    }
  }

  void _ok() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final y = _parsedYear()!;
    final day = (_month == null || _day == null) ? null : _day!.clamp(1, daysInMonth(y, _month!));
    Navigator.pop(context, formatLooseDateValue(y, _month, day));
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.isAr;
    final y = _parsedYear() ?? 2000;
    final maxDay = _month == null ? 0 : daysInMonth(y, _month!);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('looseDate-year'),
                controller: _yearCtrl,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('looseDateYear'),
                  hintText: '${widget.defaultYear}',
                ),
                validator: (_) => _parsedYear() == null ? context.tr('invalidDate') : null,
                onChanged: (_) => setState(_syncDayBounds),
                onFieldSubmitted: (_) => _ok(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                key: const ValueKey('looseDate-month'),
                isExpanded: true,
                initialValue: _month,
                decoration: InputDecoration(labelText: context.tr('looseDateMonth')),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(context.tr('looseDateYearOnly'))),
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem<int?>(
                      value: m,
                      child: Text(ar ? monthNamesAr[m] : fullMonthNamesEn[m]),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _month = v;
                  _syncDayBounds();
                }),
              ),
              if (_month != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  key: _dayKey,
                  isExpanded: true,
                  initialValue: _day,
                  decoration: InputDecoration(labelText: context.tr('looseDateDay')),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(context.tr('looseDateDayNone'))),
                    for (var d = 1; d <= maxDay; d++)
                      DropdownMenuItem<int?>(
                        key: ValueKey('looseDate-day-$d'),
                        value: d,
                        child: Text(ar ? toArabicDigits('$d') : '$d'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _day = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(key: const ValueKey('looseDate-ok'), onPressed: _ok, child: Text(context.tr('ok'))),
      ],
    );
  }
}

String _clipSnippet(String raw) {
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '';
  if (collapsed.length > 40) {
    return '${collapsed.substring(0, 40)}…';
  }
  return collapsed;
}

/// Extracts and formats the preview snippet for a collapsed block in doc editor.
/// Returns:
/// - `null` when snippet should be suppressed entirely (image block with URL but empty caption).
/// - `''` when block is empty (should show `(فاضي)`).
/// - non-empty String when a snippet is available (caller prefixes with `'· '`).
@visibleForTesting
String? blockSnippetSummary({
  required String type,
  String textAr = '',
  String textEn = '',
  String url = '',
  String account = '',
  String instapay = '',
  String wallet = '',
  bool isAr = true,
}) {
  if (type == BlockTypes.list) {
    final items = [
      for (final part in textAr.split(PageBlock.listSeparator))
        if (part.replaceAll(PageBlock.separator, '').trim().isNotEmpty)
          part.replaceAll(PageBlock.separator, '').trim(),
    ];
    if (items.isEmpty) return '';
    final first = _clipSnippet(items.first);
    if (items.length == 1) return first;
    final rest = items.length - 1;
    final countStr = isAr ? toArabicDigits('$rest') : '$rest';
    return '$first (+$countStr)';
  }
  String raw = '';
  if (type == BlockTypes.image) {
    if (textAr.trim().isNotEmpty) {
      raw = textAr;
    } else if (textEn.trim().isNotEmpty) {
      raw = textEn;
    } else if (url.trim().isNotEmpty) {
      return null;
    } else {
      return '';
    }
  } else if (type == BlockTypes.button || type == BlockTypes.link) {
    if (textAr.trim().isNotEmpty) {
      raw = textAr;
    } else if (textEn.trim().isNotEmpty) {
      raw = textEn;
    } else if (url.trim().isNotEmpty) {
      raw = url;
    }
  } else if (type == BlockTypes.heading || type == BlockTypes.paragraph) {
    if (textAr.trim().isNotEmpty) {
      raw = textAr;
    } else if (textEn.trim().isNotEmpty) {
      raw = textEn;
    }
  } else if (type == BlockTypes.details) {
    final arParts = textAr.split(PageBlock.listSeparator);
    final enParts = textEn.split(PageBlock.listSeparator);
    final summaryAr = arParts.isNotEmpty ? arParts[0].trim() : '';
    final bodyAr = arParts.length > 1 ? arParts[1].trim() : '';
    final summaryEn = enParts.isNotEmpty ? enParts[0].trim() : '';
    final bodyEn = enParts.length > 1 ? enParts[1].trim() : '';
    for (final v in [summaryAr, summaryEn, bodyAr, bodyEn]) {
      if (v.isNotEmpty) {
        raw = v;
        break;
      }
    }
  } else if (type == BlockTypes.donation) {
    if (textAr.trim().isNotEmpty) {
      raw = textAr;
    } else if (textEn.trim().isNotEmpty) {
      raw = textEn;
    } else if (account.trim().isNotEmpty) {
      raw = account;
    } else if (instapay.trim().isNotEmpty) {
      raw = instapay;
    } else if (wallet.trim().isNotEmpty) {
      raw = wallet;
    }
  } else {
    for (final v in [textAr, textEn, account, instapay, wallet, url]) {
      if (v.trim().isNotEmpty) {
        raw = v;
        break;
      }
    }
  }

  return _clipSnippet(raw);
}
