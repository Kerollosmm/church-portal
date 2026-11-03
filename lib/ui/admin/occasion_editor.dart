import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/hero_video.dart';
import '../../domain/occasion_theme.dart';

/// Admin → Settings → "Site theme & occasions" (ADR-025): the selected
/// preset (the manual override), automatic switching by Cairo date with an
/// admin schedule and the Coptic Easter dates, and per-preset colour edits
/// that are auto-corrected for contrast. Edits go to [onChanged]; the
/// features screen saves them.
class OccasionThemeEditor extends StatefulWidget {
  final FeatureSettings value;

  /// Applies an edit to the editor's *current* settings (several taps can land
  /// before a rebuild).
  final void Function(FeatureSettings Function(FeatureSettings) edit) onChanged;

  /// Today on the Cairo calendar (tests pin it).
  final DateTime? today;
  const OccasionThemeEditor({super.key, required this.value, required this.onChanged, this.today});

  @override
  State<OccasionThemeEditor> createState() => _OccasionThemeEditorState();
}

class _OccasionThemeEditorState extends State<OccasionThemeEditor> {
  late String _editing = widget.value.theme;
  final Map<String, TextEditingController> _hex = {for (final k in ThemePalette.keys) k: TextEditingController()};

  FeatureSettings get f => widget.value;
  OccasionConfig get o => f.occasions;

  DateTime get _today {
    final t = widget.today;
    if (t != null) return DateTime.utc(t.year, t.month, t.day);
    final c = CairoTime.now();
    return DateTime.utc(c.year, c.month, c.day);
  }

  @override
  void initState() {
    super.initState();
    _loadHex();
  }

  @override
  void dispose() {
    for (final c in _hex.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The colour fields show the preset with the stored edits (as typed).
  void _loadHex() {
    final base = ThemePresets.palettes[_editing]!;
    final raw = ThemePalette.withOverrides(base, o.custom[_editing] ?? const {});
    for (final k in ThemePalette.keys) {
      _hex[k]!.text = colorToHex(raw[k]);
    }
  }

  void _setO(OccasionConfig Function(OccasionConfig) fn) =>
      widget.onChanged((cur) => cur.copyWith(occasions: fn(cur.occasions)));

  String _label(String key) => context.pick(ThemePresets.labels[key]![0], ThemePresets.labels[key]![1]);

  Widget _swatch(String key, {double size = 18}) {
    final p = o.paletteFor(key);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [Color(p.background), Color(p.primary), Color(p.primary), Color(p.background)]),
        border: Border.all(color: AppColors.hairline),
      ),
    );
  }

  Future<String?> _pickDate(String current, {String? notBefore}) async {
    final first = parseDate(notBefore) ?? DateTime.utc(_today.year - 1);
    final init = parseDate(current) ?? _today;
    final d = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime.utc(_today.year + 5, 12, 31),
      initialDate: init.isBefore(first) ? first : init,
    );
    return d == null ? null : formatDate(DateTime.utc(d.year, d.month, d.day));
  }

  void _setRange(int i, ThemeRange r) => _setO((o) {
        if (i >= o.schedule.length) return o;
        return o.copyWith(schedule: [...o.schedule]..[i] = r);
      });

  void _setHex(String key, String text) {
    final c = parseHexColor(text);
    if (c == null) return;
    final preset = _editing;
    final base = ThemePresets.palettes[preset]!;
    _setO((o) {
      final edits = {...?o.custom[preset]};
      if (c == base[key]) {
        edits.remove(key);
      } else {
        edits[key] = colorToHex(c);
      }
      final custom = {...o.custom};
      if (edits.isEmpty) {
        custom.remove(preset);
      } else {
        custom[preset] = edits;
      }
      return o.copyWith(custom: custom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final now = f.themeOn(today);
    final easter = o.easterRanges(today.year);
    String span(ThemeRange r) => '${r.start} → ${r.end}';
    final rawEdit = ThemePalette.withOverrides(ThemePresets.palettes[_editing]!, o.custom[_editing] ?? const {});
    final fixed = rawEdit.normalized();
    final adjusted = [for (final k in ThemePalette.keys) if (fixed[k] != rawEdit[k]) k];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.tr('themeSelected'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in ThemePresets.keys)
          ChoiceChip(
            key: ValueKey('theme-$k'),
            avatar: _swatch(k),
            label: Text(_label(k)),
            selected: f.theme == k,
            showCheckmark: false,
            selectedColor: AppColors.burgundy,
            labelStyle: TextStyle(color: f.theme == k ? Colors.white : AppColors.burgundy, fontWeight: FontWeight.w700),
            onSelected: (_) => widget.onChanged((cur) => cur.copyWith(theme: k)),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        key: const Key('themeInForce'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _swatch(now.theme, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${context.tr('themeInForce', {'t': _label(now.theme)})} — ${context.tr('themeSrc_${now.source.name}')}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
        ]),
      ),
      SwitchListTile(
        key: const ValueKey('occasions-auto'),
        contentPadding: const EdgeInsetsDirectional.only(start: 4),
        title: Text(context.tr('themeAuto')),
        subtitle: Text(context.tr('themeAutoHint')),
        value: o.auto,
        onChanged: (v) => _setO((o) => o.copyWith(auto: v)),
      ),
      if (o.auto) ...[
        SwitchListTile(
          key: const ValueKey('occasions-easter'),
          contentPadding: const EdgeInsetsDirectional.only(start: 4),
          title: Text(context.tr('themeEaster')),
          subtitle: Text(context.tr('themeEasterDates', {'h': span(easter[0]), 'r': span(easter[1])}),
              textDirection: TextDirection.ltr),
          value: o.easter,
          onChanged: (v) => _setO((o) => o.copyWith(easter: v)),
        ),
        if (o.easter)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<int>(
              key: const ValueKey('occasions-resurrectionDays'),
              initialValue: o.resurrectionDays,
              decoration: InputDecoration(labelText: context.tr('themeResDays')),
              items: [
                for (final d in {1, 3, 7, 14, 40, 50, o.resurrectionDays}.toList()..sort())
                  DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (d) => d == null ? null : _setO((o) => o.copyWith(resurrectionDays: d)),
            ),
          ),
        Text(context.tr('themeSchedule'), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < o.schedule.length; i++) _rangeRow(i, o.schedule[i]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('occasions-addRange'),
            onPressed: o.schedule.length >= OccasionConfig.maxRanges
                ? null
                : () => _setO((o) => o.copyWith(schedule: [
                      ...o.schedule,
                      ThemeRange(
                        theme: f.theme,
                        start: formatDate(today),
                        end: formatDate(today.add(const Duration(days: 6))),
                      ),
                    ])),
            icon: const Icon(Icons.add),
            label: Text(context.tr('themeAddRange')),
          ),
        ),
      ],
      const Divider(height: 24),
      ExpansionTile(
        key: const ValueKey('occasions-colors'),
        tilePadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
        title: Text(context.tr('themeColors'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(context.tr('themeColorsHint'), style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('occasions-editing'),
            initialValue: _editing,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('themeEditing')),
            items: [for (final k in ThemePresets.keys) DropdownMenuItem(value: k, child: Text(_label(k)))],
            onChanged: (k) {
              if (k == null) return;
              setState(() {
                _editing = k;
                _loadHex();
              });
            },
          ),
          const SizedBox(height: 10),
          for (final k in ThemePalette.keys) _hexRow(k, rawEdit, fixed),
          Container(
            key: const Key('themeContrastStatus'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: adjusted.isEmpty ? const Color(0xFFE6F2EA) : const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              adjusted.isEmpty
                  ? context.tr('themeReadable')
                  : context.tr('themeAdjusted', {
                      'k': adjusted
                          .map((k) => '${context.pick(ThemePalette.keyLabels[k]![0], ThemePalette.keyLabels[k]![1])} '
                              '${colorToHex(rawEdit[k])}→${colorToHex(fixed[k])}')
                          .join('، '),
                    }),
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          _Preview(palette: fixed),
          if ((o.custom[_editing] ?? const {}).isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('occasions-resetColors'),
                onPressed: () {
                  _setO((o) => o.copyWith(custom: {...o.custom}..remove(_editing)));
                  setState(() {
                    final base = ThemePresets.palettes[_editing]!;
                    for (final k in ThemePalette.keys) {
                      _hex[k]!.text = colorToHex(base[k]);
                    }
                  });
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(context.tr('themeResetColors')),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _rangeRow(int i, ThemeRange r) => Padding(
        key: ValueKey('occasions-range-$i'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String>(
            key: ValueKey('occasions-range-$i-theme'),
            value: r.theme,
            items: [for (final k in ThemePresets.keys) DropdownMenuItem(value: k, child: Text(_label(k)))],
            onChanged: (k) => k == null ? null : _setRange(i, ThemeRange(theme: k, start: r.start, end: r.end)),
          ),
          OutlinedButton(
            key: ValueKey('occasions-range-$i-start'),
            onPressed: () async {
              final d = await _pickDate(r.start);
              if (d == null) return;
              // The end never falls before the start.
              final end = parseDate(r.end)!.isBefore(parseDate(d)!) ? d : r.end;
              _setRange(i, ThemeRange(theme: r.theme, start: d, end: end));
            },
            child: Text('${context.tr('themeFrom')} ${r.start}', textDirection: TextDirection.ltr),
          ),
          OutlinedButton(
            key: ValueKey('occasions-range-$i-end'),
            onPressed: () async {
              final d = await _pickDate(r.end, notBefore: r.start);
              if (d != null) _setRange(i, ThemeRange(theme: r.theme, start: r.start, end: d));
            },
            child: Text('${context.tr('themeTo')} ${r.end}', textDirection: TextDirection.ltr),
          ),
          IconButton(
            key: ValueKey('occasions-range-$i-remove'),
            tooltip: context.tr('themeRemoveRange'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _setO((o) => o.copyWith(schedule: [...o.schedule]..removeAt(i))),
          ),
        ]),
      );

  Widget _hexRow(String k, ThemePalette raw, ThemePalette fixed) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(raw[k]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.hairline),
            ),
          ),
          if (fixed[k] != raw[k]) ...[
            const Icon(Icons.arrow_forward, size: 14),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: Color(fixed[k]), borderRadius: BorderRadius.circular(6)),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              key: ValueKey('occasions-hex-$k'),
              controller: _hex[k],
              textDirection: TextDirection.ltr,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) => parseHexColor(v) == null ? context.tr('themeBadHex') : null,
              decoration: InputDecoration(
                labelText: context.pick(ThemePalette.keyLabels[k]![0], ThemePalette.keyLabels[k]![1]),
                isDense: true,
              ),
              onChanged: (v) => _setHex(k, v),
            ),
          ),
        ]),
      );
}

/// A small live sample of a palette: the scene, a panel with body and
/// secondary text, the accent word, a title and the primary bar.
class _Preview extends StatelessWidget {
  final ThemePalette palette;
  const _Preview({required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      key: const Key('themePreview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Color(p.background), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('accentServices'), textAlign: TextAlign.center, style: AppFonts.script(size: 20, color: Color(p.script))),
        Text(context.tr('themePreview'),
            textAlign: TextAlign.center, style: AppFonts.heading(size: 24, color: Color(p.primary))),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Color(p.surface), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: Color(p.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(Icons.access_time_filled_rounded, size: 18, color: Color(p.onPrimaryAccent)),
                const SizedBox(width: 6),
                Text(context.tr('nextMass'), style: TextStyle(color: Color(p.onPrimary), fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('massSchedule'), style: TextStyle(color: Color(p.ink), fontWeight: FontWeight.w700)),
                Text(context.tr('denomination'), style: TextStyle(color: Color(p.goldText), fontSize: 12)),
                Text(context.tr('fullSchedule'), style: TextStyle(color: Color(p.muted), fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Admin → Settings → "Hero video library" (ADR-026): named YouTube links,
/// the active one (or the built-in clip), and an optional video per theme.
class HeroVideoEditor extends StatefulWidget {
  final FeatureSettings value;

  /// Applies an edit to the current settings (see [OccasionThemeEditor.onChanged]).
  final void Function(FeatureSettings Function(FeatureSettings) edit) onChanged;
  const HeroVideoEditor({super.key, required this.value, required this.onChanged});

  @override
  State<HeroVideoEditor> createState() => _HeroVideoEditorState();
}

class _HeroVideoEditorState extends State<HeroVideoEditor> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _nameError, _urlError;

  HeroVideoLibrary get lib => widget.value.heroVideos;

  void _setLib(HeroVideoLibrary Function(HeroVideoLibrary) fn) =>
      widget.onChanged((cur) => cur.copyWith(heroVideos: fn(cur.heroVideos)));

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _add() {
    final name = _name.text.trim();
    final id = youtubeVideoId(_url.text);
    final slot = lib.freeSlot;
    setState(() {
      _nameError = name.isEmpty
          ? context.tr('required')
          : (name.length > HeroVideo.maxName ? context.tr('tooLong') : null);
      _urlError = id == null ? context.tr('heroVideoBadUrl') : (slot == null ? context.tr('heroVideoFull') : null);
    });
    if (_nameError != null || _urlError != null || id == null || slot == null) return;
    final item = HeroVideo(id: slot, name: name, url: canonicalYoutubeUrl(id));
    // The first link becomes the active one; later ones wait to be picked.
    _setLib((lib) => lib.byId(slot) != null
        ? lib
        : lib.copyWith(
            items: [...lib.items, item]..sort((a, b) => _slotNo(a.id).compareTo(_slotNo(b.id))),
            active: lib.active.isEmpty && lib.items.isEmpty ? slot : lib.active,
          ));
    _name.clear();
    _url.clear();
  }

  static int _slotNo(String id) => int.tryParse(id.substring(1)) ?? 0;

  @override
  Widget build(BuildContext context) {
    final names = {for (final i in lib.items) i.id: i.name};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.value.heroMotion)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(context.tr('heroVideoMotionOff'), style: const TextStyle(color: AppColors.alert, fontSize: 12.5)),
        ),
      RadioGroup<String>(
        groupValue: lib.active,
        onChanged: (v) => _setLib((lib) => lib.copyWith(active: v ?? '')),
        child: Column(children: [
          RadioListTile<String>(
            key: const ValueKey('heroVideo-builtin'),
            contentPadding: EdgeInsets.zero,
            value: '',
            title: Text(context.tr('heroVideoBuiltIn')),
          ),
          for (final v in lib.items)
            RadioListTile<String>(
              key: ValueKey('heroVideo-${v.id}'),
              contentPadding: EdgeInsets.zero,
              value: v.id,
              title: Text(v.name),
              subtitle: Text(v.url, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
              secondary: IconButton(
                key: ValueKey('heroVideo-${v.id}-remove'),
                tooltip: context.tr('heroVideoRemove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _setLib((lib) => lib.remove(v.id)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('heroVideo-name'),
        controller: _name,
        maxLength: HeroVideo.maxName,
        decoration: InputDecoration(labelText: context.tr('heroVideoName'), errorText: _nameError),
      ),
      TextField(
        key: const ValueKey('heroVideo-url'),
        controller: _url,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: context.tr('heroVideoUrl'),
          hintText: 'https://youtu.be/…',
          errorText: _urlError,
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _add(),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.icon(
          key: const ValueKey('heroVideo-add'),
          onPressed: lib.freeSlot == null ? null : _add,
          icon: const Icon(Icons.add_link),
          label: Text(context.tr('heroVideoAdd')),
        ),
      ),
      if (lib.items.isNotEmpty)
        ExpansionTile(
          key: const ValueKey('heroVideo-perTheme'),
          tilePadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          title: Text(context.tr('heroVideoPerTheme'), style: const TextStyle(fontWeight: FontWeight.w700)),
          children: [
            for (final k in ThemePresets.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('heroVideo-theme-$k'),
                  isExpanded: true,
                  initialValue: names.containsKey(lib.byTheme[k]) ? lib.byTheme[k] : '',
                  decoration: InputDecoration(
                    labelText: context.pick(ThemePresets.labels[k]![0], ThemePresets.labels[k]![1]),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(context.tr('heroVideoUseActive'))),
                    for (final v in lib.items)
                      DropdownMenuItem(value: v.id, child: Text(v.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => _setLib((lib) {
                    final by = {...lib.byTheme};
                    if (v == null || v.isEmpty) {
                      by.remove(k);
                    } else {
                      by[k] = v;
                    }
                    return lib.copyWith(byTheme: by);
                  }),
                ),
              ),
          ],
        ),
    ]);
  }
}
