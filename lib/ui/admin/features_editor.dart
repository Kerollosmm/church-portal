import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/features.dart';
import 'admin_validators.dart';

/// Section on/off switches + home layout (settings/features).
class FeaturesScreen extends StatefulWidget {
  final AdminBackend repo;
  const FeaturesScreen({super.key, required this.repo});

  @override
  State<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends State<FeaturesScreen> {
  late final Stream<AdminDoc?> _stream = widget.repo.watchDoc('settings/features');
  /// A fresh key per shown version rebuilds the editor from that version.
  GlobalKey<FeaturesEditorState> _editorKey = GlobalKey<FeaturesEditorState>();

  /// The stored version the editor shows; a newer one replaces it only when
  /// there are no unsaved local edits (otherwise a banner offers a reload).
  AdminDoc? _shown;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final latest = snap.data;
        final changed = !_loaded || latest?.updatedAt != _shown?.updatedAt || (latest == null) != (_shown == null);
        final dirty = _editorKey.currentState?.dirty ?? false;
        if (changed && !dirty) {
          if (_loaded) _editorKey = GlobalKey<FeaturesEditorState>();
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
                    _editorKey = GlobalKey<FeaturesEditorState>();
                  }),
                  child: Text(context.tr('reload')),
                ),
              ],
            ),
          Expanded(
            child: FeaturesEditor(
              key: _editorKey,
              initial: FeatureSettings.fromMap(doc?.data),
              exists: doc != null,
              updatedAt: doc?.updatedAt,
              updatedBy: doc?.updatedBy ?? '',
              onSave: (f) => widget.repo.saveDoc('settings/features', f.toMap()),
            ),
          ),
        ]);
      },
    );
  }
}

class FeaturesEditor extends StatefulWidget {
  final FeatureSettings initial;
  final bool exists;
  final DateTime? updatedAt;
  final String updatedBy;
  final Future<void> Function(FeatureSettings) onSave;
  const FeaturesEditor({
    super.key,
    required this.initial,
    required this.onSave,
    this.exists = true,
    this.updatedAt,
    this.updatedBy = '',
  });

  @override
  State<FeaturesEditor> createState() => FeaturesEditorState();
}

class FeaturesEditorState extends State<FeaturesEditor> {
  late FeatureSettings f = widget.initial;
  late final Map<String, TextEditingController> _t = {
    'heroTitleAr': TextEditingController(text: f.heroTitleAr),
    'heroTitleEn': TextEditingController(text: f.heroTitleEn),
    'heroSubtitleAr': TextEditingController(text: f.heroSubtitleAr),
    'heroSubtitleEn': TextEditingController(text: f.heroSubtitleEn),
    'bannerAr': TextEditingController(text: f.bannerAr),
    'bannerEn': TextEditingController(text: f.bannerEn),
    'bannerLink': TextEditingController(text: f.bannerLink),
  };
  final _formKey = GlobalKey<FormState>();
  bool _dirty = false;
  bool _saving = false;

  /// Unsaved local edits (a save in flight counts as saved).
  bool get dirty => _dirty && !_saving;

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(FeatureSettings next) => setState(() {
        f = next;
        _dirty = true;
      });

  FeatureSettings collect() => f.copyWith(
        heroTitleAr: _t['heroTitleAr']!.text.trim(),
        heroTitleEn: _t['heroTitleEn']!.text.trim(),
        heroSubtitleAr: _t['heroSubtitleAr']!.text.trim(),
        heroSubtitleEn: _t['heroSubtitleEn']!.text.trim(),
        bannerAr: _t['bannerAr']!.text.trim(),
        bannerEn: _t['bannerEn']!.text.trim(),
        bannerLink: _t['bannerLink']!.text.trim(),
      );

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = context.tr('saved');
    final failed = context.tr('saveFailed', {'e': '{e}'});
    setState(() => _saving = true);
    try {
      await widget.onSave(collect());
      messenger.showSnackBar(SnackBar(content: Text(ok)));
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed.replaceAll('{e}', '$e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(String title, IconData icon, List<Widget> children, {String? hint}) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: AppColors.burgundy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.burgundy)),
              ),
            ]),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _text(String key, String label, {int maxLength = 300, bool url = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: ValueKey('features-$key'),
          controller: _t[key],
          onChanged: (_) => _dirty ? null : setState(() => _dirty = true),
          textDirection: url ? TextDirection.ltr : null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.length > maxLength) return context.tr('tooLong');
            if (url && s.isNotEmpty && !isValidUrl(s, allowPath: true)) return context.tr('invalidUrl');
            return null;
          },
          decoration: InputDecoration(labelText: label, hintText: url ? '/mass-schedule  /  https://…' : null),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final order = f.homeOrder;
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('features-save'),
        heroTag: 'features-save',
        backgroundColor: _dirty ? AppColors.burgundy : AppColors.muted,
        foregroundColor: Colors.white,
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(context.tr(_dirty ? 'saveChanges' : 'save')),
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
              if (!widget.exists)
                Card(
                  color: AppColors.parchment,
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: AppColors.burgundy),
                    title: Text(context.tr('featuresDefaultsNote')),
                  ),
                ),
              if (widget.updatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    context.tr('updatedBy', {'t': fmtDateTime(widget.updatedAt!), 'u': widget.updatedBy}),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              _card(context.tr('sectionsTitle'), Icons.toggle_on_outlined, [
                Wrap(spacing: 8, children: [
                  TextButton(
                    onPressed: () => _set(f.copyWith(sections: {for (final s in Sections.all) s: true})),
                    child: Text(context.tr('enableAll')),
                  ),
                ]),
                for (final s in Sections.all)
                  SwitchListTile(
                    key: ValueKey('section-$s'),
                    contentPadding: const EdgeInsetsDirectional.only(start: 4),
                    title: Text(context.pick(Sections.labels[s]![0], Sections.labels[s]![1])),
                    value: f.enabled(s),
                    onChanged: (v) => _set(f.copyWith(sections: {...f.sections, s: v})),
                  ),
              ], hint: context.tr('sectionsHint')),
              _card(context.tr('homeLayout'), Icons.dashboard_customize_outlined, [
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) {
                    final next = [...order];
                    next.insert(to, next.removeAt(from));
                    _set(f.copyWith(homeOrder: normalizeHomeOrder(next)));
                  },
                  children: [
                    for (var i = 0; i < order.length; i++)
                      _homeBlockTile(context, order[i], i),
                  ],
                ),
              ], hint: context.tr('homeLayoutHint')),
              _card(context.tr('heroTexts'), Icons.title_rounded, [
                _text('heroTitleAr', context.tr('heroTitleAr'), maxLength: 200),
                _text('heroTitleEn', context.tr('heroTitleEn'), maxLength: 200),
                _text('heroSubtitleAr', context.tr('heroSubtitleAr'), maxLength: 300),
                _text('heroSubtitleEn', context.tr('heroSubtitleEn'), maxLength: 300),
              ], hint: context.tr('heroTextsHint')),
              _card(context.tr('announcementBanner'), Icons.campaign_outlined, [
                SwitchListTile(
                  key: const ValueKey('features-bannerEnabled'),
                  contentPadding: const EdgeInsetsDirectional.only(start: 4),
                  title: Text(context.tr('showBanner')),
                  value: f.bannerEnabled,
                  onChanged: (v) => _set(f.copyWith(bannerEnabled: v)),
                ),
                _text('bannerAr', context.tr('bannerAr'), maxLength: 500),
                _text('bannerEn', context.tr('bannerEn'), maxLength: 500),
                _text('bannerLink', context.tr('bannerLink'), maxLength: 500, url: true),
              ]),
              _card(context.tr('themeColor'), Icons.palette_outlined, [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final e in ThemePresets.all.entries)
                    ChoiceChip(
                      key: ValueKey('theme-${e.key}'),
                      avatar: CircleAvatar(backgroundColor: Color(e.value), radius: 9),
                      label: Text(context.pick(ThemePresets.labels[e.key]![0], ThemePresets.labels[e.key]![1])),
                      selected: f.theme == e.key,
                      showCheckmark: false,
                      onSelected: (_) => _set(f.copyWith(theme: e.key)),
                    ),
                ]),
              ], hint: context.tr('themeHint')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _homeBlockTile(BuildContext context, String b, int i) {
    final shown = !f.homeHidden.contains(b);
    final req = HomeBlocks.requires[b];
    final sectionOff = req != null && !f.enabled(req);
    return ListTile(
      key: ValueKey('home-$b'),
      contentPadding: EdgeInsets.zero,
      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
      title: Text(context.pick(HomeBlocks.labels[b]![0], HomeBlocks.labels[b]![1])),
      subtitle: sectionOff
          ? Text(context.tr('blockSectionOff'), style: const TextStyle(color: AppColors.alert, fontSize: 12))
          : null,
      trailing: Switch(
        value: shown,
        onChanged: (v) => _set(f.copyWith(homeHidden: v ? ({...f.homeHidden}..remove(b)) : {...f.homeHidden, b})),
      ),
    );
  }
}
