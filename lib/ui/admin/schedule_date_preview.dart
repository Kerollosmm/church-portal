import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/cairo_time.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/time_format.dart';
import '../widgets/common.dart' show localDigits;
import 'admin_strings.dart';
import 'state_switch.dart';

/// Loads liturgies and seasons, then opens [ScheduleDatePreviewSheet].
Future<void> showScheduleDatePreview(BuildContext context, {required AdminBackend repo}) async {
  registerAdminStrings();
  final messenger = ScaffoldMessenger.maybeOf(context);
  late final List<Liturgy> liturgies;
  late final List<Season> seasons;
  try {
    final docs = await Future.wait([repo.watch('liturgies').first, repo.watch('seasons').first]);
    liturgies = [
      for (final d in docs[0])
        if (!isSoftDeleted(d.data)) Liturgy.fromMap(d.id, d.data),
    ].where((l) => l.visible).toList();
    seasons = [
      for (final d in docs[1])
        if (!isSoftDeleted(d.data)) Season.fromMap(d.id, d.data),
    ];
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ScheduleDatePreviewSheet(liturgies: liturgies, seasons: seasons),
  );
}

/// Admin sheet: the public schedule as a visitor would see it on a chosen
/// Cairo date, with inactive seasons optionally forced on (#159).
class ScheduleDatePreviewSheet extends StatefulWidget {
  final List<Liturgy> liturgies;
  final List<Season> seasons;
  final DateTime? initialDate;
  const ScheduleDatePreviewSheet({
    super.key,
    required this.liturgies,
    required this.seasons,
    this.initialDate,
  });

  @override
  State<ScheduleDatePreviewSheet> createState() => _ScheduleDatePreviewSheetState();
}

class _ScheduleDatePreviewSheetState extends State<ScheduleDatePreviewSheet> {
  late DateTime _day;
  bool _includeInactive = false;

  @override
  void initState() {
    super.initState();
    registerAdminStrings();
    final now = CairoTime.now();
    final seed = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _day = DateTime(seed.year, seed.month, seed.day);
  }

  tz.TZDateTime get _dayStart => CairoTime.at(_day.year, _day.month, _day.day);

  List<Season> get _previewSeasons =>
      seasonsForVisitorPreview(widget.seasons, includeInactive: _includeInactive);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 2),
      lastDate: DateTime(_day.year + 3),
    );
    if (picked != null && mounted) setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final arabic = context.isAr;
    final seasons = _previewSeasons;
    final dayStart = _dayStart;
    final inEffect = [for (final s in seasons) if (isSeasonActiveOnDay(s, dayStart)) s];
    final occurrences = occurrencesForDay(
      liturgies: widget.liturgies,
      seasons: seasons,
      day: dayStart,
      dayOffset: 0,
    );
    final next = computeNextMass(liturgies: widget.liturgies, seasons: seasons, now: dayStart);
    final dateLabel = formatDate(_day, arabic: arabic);
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('previewScheduleDateTitle'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.pal.primary)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('preview-pick-date'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('${context.tr('previewPickDate')}: ${localDigits(context, dateLabel)}'),
                onPressed: _pickDate,
              ),
              AdminStateSwitch(
                key: const Key('preview-include-inactive'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('previewIncludeInactiveSeasons')),
                value: _includeInactive,
                onLabel: context.tr('switch_enabled'),
                offLabel: context.tr('switch_disabled'),
                onChanged: (v) => setState(() => _includeInactive = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    Text(context.tr('previewSeasonsInEffect'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    if (inEffect.isEmpty)
                      Text(context.tr('previewNoSeasonsInEffect'),
                          key: const Key('preview-no-seasons'),
                          style: TextStyle(color: context.pal.muted, height: 1.5))
                    else
                      for (final s in inEffect)
                        ListTile(
                          key: ValueKey('preview-season-${s.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.event_outlined, color: context.pal.primary),
                          title: Text(context.pick(s.nameAr, s.nameEn),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    const SizedBox(height: 16),
                    Text(context.tr('previewDaysServices'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    if (occurrences.isEmpty)
                      Text(context.tr('previewNoServices'),
                          key: const Key('preview-no-services'),
                          style: TextStyle(color: context.pal.muted, height: 1.5))
                    else
                      for (final o in occurrences)
                        ListTile(
                          key: ValueKey('preview-hit-${o.liturgy.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.church_outlined, color: context.pal.primary),
                          title: Text(context.pick(o.liturgy.nameAr, o.liturgy.nameEn),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            localDigits(
                              context,
                              arabic
                                  ? formatRangeArabic(o.liturgy.start, o.liturgy.end)
                                  : formatRangeLatin(o.liturgy.start, o.liturgy.end),
                            ),
                          ),
                        ),
                    if (next.next != null) ...[
                      const SizedBox(height: 16),
                      Text(context.tr('previewNextService'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ListTile(
                        key: ValueKey('preview-next-${next.next!.liturgy.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.schedule_outlined, color: context.pal.primary),
                        title: Text(context.pick(next.next!.liturgy.nameAr, next.next!.liturgy.nameEn),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
