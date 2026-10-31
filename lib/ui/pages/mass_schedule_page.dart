import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class MassSchedulePage extends ConsumerStatefulWidget {
  const MassSchedulePage({super.key});

  @override
  ConsumerState<MassSchedulePage> createState() => _MassSchedulePageState();
}

class _MassSchedulePageState extends ConsumerState<MassSchedulePage> {
  late ScheduleTab _tab = _todayTab();
  bool _seasons = false;
  bool _seasonDefaultApplied = false;

  static ScheduleTab _todayTab() {
    final wd = CairoTime.now().weekday;
    return scheduleTabWeekdays.entries.firstWhere((e) => e.value.contains(wd)).key;
  }

  String _tabLabel(ScheduleTab t) => switch (t) {
        ScheduleTab.friday => context.tr('friday'),
        ScheduleTab.sunday => context.tr('sunday'),
        ScheduleTab.wednesday => context.tr('wednesday'),
        ScheduleTab.saturday => context.tr('saturday'),
        ScheduleTab.other => context.tr('otherDays'),
      };

  @override
  Widget build(BuildContext context) {
    final lits = ref.watch(liturgiesProvider);
    final seasons = ref.watch(seasonsProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    // Open the seasonal view by default while a season is in effect.
    final seasonList = seasons.value;
    if (!_seasonDefaultApplied && seasonList != null) {
      _seasonDefaultApplied = true;
      if (activeSeasonsAt(seasonList, now).isNotEmpty) _seasons = true;
    }

    return PageBody(
      header: PageHeader(
          title: context.tr('massSchedule'), subtitle: context.tr('dir_mass'), icon: Icons.access_time_filled_rounded),
      children: [
        const AlertBanner(),
        const NextMassCard(),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            value: _seasons,
            onChanged: (v) => setState(() => _seasons = v),
            activeThumbColor: AppColors.gold,
            secondary: const Icon(Icons.auto_awesome_rounded, color: AppColors.burgundy),
            title: Text(context.tr('holySeasons'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(context.tr('holySeasonsHint')),
          ),
        ),
        if (lits.isLoading || seasons.isLoading)
          const Padding(padding: EdgeInsets.only(top: 16), child: SkeletonList(count: 4))
        else if (lits.hasError && !lits.hasValue)
          ErrorState(onRetry: () => ref.invalidate(liturgiesProvider))
        else if (_seasons)
          ..._seasonal(context, seasons.value ?? const [], lits.value ?? const [], now)
        else
          ..._weekly(context, lits.value ?? const []),
      ],
    );
  }

  List<Widget> _weekly(BuildContext context, List<Liturgy> all) {
    final list = regularLiturgiesForTab(all, _tab);
    final vespers = vespersAndPraise(all);
    final showWeekday = _tab == ScheduleTab.other;
    return [
      SectionTitle(context.tr('regularSchedule'), icon: Icons.calendar_month_rounded),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in ScheduleTab.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(_tabLabel(t)),
                selected: _tab == t,
                showCheckmark: false,
                labelStyle: TextStyle(
                    color: _tab == t ? Colors.white : AppColors.burgundy, fontWeight: FontWeight.w700),
                onSelected: (_) => setState(() => _tab = t),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const EmptyState(icon: Icons.event_busy)
      else
        ResponsiveGrid(minItemWidth: 340, children: [
          for (final l in list) LiturgyCard(liturgy: l, showWeekday: showWeekday),
        ]),
      SectionTitle(context.tr('vespersPraise'), icon: Icons.nightlight_round),
      if (vespers.isEmpty)
        const EmptyState()
      else
        ResponsiveGrid(minItemWidth: 340, children: [
          for (final l in vespers) LiturgyCard(liturgy: l, showWeekday: true),
        ]),
    ];
  }

  List<Widget> _seasonal(BuildContext context, List<Season> seasons, List<Liturgy> all, DateTime now) {
    final grouped = seasonalSchedule(seasons, all);
    if (grouped.isEmpty) return [const EmptyState(icon: Icons.event_busy)];
    final out = <Widget>[];
    for (final e in grouped.entries) {
      final s = e.key;
      final active = isSeasonActiveAt(s, now);
      final range = [
        if (s.startsAt != null) formatDate(CairoTime.calendarDate(s.startsAt!), arabic: context.isAr),
        if (s.endsAt != null) formatDate(CairoTime.calendarDate(s.endsAt!), arabic: context.isAr),
      ].join(' – ');
      out.add(SectionTitle(
        context.pick(s.nameAr, s.nameEn),
        icon: Icons.auto_awesome_rounded,
        trailing: active ? Pill(context.tr('activeNow'), icon: Icons.circle) : null,
      ));
      if (range.isNotEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IconLine(Icons.date_range_rounded, range),
        ));
      }
      out.add(ResponsiveGrid(minItemWidth: 340, children: [
        for (final l in e.value) LiturgyCard(liturgy: l, showDate: true),
      ]));
    }
    return out;
  }
}
