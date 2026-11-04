import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/image_style.dart';
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

  /// Audience filter of the seasonal lists (ADR-041); '' = everyone.
  String _audience = '';

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

    // Open the seasonal view by default while a season that REPLACES the
    // regular schedule is in effect (an additive evening revival keeps the
    // weekly tabs: its regular morning masses continue).
    final seasonList = seasons.value;
    if (!_seasonDefaultApplied && seasonList != null) {
      _seasonDefaultApplied = true;
      if (activeSeasonsAt(seasonList, now).any((s) => s.replacesRegular)) _seasons = true;
    }

    return PageBody(
      header: CustomizablePageHeader(
          pageKey: CustomizablePages.schedule,
          
          title: context.tr('massSchedule'), subtitle: context.tr('dir_mass'), icon: Icons.access_time_filled_rounded),
      children: [
        const PageIntro(pageKey: CustomizablePages.schedule),
        const AlertBanner(),
        if ((lits.value ?? const <Liturgy>[]).any((l) => l.sample)) const PendingConfirmationNote(),
        const NextMassCard(),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            value: _seasons,
            onChanged: (v) => setState(() {
              _seasons = v;
              // The audience chips live in the seasonal view only: never
              // leave a hidden filter on (Sentry review).
              _audience = '';
              // The visitor chose: never override it with the season default.
              _seasonDefaultApplied = true;
            }),
            activeThumbColor: AppColors.gold,
            secondary: Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.primary),
            title: Text(context.tr('holySeasons'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(context.tr('holySeasonsHint')),
          ),
        ),
        if (lits.isLoading || (_seasons && seasons.isLoading))
          const Padding(padding: EdgeInsets.only(top: 16), child: SkeletonList(count: 4))
        else if (lits.hasError && !lits.hasValue)
          ErrorState(onRetry: () => ref.invalidate(liturgiesProvider))
        else if (_seasons)
          ..._seasonal(context, seasons.value ?? const [], lits.value ?? const [], now)
        else
          ..._weekly(context, lits.value ?? const [], seasons.value ?? const [], now),
      ],
    );
  }

  List<Widget> _weekly(BuildContext context, List<Liturgy> all, List<Season> seasons, DateTime now) {
    final list = regularLiturgiesForTab(all, _tab);
    final vespers = vespersAndPraise(all, now: now);
    final special = upcomingSpecialLiturgies(all, now);
    // Additive seasons in effect now (e.g. an evening revival): the weekly
    // view stays open, so their services (and feast liturgy) are listed here.
    final revivals = seasonalSchedule(seasons.where((s) => !s.replacesRegular && isSeasonActiveAt(s, now)), all);
    final showWeekday = _tab == ScheduleTab.other;
    // Services at the same time in another hall, across every list shown
    // (ADR-041; Codex / CodeRabbit review on PR #32).
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final shown = <String, Liturgy>{
      for (final l in [...revivals.values.expand((l) => l), ...special, ...list, ...vespers]) l.id: l,
    };
    final parallel = parallelServices(shown.values, opts);
    String parallelOf(Liturgy l) => parallelSummary(context, opts, parallel[l.id] ?? const []);
    return [
      for (final e in revivals.entries) ...[
        SectionTitle(
          context.pick(e.key.nameAr, e.key.nameEn),
          icon: Icons.auto_awesome_rounded,
          trailing: Pill(context.tr('activeNow'), icon: Icons.circle),
        ),
        Padding(padding: const EdgeInsets.only(bottom: Space.s), child: ProgramDetails(e.key.program)),
        // No audience chips in this view: never filter (Sentry review).
        ..._seasonCards(context, e.value, parallel),
      ],
      // One-off dated services outside any season (e.g. a feast or New
      // Year's Eve), which the weekly tabs cannot show.
      if (special.isNotEmpty) ...[
        SectionTitle(context.tr('specialServices'), icon: Icons.event_available_rounded),
        ResponsiveGrid(children: [
          for (final l in special)
            LiturgyCard(
              liturgy: l,
              showDate: true,
              parallelText: parallelOf(l),
            ),
        ]),
      ],
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
                    color: _tab == t ? context.pal.onPrimary : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                onSelected: (_) => setState(() => _tab = t),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const EmptyState(icon: Icons.event_busy)
      else
        ResponsiveGrid(children: [
          for (final l in list)
            LiturgyCard(
              liturgy: l,
              showWeekday: showWeekday,
              parallelText: parallelOf(l),
            ),
        ]),
      SectionTitle(context.tr('vespersPraise'), icon: Icons.nightlight_round),
      if (vespers.isEmpty)
        const EmptyState()
      else
        ResponsiveGrid(children: [
          for (final l in vespers)
            LiturgyCard(liturgy: l, showWeekday: true, showDate: true, parallelText: parallelOf(l)),
        ]),
    ];
  }

  List<Widget> _seasonal(BuildContext context, List<Season> seasons, List<Liturgy> all, DateTime now) {
    final grouped = seasonalSchedule(seasons, all);
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final allSeasonal = grouped.values.expand((l) => l).toList();
    // One map for every season shown: services of two seasons can overlap.
    final parallel = parallelServices(allSeasonal, opts);
    // The chosen audience applies only while its chip is shown (CodeRabbit).
    final keys = _audienceKeys(opts, allSeasonal);
    final audience = keys.length >= 2 && keys.contains(_audience) ? _audience : '';
    final showImages = ref.watch(featuresProvider.select((f) => f.showImages));
    if (grouped.isEmpty) return [const EmptyState(icon: Icons.event_busy)];
    // Seasons in effect now come first, then the others in date order.
    final entries = [
      ...grouped.entries.where((e) => isSeasonActiveAt(e.key, now)),
      ...grouped.entries.where((e) => !isSeasonActiveAt(e.key, now)),
    ];
    final out = <Widget>[];
    for (final e in entries) {
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
      final hasImage = s.image != null && showImages;
      final name = context.pick(s.nameAr, s.nameEn);
      final seasonStyle = ref.watch(featuresProvider).imageStyleFor('seasons', s.imageStyle);
      // Optional season / revival picture, in its display style (ADR-023);
      // nothing when there is none.
      if (hasImage && seasonStyle != ImageStyles.avatar) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: seasonStyle == ImageStyles.banner ? double.infinity : 560),
            child: DetailCover(key: const Key('seasonCover'), style: seasonStyle, image: s.image!, label: name),
          ),
        ));
      }
      if (range.isNotEmpty || (hasImage && seasonStyle == ImageStyles.avatar)) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Row(children: [
            CardLead(collection: 'seasons', itemStyle: s.imageStyle, image: s.image, size: 72, label: name),
            if (range.isNotEmpty) Expanded(child: IconLine(Icons.date_range_rounded, range)),
          ]),
        ));
      }
      if (!s.program.isEmpty) {
        out.add(Padding(padding: const EdgeInsets.only(bottom: Space.m), child: ProgramDetails(s.program)));
      }
      out.addAll(_seasonCards(context, e.value, parallel, audience: audience));
    }
    return [..._audienceFilter(context, keys, audience), ...out];
  }

  /// The audience keys the seasonal services use that resolve to a label.
  static Set<String> _audienceKeys(ProgramOptions opts, Iterable<Liturgy> all) =>
      {for (final l in all) if (opts.audience(l.program.audience) != null) l.program.audience};

  /// Audience chips (ADR-041) when the seasonal services name two or more
  /// audiences (e.g. everyone / youth / children in parallel halls).
  List<Widget> _audienceFilter(BuildContext context, Set<String> keys, String selected) {
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    if (keys.length < 2) return const [];
    Widget chip(String key, String label) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            key: Key('audience-$key'),
            label: Text(label),
            selected: selected == key,
            showCheckmark: false,
            labelStyle: TextStyle(
                color: selected == key ? context.pal.onPrimary : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700),
            onSelected: (_) => setState(() => _audience = key),
          ),
        );
    return [
      const SizedBox(height: Space.m),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip('', context.tr('allAudiences')),
          for (final o in ProgramOptions.withUsed(opts.audiences, keys, opts.audience))
            if (keys.contains(o.key)) chip(o.key, context.pick(o.labelAr, o.labelEn)),
        ]),
      ),
    ];
  }

  /// A season's services, filtered by [audience] (a service without an
  /// audience is for everyone), each with the services held at the same
  /// time in another hall ([parallel], ADR-041).
  List<Widget> _seasonCards(BuildContext context, List<Liturgy> list, Map<String, List<Liturgy>> parallel,
      {String audience = ''}) {
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final shown = audience.isEmpty
        ? list
        : [for (final l in list) if (l.program.audience.isEmpty || l.program.audience == audience) l];
    if (shown.isEmpty) return const [EmptyState(icon: Icons.event_busy)];
    return [
      ResponsiveGrid(children: [
        for (final l in shown)
          LiturgyCard(
            liturgy: l,
            showDate: true,
            parallelText: parallelSummary(context, opts, parallel[l.id] ?? const []),
          ),
      ]),
    ];
  }
}
