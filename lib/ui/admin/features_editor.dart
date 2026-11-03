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
  late Stream<AdminDoc?> _stream = widget.repo.watchDoc('settings/features');

  @override
  void didUpdateWidget(covariant FeaturesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different backend: re-bind the stream and rebuild the form from it.
    if (widget.repo != oldWidget.repo) {
      _stream = widget.repo.watchDoc('settings/features');
      _shown = null;
      _loaded = false;
      _editorKey = GlobalKey<FeaturesEditorState>();
    }
  }

  /// A fresh key per shown version rebuilds the editor from that version.
  GlobalKey<FeaturesEditorState> _editorKey = GlobalKey<FeaturesEditorState>();

  /// The stored version the editor shows; a newer one replaces it only when
  /// there are no unsaved local edits (otherwise a banner offers a reload).
  AdminDoc? _shown;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminDoc?>(
      // A new stream (another backend) gets a fresh StreamBuilder: a reused one
      // keeps the old backend's last snapshot while waiting, and that stale
      // document would then be marked as loaded.
      key: ObjectKey(_stream),
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final latest = snap.data;
        final changed = !_loaded || latest?.updatedAt != _shown?.updatedAt || (latest == null) != (_shown == null);
        final editor = _editorKey.currentState;
        final dirty = editor?.dirty ?? false;
        if (changed && !dirty) {
          // The snapshot of our own save keeps the form and its scroll position.
          final echo =
              _loaded && editor != null && isEchoOfEditor(_shown?.data ?? const {}, latest?.data, editor.collect().toMap());
          if (_loaded && !echo) _editorKey = GlobalKey<FeaturesEditorState>();
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
              onSave: (f) async {
                for (final w in featuresSaveWrites(f, doc?.data)) {
                  await widget.repo.saveDoc('settings/features', w);
                }
              },
            ),
          ),
        ]);
      },
    );
  }
}

/// The writes that save [next] over the [stored] settings/features document:
/// everything else first, then `pageHeaders` on its own when it changed.
/// Firestore evaluates at most 1,000 rule expressions per request and every
/// page header that changes is validated (validPageHeaders): the whole
/// document plus all 8 pages in one write exceeds it (ADR-020).
List<Map<String, dynamic>> featuresSaveWrites(FeatureSettings next, Map<String, dynamic>? stored) {
  final base = next.toMap();
  final headers = base.remove('pageHeaders');
  // heroMotion (ADR-022) is written only once it differs from the default or
  // is already stored, so saves keep working against rules that predate it.
  if (next.heroMotion && (stored == null || !stored.containsKey('heroMotion'))) base.remove('heroMotion');
  final before = FeatureSettings.fromMap(stored).toMap()['pageHeaders'];
  return [
    base,
    if (stored == null || !stored.containsKey('pageHeaders') || !sameValue(headers, before)) {'pageHeaders': headers},
  ];
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
    'footerNoteAr': TextEditingController(text: f.footer.noteAr),
    'footerNoteEn': TextEditingController(text: f.footer.noteEn),
  };

  /// Page header / intro inputs: page key -> field -> controller.
  late final Map<String, Map<String, TextEditingController>> _pages = {
    for (final p in CustomizablePages.all)
      p: {
        for (final e in f.pageHeader(p).toMap().entries) e.key: TextEditingController(text: e.value as String),
      },
  };

  /// Max lengths of the page header fields (validPageHeader in firestore.rules).
  static const pageFieldMax = {
    'titleAr': 200, 'titleEn': 200, 'subtitleAr': 300, 'subtitleEn': 300, 'introAr': 1500, 'introEn': 1500, //
  };

  /// Footer note length (validFooter in firestore.rules).
  static const footerNoteMax = 500;

  /// One collapsible row per page (opened when it holds an invalid field).
  final Map<String, ExpansibleController> _pageCtl = {
    for (final p in CustomizablePages.all) p: ExpansibleController(),
  };
  final _formKey = GlobalKey<FormState>();
  bool _dirty = false;
  bool _saving = false;

  /// Unsaved local edits (a save in flight counts as saved).
  bool get dirty => _dirty && !_saving;

  @override
  void dispose() {
    for (final c in [..._t.values, for (final m in _pages.values) ...m.values, ..._pageCtl.values]) {
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
        pageHeaders: {
          for (final p in CustomizablePages.all)
            if (_pageCustom(p) case final PageCustom c when !c.isEmpty) p: c,
        },
        footer: FooterConfig(
          showPhones: f.footer.showPhones,
          showSocials: f.footer.showSocials,
          showQuickLinks: f.footer.showQuickLinks,
          noteAr: _t['footerNoteAr']!.text.trim(),
          noteEn: _t['footerNoteEn']!.text.trim(),
        ),
      );

  PageCustom _pageCustom(String p) {
    String v(String k) => _pages[p]![k]!.text.trim();
    return PageCustom(
      titleAr: v('titleAr'),
      titleEn: v('titleEn'),
      subtitleAr: v('subtitleAr'),
      subtitleEn: v('subtitleEn'),
      introAr: v('introAr'),
      introEn: v('introEn'),
    );
  }

  /// Opens every collapsed page row holding a too-long field.
  void _openInvalidPages() {
    for (final p in CustomizablePages.all) {
      final bad = _pages[p]!.entries.any((e) => e.value.text.trim().length > pageFieldMax[e.key]!);
      if (bad && !_pageCtl[p]!.isExpanded) _pageCtl[p]!.expand();
    }
  }

  void _setFooter({bool? showPhones, bool? showSocials, bool? showQuickLinks}) => _set(f.copyWith(
        footer: FooterConfig(
          showPhones: showPhones ?? f.footer.showPhones,
          showSocials: showSocials ?? f.footer.showSocials,
          showQuickLinks: showQuickLinks ?? f.footer.showQuickLinks,
          noteAr: f.footer.noteAr,
          noteEn: f.footer.noteEn,
        ),
      ));

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      _openInvalidPages();
      return;
    }
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

  Widget _text(String key, String label,
          {int maxLength = 300, bool url = false, TextEditingController? controller, Key? fieldKey, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: fieldKey ?? ValueKey('features-$key'),
          controller: controller ?? _t[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
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
                  onReorderItem: (from, to) => _moveBlock(order, from, to),
                  children: [
                    for (var i = 0; i < order.length; i++)
                      _homeBlockTile(context, order[i], i, order.length),
                  ],
                ),
              ], hint: context.tr('homeLayoutHint')),
              _card(context.tr('heroTexts'), Icons.title_rounded, [
                _text('heroTitleAr', context.tr('heroTitleAr'), maxLength: 200),
                _text('heroTitleEn', context.tr('heroTitleEn'), maxLength: 200),
                _text('heroSubtitleAr', context.tr('heroSubtitleAr'), maxLength: 300),
                _text('heroSubtitleEn', context.tr('heroSubtitleEn'), maxLength: 300),
                SwitchListTile(
                  key: const ValueKey('features-heroMotion'),
                  contentPadding: const EdgeInsetsDirectional.only(start: 4),
                  title: Text(context.tr('heroMotion')),
                  subtitle: Text(context.tr('heroMotionHint')),
                  value: f.heroMotion,
                  onChanged: (v) => _set(f.copyWith(heroMotion: v)),
                ),
              ], hint: context.tr('heroTextsHint')),
              _card(context.tr('pageHeadersTitle'), Icons.view_headline_rounded, [
                for (final p in CustomizablePages.all) _pageTile(context, p),
              ], hint: context.tr('pageHeadersHint')),
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
              _card(context.tr('footerTitle'), Icons.call_to_action_outlined, [
                for (final (k, label, v, set) in [
                  ('showPhones', 'footerShowPhones', f.footer.showPhones, (bool v) => _setFooter(showPhones: v)),
                  ('showSocials', 'footerShowSocials', f.footer.showSocials, (bool v) => _setFooter(showSocials: v)),
                  ('showQuickLinks', 'footerShowQuickLinks', f.footer.showQuickLinks,
                      (bool v) => _setFooter(showQuickLinks: v)),
                ])
                  SwitchListTile(
                    key: ValueKey('footer-$k'),
                    contentPadding: const EdgeInsetsDirectional.only(start: 4),
                    title: Text(context.tr(label)),
                    value: v,
                    onChanged: set,
                  ),
                _text('footerNoteAr', context.tr('footerNoteAr'),
                    maxLength: footerNoteMax, fieldKey: const ValueKey('footer-noteAr'), lines: 2),
                _text('footerNoteEn', context.tr('footerNoteEn'),
                    maxLength: footerNoteMax, fieldKey: const ValueKey('footer-noteEn'), lines: 2),
              ], hint: context.tr('footerHint')),
              _card(context.tr('themeColor'), Icons.palette_outlined, [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final e in ThemePresets.all.entries)
                    ChoiceChip(
                      key: ValueKey('theme-${e.key}'),
                      avatar: CircleAvatar(backgroundColor: Color(e.value), radius: 9),
                      label: Text(context.pick(ThemePresets.labels[e.key]![0], ThemePresets.labels[e.key]![1])),
                      selected: f.theme == e.key,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: f.theme == e.key ? Colors.white : AppColors.burgundy,
                        fontWeight: FontWeight.w700,
                      ),
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

  /// One page's header / intro overrides: a collapsible row with a
  /// "Customized" badge and a Reset button while any field is filled.
  Widget _pageTile(BuildContext context, String p) {
    final ctrls = _pages[p]!;
    final labels = CustomizablePages.labels[p]!;
    return ListenableBuilder(
      listenable: Listenable.merge(ctrls.values.toList()),
      builder: (context, _) {
        final customized = ctrls.values.any((c) => c.text.trim().isNotEmpty);
        return ExpansionTile(
          key: ValueKey('page-$p'),
          controller: _pageCtl[p],
          maintainState: true,
          tilePadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          childrenPadding: const EdgeInsetsDirectional.only(start: 4, end: 4, bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(context.pick(labels[0], labels[1]), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: customized
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    key: ValueKey('pageCustomized-$p'),
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.parchment,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.burgundy.withValues(alpha: 0.35)),
                    ),
                    child: Text(context.tr('pageCustomized'),
                        style: const TextStyle(fontSize: 12, color: AppColors.burgundy, fontWeight: FontWeight.w700)),
                  ),
                )
              : null,
          children: [
            for (final e in ctrls.entries)
              _text('page-$p-${e.key}', context.tr('page_${e.key}'),
                  maxLength: pageFieldMax[e.key]!,
                  controller: e.value,
                  lines: e.key.startsWith('intro') ? 3 : 1),
            if (customized)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: ValueKey('pageReset-$p'),
                  onPressed: () => setState(() {
                    for (final c in ctrls.values) {
                      c.clear();
                    }
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(context.tr('pageReset')),
                ),
              ),
          ],
        );
      },
    );
  }

  /// [to] is the index after removing [from] (onReorderItem semantics).
  void _moveBlock(List<String> order, int from, int to) {
    final next = [...order];
    next.insert(to, next.removeAt(from));
    _set(f.copyWith(homeOrder: normalizeHomeOrder(next)));
  }

  Widget _homeBlockTile(BuildContext context, String b, int i, int count) {
    final shown = !f.homeHidden.contains(b);
    final req = HomeBlocks.requires[b];
    final sectionOff = req != null && !f.enabled(req);
    // Single-tap alternative to dragging (WCAG 2.5.7).
    final moveButtons = [
      IconButton(
        key: ValueKey('home-$b-up'),
        tooltip: context.tr('moveUp'),
        icon: const Icon(Icons.arrow_upward),
        onPressed: i == 0 ? null : () => _moveBlock(f.homeOrder, i, i - 1),
      ),
      IconButton(
        key: ValueKey('home-$b-down'),
        tooltip: context.tr('moveDown'),
        icon: const Icon(Icons.arrow_downward),
        onPressed: i == count - 1 ? null : () => _moveBlock(f.homeOrder, i, i + 1),
      ),
    ];
    final offNote = sectionOff
        ? Text(context.tr('blockSectionOff'), style: const TextStyle(color: AppColors.alert, fontSize: 12))
        : null;
    final toggle = Switch(
      value: shown,
      onChanged: (v) => _set(f.copyWith(homeHidden: v ? ({...f.homeHidden}..remove(b)) : {...f.homeHidden, b})),
    );
    // Narrow screens: the move buttons get their own row under the title so
    // the title keeps its width (and nothing overflows at 200% text).
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return ListTile(
      key: ValueKey('home-$b'),
      contentPadding: EdgeInsets.zero,
      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
      title: Text(context.pick(HomeBlocks.labels[b]![0], HomeBlocks.labels[b]![1])),
      subtitle: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              ?offNote,
              Row(mainAxisSize: MainAxisSize.min, children: moveButtons),
            ])
          : offNote,
      trailing: narrow ? toggle : Row(mainAxisSize: MainAxisSize.min, children: [...moveButtons, toggle]),
    );
  }
}
