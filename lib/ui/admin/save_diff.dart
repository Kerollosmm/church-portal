import '../../domain/daily_verse.dart';
import '../../domain/features.dart';
import '../../domain/image_style.dart';
import 'admin_schema.dart';
import 'admin_strings.dart';
import 'admin_validators.dart';

/// Maximum number of changed-field rows rendered in the save-confirmation dialog.
const int maxSaveDiffRows = 12;

/// Maximum length of a single-line scalar value displayed as `old → new`.
const int maxShortDiffLen = 36;

/// One human-readable field diff entry shown before saving high-impact docs.
class SaveDiffRow {
  final String label;
  final String? oldValue;
  final String? newValue;
  final bool changedOnly;

  const SaveDiffRow({
    required this.label,
    this.oldValue,
    this.newValue,
    this.changedOnly = false,
  });
}

/// Capped list of changed-field rows plus how many additional rows were omitted.
class SaveDiffSummary {
  final List<SaveDiffRow> rows;
  final int overflowCount;

  const SaveDiffSummary({
    required this.rows,
    this.overflowCount = 0,
  });

  bool get isEmpty => rows.isEmpty && overflowCount == 0;
  bool get isNotEmpty => !isEmpty;
}

String _lookup(bool isAr, String key, String Function(String key)? tr) {
  if (tr != null) return tr(key);
  final pair = adminStrings[key];
  if (pair != null) return pair[isAr ? 0 : 1];
  return key;
}

(String, String) _boolKeysFor(String fieldKey) => switch (fieldKey) {
      'visible' => ('switch_visible', 'switch_hidden'),
      'sample' => ('switch_sample', 'switch_confirmed'),
      'active' => ('switch_active', 'switch_stopped'),
      'replacesDay' => ('switch_replaces_on', 'switch_replaces_off'),
      'showInNav' => ('switch_nav_on', 'switch_nav_off'),
      'featured' => ('switch_featured_on', 'switch_featured_off'),
      _ => ('switch_enabled', 'switch_disabled'),
    };

String? _formatShortScalar(Object? v) {
  if (v == null) return '—';
  if (v is DateTime) return fmtDateTime(v);
  if (v is num) return '$v';
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return '—';
    if (s.contains('\n') || s.contains('\r') || s.length > maxShortDiffLen) return null;
    return s;
  }
  return null;
}

String? _formatChoice(
  FieldDef f,
  Object? v, {
  required bool isAr,
  String Function(String key)? tr,
}) {
  final raw = (v ?? '').toString().trim();
  if (raw.isEmpty) return '—';
  final scopedKey = 'opt_${f.key}_$raw';
  final scoped = _lookup(isAr, scopedKey, tr);
  final resolved = scoped != scopedKey
      ? scoped
      : () {
          final plainKey = 'opt_$raw';
          final plain = _lookup(isAr, plainKey, tr);
          return plain != plainKey ? plain : raw;
        }();
  if (resolved.contains('\n') || resolved.contains('\r') || resolved.length > maxShortDiffLen) {
    return null;
  }
  return resolved;
}

SaveDiffSummary _capRows(List<SaveDiffRow> all, int maxRows) {
  if (all.length <= maxRows) {
    return SaveDiffSummary(rows: all);
  }
  return SaveDiffSummary(
    rows: all.sublist(0, maxRows),
    overflowCount: all.length - maxRows,
  );
}

/// Builds human-readable changed-field rows for a [DocEditor] form from
/// [fields], comparing [initial] against [current].
SaveDiffSummary buildSaveDiffRows(
  List<FieldDef> fields,
  Map<String, dynamic> initial,
  Map<String, dynamic> current, {
  required bool isAr,
  String Function(String key)? tr,
  int maxRows = maxSaveDiffRows,
}) {
  final all = <SaveDiffRow>[];
  for (final f in fields) {
    if (f.hidden) continue;
    final oldVal = initial[f.key];
    final newVal = current[f.key];
    if (sameValue(oldVal, newVal)) continue;

    final rawLabel = (isAr ? f.labelAr : f.labelEn).trim();
    final label = rawLabel.isEmpty ? f.key : rawLabel;

    if (f.type == FieldType.boolean) {
      final (onKey, offKey) = _boolKeysFor(f.key);
      final oldStr = oldVal is bool ? _lookup(isAr, oldVal ? onKey : offKey, tr) : '—';
      final newStr = newVal is bool ? _lookup(isAr, newVal ? onKey : offKey, tr) : '—';
      all.add(SaveDiffRow(label: label, oldValue: oldStr, newValue: newStr));
      continue;
    }

    if (f.type == FieldType.choice) {
      final oldStr = _formatChoice(f, oldVal, isAr: isAr, tr: tr);
      final newStr = _formatChoice(f, newVal, isAr: isAr, tr: tr);
      if (oldStr == null || newStr == null) {
        all.add(SaveDiffRow(label: label, changedOnly: true));
      } else {
        all.add(SaveDiffRow(label: label, oldValue: oldStr, newValue: newStr));
      }
      continue;
    }

    if (f.type == FieldType.multiline ||
        f.type == FieldType.objectList ||
        f.type == FieldType.image ||
        f.type == FieldType.imageList ||
        f.type == FieldType.weekdays ||
        f.type == FieldType.choices ||
        f.type == FieldType.dateList) {
      all.add(SaveDiffRow(label: label, changedOnly: true));
      continue;
    }

    final oldStr = _formatShortScalar(oldVal);
    final newStr = _formatShortScalar(newVal);
    if (oldStr == null || newStr == null) {
      all.add(SaveDiffRow(label: label, changedOnly: true));
    } else {
      all.add(SaveDiffRow(label: label, oldValue: oldStr, newValue: newStr));
    }
  }
  return _capRows(all, maxRows);
}

/// Builds human-readable changed-field rows for [FeaturesEditor] comparing
/// [before] and [after].
SaveDiffSummary buildFeaturesSaveDiffRows(
  FeatureSettings before,
  FeatureSettings after, {
  required bool isAr,
  String Function(String key)? tr,
  int maxRows = maxSaveDiffRows,
}) {
  String t(String key) => _lookup(isAr, key, tr);
  String pick(String ar, String en) => isAr ? ar : en;
  String onOff(bool v, [String onKey = 'switch_enabled', String offKey = 'switch_disabled']) =>
      t(v ? onKey : offKey);

  final all = <SaveDiffRow>[];

  void addShort(String label, String oldRaw, String newRaw) {
    final o = _formatShortScalar(oldRaw);
    final n = _formatShortScalar(newRaw);
    if (o == null || n == null) {
      all.add(SaveDiffRow(label: label, changedOnly: true));
    } else {
      all.add(SaveDiffRow(label: label, oldValue: o, newValue: n));
    }
  }

  for (final s in Sections.all) {
    final b = before.enabled(s);
    final a = after.enabled(s);
    if (b != a) {
      final labels = Sections.labels[s];
      all.add(SaveDiffRow(
        label: labels != null ? pick(labels[0], labels[1]) : s,
        oldValue: onOff(b),
        newValue: onOff(a),
      ));
    }
  }

  if (before.aboutMilestones != after.aboutMilestones) {
    all.add(SaveDiffRow(
      label: t('aboutMilestonesSwitch'),
      oldValue: onOff(before.aboutMilestones),
      newValue: onOff(after.aboutMilestones),
    ));
  }

  if (before.englishEnabled != after.englishEnabled) {
    all.add(SaveDiffRow(
      label: t('englishEnabledSwitch'),
      oldValue: onOff(before.englishEnabled),
      newValue: onOff(after.englishEnabled),
    ));
  }

  if (!sameValue(before.homeOrder, after.homeOrder)) {
    all.add(SaveDiffRow(label: t('homeLayout'), changedOnly: true));
  }

  for (final b in HomeBlocks.defaultOrder) {
    final wasShown = !before.homeHidden.contains(b);
    final nowShown = !after.homeHidden.contains(b);
    if (wasShown != nowShown) {
      final labels = HomeBlocks.labels[b];
      final blockLabel = labels != null ? pick(labels[0], labels[1]) : b;
      all.add(SaveDiffRow(
        label: '${t('homeLayout')} — $blockLabel',
        oldValue: onOff(wasShown, 'switch_visible', 'switch_hidden'),
        newValue: onOff(nowShown, 'switch_visible', 'switch_hidden'),
      ));
    }
  }

  if (before.heroTitleAr != after.heroTitleAr) addShort(t('heroTitleAr'), before.heroTitleAr, after.heroTitleAr);
  if (before.heroTitleEn != after.heroTitleEn) addShort(t('heroTitleEn'), before.heroTitleEn, after.heroTitleEn);
  if (before.heroSubtitleAr != after.heroSubtitleAr) {
    addShort(t('heroSubtitleAr'), before.heroSubtitleAr, after.heroSubtitleAr);
  }
  if (before.heroSubtitleEn != after.heroSubtitleEn) {
    addShort(t('heroSubtitleEn'), before.heroSubtitleEn, after.heroSubtitleEn);
  }
  if (before.heroMotion != after.heroMotion) {
    all.add(SaveDiffRow(
      label: t('heroMotion'),
      oldValue: onOff(before.heroMotion),
      newValue: onOff(after.heroMotion),
    ));
  }
  if (before.heroShowAddress != after.heroShowAddress) {
    all.add(SaveDiffRow(
      label: t('heroShowAddress'),
      oldValue: onOff(before.heroShowAddress, 'switch_visible', 'switch_hidden'),
      newValue: onOff(after.heroShowAddress, 'switch_visible', 'switch_hidden'),
    ));
  }

  if (before.dailyVerse.mode != after.dailyVerse.mode) {
    all.add(SaveDiffRow(
      label: t('dailyVerseTitle'),
      oldValue: t(before.dailyVerse.mode == DailyVerseConfig.daily ? 'dailyVerseModeDaily' : 'dailyVerseModeFixed'),
      newValue: t(after.dailyVerse.mode == DailyVerseConfig.daily ? 'dailyVerseModeDaily' : 'dailyVerseModeFixed'),
    ));
  } else if (before.dailyVerse != after.dailyVerse) {
    all.add(SaveDiffRow(label: t('dailyVerseTitle'), changedOnly: true));
  }

  for (final p in CustomizablePages.all) {
    if (before.pageHeader(p) != after.pageHeader(p)) {
      final labels = CustomizablePages.labels[p];
      final pageLabel = labels != null ? pick(labels[0], labels[1]) : p;
      all.add(SaveDiffRow(label: '${t('pageHeadersTitle')} — $pageLabel', changedOnly: true));
    }
  }

  if (before.bannerEnabled != after.bannerEnabled) {
    all.add(SaveDiffRow(
      label: t('showBanner'),
      oldValue: onOff(before.bannerEnabled, 'switch_visible', 'switch_hidden'),
      newValue: onOff(after.bannerEnabled, 'switch_visible', 'switch_hidden'),
    ));
  }
  if (before.bannerAr != after.bannerAr) addShort(t('bannerAr'), before.bannerAr, after.bannerAr);
  if (before.bannerEn != after.bannerEn) addShort(t('bannerEn'), before.bannerEn, after.bannerEn);
  if (before.bannerLink != after.bannerLink) addShort(t('bannerLink'), before.bannerLink, after.bannerLink);

  if (before.footer.showPhones != after.footer.showPhones) {
    all.add(SaveDiffRow(
      label: t('footerShowPhones'),
      oldValue: onOff(before.footer.showPhones, 'switch_visible', 'switch_hidden'),
      newValue: onOff(after.footer.showPhones, 'switch_visible', 'switch_hidden'),
    ));
  }
  if (before.footer.showSocials != after.footer.showSocials) {
    all.add(SaveDiffRow(
      label: t('footerShowSocials'),
      oldValue: onOff(before.footer.showSocials, 'switch_visible', 'switch_hidden'),
      newValue: onOff(after.footer.showSocials, 'switch_visible', 'switch_hidden'),
    ));
  }
  if (before.footer.showQuickLinks != after.footer.showQuickLinks) {
    all.add(SaveDiffRow(
      label: t('footerShowQuickLinks'),
      oldValue: onOff(before.footer.showQuickLinks, 'switch_visible', 'switch_hidden'),
      newValue: onOff(after.footer.showQuickLinks, 'switch_visible', 'switch_hidden'),
    ));
  }
  if (before.footer.noteAr != after.footer.noteAr) {
    addShort(t('footerNoteAr'), before.footer.noteAr, after.footer.noteAr);
  }
  if (before.footer.noteEn != after.footer.noteEn) {
    addShort(t('footerNoteEn'), before.footer.noteEn, after.footer.noteEn);
  }

  for (final c in ImageStyles.collections) {
    final b = before.imageStyleFor(c, '');
    final a = after.imageStyleFor(c, '');
    if (b != a) {
      final colLabels = ImageStyles.collectionLabels[c];
      final oldLabels = ImageStyles.labels[b];
      final newLabels = ImageStyles.labels[a];
      all.add(SaveDiffRow(
        label: '${t('imageDisplay')} — ${colLabels != null ? pick(colLabels[0], colLabels[1]) : c}',
        oldValue: oldLabels != null ? pick(oldLabels[0], oldLabels[1]) : b,
        newValue: newLabels != null ? pick(newLabels[0], newLabels[1]) : a,
      ));
    }
  }

  if (before.theme != after.theme) {
    final oldLabels = ThemePresets.labels[before.theme];
    final newLabels = ThemePresets.labels[after.theme];
    all.add(SaveDiffRow(
      label: t('themeColor'),
      oldValue: oldLabels != null ? pick(oldLabels[0], oldLabels[1]) : before.theme,
      newValue: newLabels != null ? pick(newLabels[0], newLabels[1]) : after.theme,
    ));
  }

  if (!sameValue(before.occasions.toMap(), after.occasions.toMap()) ||
      !sameValue(before.occasions.colorsToMap(), after.occasions.colorsToMap())) {
    all.add(SaveDiffRow(label: t('themeOccasionsDiff'), changedOnly: true));
  }

  if (before.heroSeasonTint != after.heroSeasonTint) {
    all.add(SaveDiffRow(
      label: t('heroSeasonTint'),
      oldValue: onOff(before.heroSeasonTint),
      newValue: onOff(after.heroSeasonTint),
    ));
  }

  return _capRows(all, maxRows);
}
