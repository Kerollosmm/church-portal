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
            // ON / OFF clearly apart on every theme, Holy Week's charcoal
            // included (ADR-049): palette roles only (ADR-043).
            activeThumbColor: context.pal.switchOnThumb,
            activeTrackColor: context.pal.switchOnTrack,
            inactiveThumbColor: context.pal.switchOffThumb,
            inactiveTrackColor: context.pal.switchOffTrack,
            trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected) ? context.pal.switchOnTrack : context.pal.switchOffThumb),
            secondary: Icon(Icons.auto_awesome_rounded, color: context.pal.primary),
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
    final revivals =
        seasonalSchedule(seasons.where((s) => !s.replacesRegular && isSeasonActiveAt(s, now)), all, context: seasons);
    final showWeekday = _tab == ScheduleTab.other;
    // Services at the same time in another hall, across every list shown
    // (ADR-041; Codex / CodeRabbit review on PR #32).
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final shown = <String, Liturgy>{
      for (final l in [...revivals.values.expand((l) => l), ...special, ...list, ...vespers]) l.id: l,
    };
    final parallel = parallelServices(shown.values, opts);
    String parallelOf(Liturgy l) => parallelSummary(context, opts, parallel[l.id] ?? const []);
    // Regular services a season supersedes today: the same function as the
    // home card, so the tab marks them «لا يُقام اليوم» (ADR-050).
    final today = CairoTime.startOfDay(CairoTime.fromInstant(now));
    final notToday = {
      for (final l in regularSupersededOn(liturgies: all, seasons: seasons, day: today)) l.id,
    };
    // A dated one-off (a special service or vespers) superseded today is
    // marked too; [regularSupersededOn] only names one dated today
    // (CodeRabbit on PR #45).
    bool offToday(Liturgy l) => notToday.contains(l.id) && (l.date != null || l.weekday == today.weekday);
    return [
      for (final e in revivals.entries) ...[
        SectionTitle(
          context.pick(e.key.nameAr, e.key.nameEn),
          icon: Icons.auto_awesome_rounded,
          trailing: Pill(context.tr('activeNow'), icon: Icons.circle),
        ),
        Padding(padding: const EdgeInsets.only(bottom: Space.s), child: ProgramDetails(e.key.program)),
        // No audience chips in this view: never filter (Sentry review).
        ..._seasonCards(context, e.value, parallel, season: e.key, all: all, seasons: seasons, now: now),
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
              notHeldToday: offToday(l),
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
                    color: _tab == t ? context.pal.onBar : context.pal.primary, fontWeight: FontWeight.w700),
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
              notHeldToday: offToday(l),
            ),
        ]),
      SectionTitle(context.tr('vespersPraise'), icon: Icons.nightlight_round),
      if (vespers.isEmpty)
        const EmptyState()
      else
        ResponsiveGrid(children: [
          for (final l in vespers)
            LiturgyCard(
                liturgy: l, showWeekday: true, showDate: true, parallelText: parallelOf(l), notHeldToday: offToday(l)),
        ]),
    ];
  }

  List<Widget> _seasonal(BuildContext context, List<Season> seasons, List<Liturgy> all, DateTime now) {
    // A season that ended before today is no longer listed (ADR-054).
    final grouped = seasonalSchedule(seasons, all, now: now);
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final allSeasonal = grouped.values.expand((l) => l).toList();
    // One map for every season shown: services of two seasons can overlap.
    final parallel = parallelServices(allSeasonal, opts);
    // The chosen audience applies only while its chip is shown (CodeRabbit).
    final keys = _audienceKeys(opts, allSeasonal);
    final audience = keys.length >= 2 && keys.contains(_audience) ? _audience : '';
    final showImages = ref.watch(featuresProvider.select((f) => f.showImages));
    // No season in effect now (all ended / none enabled yet): a friendly
    // empty state naming the next season, from the seasons already loaded
    // (ADR-055). Upcoming seasons with services stay listed below it.
    final none = activeSeasonsAt(seasons, now).isEmpty ? _noCurrentSeasons(context, seasons, now) : null;
    if (grouped.isEmpty) return [none ?? const EmptyState(icon: Icons.event_busy)];
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
      out.addAll(_seasonCards(context, e.value, parallel,
          audience: audience, season: s, all: all, seasons: seasons, now: now));
    }
    return [?none, ..._audienceFilter(context, keys, audience), ...out];
  }

  /// «لا توجد مواسم حالية» + «الموسم القادم: … — يبدأ ٢٥ نوفمبر» (ADR-055).
  Widget _noCurrentSeasons(BuildContext context, List<Season> seasons, DateTime now) {
    final next = nextUpcomingSeason(seasons, now);
    String? line;
    if (next != null) {
      final start = CairoTime.calendarDate(next.startsAt!);
      final today = CairoTime.fromInstant(now);
      final date = start.year == today.year
          ? formatDayMonth(start, arabic: context.isAr)
          : formatDate(start, arabic: context.isAr);
      line = context.tr('nextSeasonLine', {'name': context.pick(next.nameAr, next.nameEn), 'date': date});
    }
    return EmptyState(
      key: const Key('noCurrentSeasons'),
      icon: Icons.event_available_rounded,
      message: context.tr('noCurrentSeasons'),
      detail: line,
    );
  }

  /// The audience keys the seasonal services use that resolve to a label.
  static Set<String> _audienceKeys(ProgramOptions opts, Iterable<Liturgy> all) =>
      {for (final l in all) if (opts.audience(l.program.audience) != null) opts.audienceKey(l.program.audience)};

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
                color: selected == key ? context.pal.onBar : context.pal.primary,
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
  ///
  /// A sample still listed but not held on some days, because another
  /// season's real service takes its time, says so on its card («لا يُقام
  /// ٢٣ يونيو», ADR-054); past days are not named.
  List<Widget> _seasonCards(BuildContext context, List<Liturgy> list, Map<String, List<Liturgy>> parallel,
      {String audience = '',
      Season? season,
      List<Liturgy> all = const [],
      List<Season> seasons = const [],
      DateTime? now}) {
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final shown = audience.isEmpty
        ? list
        : [for (final l in list) if (audienceMatches(l, audience, opts)) l];
    if (shown.isEmpty) return const [EmptyState(icon: Icons.event_busy)];
    return [
      ResponsiveGrid(children: [
        for (final l in shown)
          LiturgyCard(
            liturgy: l,
            showDate: true,
            parallelText: parallelSummary(context, opts, parallel[l.id] ?? const []),
            notHeldOn: season == null
                ? ''
                : seasonListExceptions(l, season, all, seasons: seasons, from: now)
                    .map((x) => formatDayMonth(x.date, arabic: context.isAr))
                    .join(context.isAr ? '، ' : ', '),
          ),
      ]),
    ];
  }
}

/// [l] shows under the audience chip [audience] (ADR-041): its own audience,
/// or none / an unknown key (no chip of its own) = for everyone (Sentry review).
bool audienceMatches(Liturgy l, String audience, ProgramOptions opts) {
  final a = l.program.audience;
  // `kids` and `children` are one audience (ADR-043).
  return audience.isEmpty || a.isEmpty || opts.audienceKey(a) == audience || opts.audience(a) == null;
}
