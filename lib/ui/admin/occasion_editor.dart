import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
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

  /// Keys of the church seasons active now (ADR-043), for "in force today".
  final List<String> activeSeasonKeys;
  const OccasionThemeEditor(
      {super.key, required this.value, required this.onChanged, this.today, this.activeSeasonKeys = const []});

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
        border: Border.all(color: context.pal.hairline),
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
    final now = f.themeOn(today, activeSeasonKeys: widget.activeSeasonKeys);
    final easter = o.easterRanges(today.year);
    String span(ThemeRange r) => '${r.start} → ${r.end}';
    final rawEdit = ThemePalette.withOverrides(ThemePresets.palettes[_editing]!, o.custom[_editing] ?? const {});
    final fixed = rawEdit.normalized();
    final adjusted = [for (final k in ThemePalette.keys) if (fixed[k] != rawEdit[k]) k];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.tr('themeSelected'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        // The legacy `purple` key only while a document still holds it (ADR-043).
        for (final k in [...ThemePresets.pickable, if (f.theme == ThemePresets.legacyPurple) ThemePresets.legacyPurple])
          ChoiceChip(
            key: ValueKey('theme-$k'),
            avatar: _swatch(k),
            label: Text(_label(k)),
            selected: f.theme == k,
            showCheckmark: false,
            selectedColor: context.pal.bar,
            labelStyle: TextStyle(color: f.theme == k ? context.pal.onBar : context.pal.primary, fontWeight: FontWeight.w700),
            onSelected: (_) => widget.onChanged((cur) => cur.copyWith(theme: k)),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        key: const Key('themeInForce'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _swatch(now.theme, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${context.tr('themeInForce', {'t': _label(now.theme)})} — ${context.tr('themeSrc_${now.source.name}')}',
              style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.ink),
            ),
          ),
        ]),
      ),
      SwitchListTile(
        key: const ValueKey('occasions-followSeason'),
        contentPadding: const EdgeInsetsDirectional.only(start: 4),
        title: Text(context.tr('themeFollowSeason')),
        subtitle: Text(context.tr('themeFollowSeasonHint')),
        value: o.followSeason,
        onChanged: (v) => _setO((o) => o.copyWith(followSeason: v)),
      ),
      if (o.followSeason)
        ExpansionTile(
          key: const ValueKey('occasions-seasonMap'),
          tilePadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          title: Text(context.tr('themeSeasonMap'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.tr('themeSeasonMapHint'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final k in SeasonThemes.seasonKeys) _seasonRow(k)],
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
        subtitle: Text(context.tr('themeColorsHint'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
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
              color: adjusted.isEmpty ? context.pal.success.withValues(alpha: 0.1) : context.pal.notice,
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
              style: TextStyle(color: context.pal.ink, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          _Preview(palette: fixed, themeKey: _editing),
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

  /// One season key → its theme (or none). Only differences from
  /// [SeasonThemes.defaults] are stored.
  Widget _seasonRow(String key) {
    final current = o.themeForSeason(key) ?? SeasonThemes.none;
    return Padding(
      key: ValueKey('occasions-season-$key'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(context.tr('opt_$key'))),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButton<String>(
            key: ValueKey('occasions-season-$key-theme'),
            value: current,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: SeasonThemes.none, child: Text(context.tr('themeSeasonNone'))),
              for (final t in ThemePresets.pickable) DropdownMenuItem(value: t, child: Text(_label(t))),
              if (current == ThemePresets.legacyPurple)
                DropdownMenuItem(value: ThemePresets.legacyPurple, child: Text(_label(ThemePresets.legacyPurple))),
            ],
            onChanged: (t) {
              if (t == null) return;
              _setO((o) {
                final m = {...o.seasonThemes};
                if (t == SeasonThemes.defaults[key]) {
                  m.remove(key);
                } else {
                  m[key] = t;
                }
                return o.copyWith(seasonThemes: m);
              });
            },
          ),
        ),
      ]),
    );
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
              border: Border.all(color: context.pal.hairline),
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
/// secondary text, the accent word, a title and the title band with its
/// scene accents (ADR-043: the same band colours and edge as the site).
class _Preview extends StatelessWidget {
  final ThemePalette palette;
  final String themeKey;
  const _Preview({required this.palette, required this.themeKey});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final a = SceneAccents.of(themeKey, p);
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
          decoration: BoxDecoration(
            color: Color(p.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(a.ornament).withValues(alpha: 0.38)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              key: const Key('themePreviewBand'),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(a.bar), Color(a.barDeep)]),
                border: a.barEdge == null ? null : Border(bottom: BorderSide(color: Color(a.barEdge!), width: 2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(Icons.access_time_filled_rounded, size: 18, color: Color(a.onBarAccent)),
                const SizedBox(width: 6),
                Text(context.tr('nextMass'), style: TextStyle(color: Color(a.onBar), fontWeight: FontWeight.w700)),
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
