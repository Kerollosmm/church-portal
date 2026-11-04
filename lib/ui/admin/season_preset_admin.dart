import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/season_preset.dart';
import '../../domain/time_format.dart';
import 'doc_editor.dart' show choiceLabel;

/// /admin → «تجهيز الموسم» / "Season preparation" (ADR-042): the owner's
/// pre-season checklist as one explicit, confirmed action, and its
/// «استرجاع الإعدادات السابقة» undo. Reads the two streams the dashboard
/// already uses (`seasons`, `settings/features`); each apply / restore is
/// ONE batched write of at most two documents (`settings/features` and the
/// season).
class SeasonPresetScreen extends StatefulWidget {
  final AdminBackend repo;

  /// The clock (tests pin it).
  final DateTime Function()? now;
  const SeasonPresetScreen({super.key, required this.repo, this.now});

  @override
  State<SeasonPresetScreen> createState() => _SeasonPresetScreenState();
}

class _SeasonPresetScreenState extends State<SeasonPresetScreen> {
  late Stream<List<AdminDoc>> _seasons = widget.repo.watch('seasons');
  late Stream<AdminDoc?> _features = widget.repo.watchDoc('settings/features');

  String? _seasonId;
  Set<String> _options = {};
  final _liveUrl = TextEditingController();
  final _pdfUrl = TextEditingController();
  final _pdfLabelAr = TextEditingController();
  final _pdfLabelEn = TextEditingController();
  bool _saving = false;
  String? _problem;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void didUpdateWidget(covariant SeasonPresetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo) {
      _seasons = widget.repo.watch('seasons');
      _features = widget.repo.watchDoc('settings/features');
    }
  }

  @override
  void dispose() {
    for (final c in [_liveUrl, _pdfUrl, _pdfLabelAr, _pdfLabelEn]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Seasons not over yet first (by start), then the past ones.
  List<Season> _sorted(List<AdminDoc> docs, DateTime now) {
    final all = [for (final d in docs) Season.fromMap(d.id, d.data)];
    bool over(Season s) => s.endsAt != null && !now.isBefore(s.endsAt!);
    int byStart(Season a, Season b) =>
        (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999));
    return [
      ...all.where((s) => !over(s)).toList()..sort(byStart),
      ...all.where(over).toList()..sort((a, b) => byStart(b, a)),
    ];
  }

  void _pick(Season s) => setState(() {
        _seasonId = s.id;
        _options = {...PresetRequest.defaultsFor(s.key)};
        _pdfUrl.text = s.program.attachmentUrl;
        _pdfLabelAr.text = s.program.attachmentLabelAr;
        _pdfLabelEn.text = s.program.attachmentLabelEn;
        _liveUrl.text = ''; // never carry one season's link to another (CodeRabbit review)
        _problem = null;
      });

  String _seasonName(BuildContext context, Season s) =>
      context.pick(s.nameAr, s.nameEn.isEmpty ? s.nameAr : s.nameEn);

  String _date(BuildContext context, DateTime? d) =>
      d == null ? '—' : formatDate(CairoTime.calendarDate(d), arabic: context.isAr);

  Future<bool> _confirm(BuildContext context, String title, List<String> lines, String action, {Key? key}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: key,
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $l'))],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            key: const Key('presetConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Writes what [plan] makes of the current `settings/features` and season
  /// documents, read in the same transaction (CodeRabbit review on PR #33).
  Future<void> _write(String seasonId, PresetWrites Function(Map<String, dynamic>? features, Map<String, dynamic>? season) plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('saved');
    final conflict = context.tr('presetConflict');
    String failed(Object e) => context.tr('saveFailed', {'e': '$e'});
    setState(() => _saving = true);
    try {
      final seasonPath = 'seasons/$seasonId';
      await widget.repo.saveDocsFresh(['settings/features', seasonPath], (cur) {
        final w = plan(cur['settings/features'], cur[seasonPath]);
        return {
          'settings/features': w.features,
          // Never create a deleted season (its rules need a key and a name).
          if (w.season.isNotEmpty && cur[seasonPath] != null) seasonPath: w.season,
        };
      });
      if (mounted) {
        setState(() => _seasonId = null);
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } on PresetConflict {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(conflict)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failed(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _apply(BuildContext context, Season season, Map<String, dynamic>? raw) async {
    final r = PresetRequest(
      options: _options,
      liveUrl: _liveUrl.text,
      attachmentUrl: _pdfUrl.text,
      attachmentLabelAr: _pdfLabelAr.text,
      attachmentLabelEn: _pdfLabelEn.text,
    );
    final problem = presetProblem(r, season);
    setState(() => _problem = problem);
    if (problem != null) return;
    final lines = [
      context.tr('presetLineActivate', {'s': _seasonName(context, season)}),
      for (final o in PresetOption.all)
        if (_options.contains(o)) context.tr('presetOpt_$o'),
      context.tr('presetAutoRevert', {'d': _date(context, season.endsAt)}),
    ];
    final ok = await _confirm(context, context.tr('presetApplyConfirmTitle'), lines, context.tr('presetApply'),
        key: const Key('presetApplyDialog'));
    if (!ok || !mounted) return;
    final now = _now();
    await _write(season.id, (stored, seasonDoc) {
      // Another admin applied a preset meanwhile, or deleted the season: write nothing.
      if (SeasonPreset.fromMap(stored?['seasonPreset']) != null || seasonDoc == null) throw const PresetConflict();
      final f = FeatureSettings.fromMap(stored);
      return planApply(
        r: r,
        season: Season.fromMap(season.id, seasonDoc),
        sections: {for (final k in Sections.all) k: f.enabled(k)},
        sectionKeys: Sections.all,
        heroMotion: f.heroMotion,
        weddingBookingOff: f.weddingBookingOff,
        liveUrl: f.today.liveUrl,
        liveEndsAt: f.today.liveEndsAt,
        now: now,
      );
    });
  }

  Future<void> _restore(BuildContext context, SeasonPreset p) async {
    final ok = await _confirm(
        context,
        context.tr('presetRestoreConfirmTitle'),
        [
          for (final o in PresetOption.all)
            if (p.has(o)) context.tr('presetUndo_$o'),
          if (p.prevBool(PresetPrev.seasonActive) == false) context.tr('presetUndoActive'),
        ],
        context.tr('presetRestore'),
        key: const Key('presetRestoreDialog'));
    if (!ok || !mounted) return;
    await _write(p.seasonId, (stored, _) {
      // Restored (or replaced) by another admin meanwhile: write nothing.
      final fresh = SeasonPreset.fromMap(stored?['seasonPreset']);
      if (fresh == null || fresh.seasonId != p.seasonId || fresh.appliedAt != p.appliedAt) throw const PresetConflict();
      final f = FeatureSettings.fromMap(stored);
      return planRestore(fresh, sections: {for (final k in Sections.all) k: f.enabled(k)}, sectionKeys: Sections.all);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminDoc>>(
      key: ObjectKey(_seasons),
      stream: _seasons,
      builder: (context, seasonsSnap) => StreamBuilder<AdminDoc?>(
        key: ObjectKey(_features),
        stream: _features,
        builder: (context, featuresSnap) {
          if (seasonsSnap.hasError || featuresSnap.hasError) {
            return Center(child: Text(context.tr('presetLoadFailed', {'e': '${seasonsSnap.error ?? featuresSnap.error}'})));
          }
          if (!seasonsSnap.hasData || featuresSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = _now();
          final raw = featuresSnap.data?.data;
          final seasons = _sorted(seasonsSnap.data!, now);
          final preset = SeasonPreset.fromMap(raw?['seasonPreset']);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(context.tr('presetIntro'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              if (preset != null)
                _appliedCard(context, preset, seasons, raw, now)
              else
                _applyCard(context, seasons, raw),
            ],
          );
        },
      ),
    );
  }

  Widget _appliedCard(
      BuildContext context, SeasonPreset p, List<Season> seasons, Map<String, dynamic>? raw, DateTime now) {
    final season = seasons.where((s) => s.id == p.seasonId).firstOrNull;
    final name = season != null ? _seasonName(context, season) : choiceLabel(context, p.seasonKey);
    final expired = p.expiredAt(now);
    return Card(
      key: const Key('presetApplied'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.tr('presetAppliedTitle', {'s': name}),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(context.tr('presetAppliedOn', {'a': _date(context, p.appliedAt), 'e': _date(context, p.endsAt)})),
          const SizedBox(height: 8),
          for (final o in PresetOption.all)
            if (p.has(o)) Text('• ${context.tr('presetOpt_$o')}'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (expired ? AppColors.success : AppColors.gold).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              context.tr(expired ? 'presetExpiredNote' : 'presetActiveNote'),
              key: Key(expired ? 'presetExpired' : 'presetActive'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('presetRestore'),
            icon: const Icon(Icons.restore_rounded),
            label: Text(context.tr('presetRestore')),
            onPressed: _saving ? null : () => _restore(context, p),
          ),
        ]),
      ),
    );
  }

  Widget _applyCard(BuildContext context, List<Season> seasons, Map<String, dynamic>? raw) {
    if (seasons.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(context.tr('presetNoSeasons'))));
    }
    final season = seasons.where((s) => s.id == _seasonId).firstOrNull;
    final ended = season?.endsAt != null && !_now().isBefore(season!.endsAt!);
    final err = _problem;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            key: const Key('presetSeason'),
            initialValue: season?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('presetSeason')),
            items: [
              for (final s in seasons)
                DropdownMenuItem(
                  value: s.id,
                  child: Text('${_seasonName(context, s)} (${_date(context, s.startsAt)} – ${_date(context, s.endsAt)})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _saving ? null : (id) => _pick(seasons.firstWhere((s) => s.id == id)),
          ),
          if (season != null) ...[
            const SizedBox(height: 8),
            if (season.endsAt == null)
              Text(context.tr('presetNoEnd'), style: const TextStyle(color: AppColors.alert, fontSize: 12)),
            if (ended)
              Text(context.tr('presetEnded'),
                  key: const Key('presetEnded'), style: const TextStyle(color: AppColors.alert, fontSize: 12)),
            for (final o in PresetOption.all) ...[
              CheckboxListTile(
                key: Key('presetOpt-$o'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _options.contains(o),
                title: Text(context.tr('presetOpt_$o')),
                subtitle: Text(context.tr('presetHint_$o'), style: const TextStyle(fontSize: 12)),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => v == true ? _options.add(o) : _options.remove(o)),
              ),
              if (o == PresetOption.live && _options.contains(o))
                TextField(
                  key: const Key('presetLiveUrl'),
                  controller: _liveUrl,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.tr('presetLiveUrl'),
                    errorText: err == 'liveUrl' ? context.tr('invalidUrl') : null,
                  ),
                ),
              if (o == PresetOption.pdf && _options.contains(o)) ...[
                TextField(
                  key: const Key('presetPdfUrl'),
                  controller: _pdfUrl,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.tr('presetPdfUrl'),
                    errorText: err == 'attachmentUrl' ? context.tr('invalidUrl') : null,
                  ),
                ),
                TextField(
                    controller: _pdfLabelAr,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: context.tr('presetPdfLabelAr'))),
                TextField(
                    controller: _pdfLabelEn,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: context.tr('presetPdfLabelEn'))),
              ],
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('presetApply'),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(context.tr('presetApply')),
              // An ended season is never applied: `active` would stay on (CodeRabbit review).
              onPressed: _saving || ended ? null : () => _apply(context, season, raw),
            ),
          ],
        ]),
      ),
    );
  }
}
