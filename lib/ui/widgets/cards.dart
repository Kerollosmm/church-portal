import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../domain/models.dart';
import '../../domain/reminders.dart';
import '../../domain/rules.dart';
import '../../domain/schedule.dart';
import '../../domain/today.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import 'common.dart';
import 'item_image.dart';
import 'program_details.dart';
import 'remind_me.dart';
import 'styled_image.dart';

export 'program_details.dart' show ProgramDetails, parallelSummary, parallelThenLine;
export 'styled_image.dart';

/// The occurrence a liturgy card's «ذكّرني» is for. [skipToday]: today's
/// service is replaced by a season service (the card's «لا يقام اليوم»), so
/// a weekly liturgy points at next week instead.
DateTime _nextLiturgyOccurrence(Liturgy l, DateTime now, {bool skipToday = false}) {
  if (l.date != null) {
    final c = CairoTime.calendarDate(l.date!);
    return CairoTime.at(c.year, c.month, c.day, l.startMinutes ?? 0);
  }
  final cNow = CairoTime.fromInstant(now);
  final weekday = l.weekday ?? 7;
  final daysAhead = (weekday - cNow.weekday + 7) % 7;
  var target = CairoTime.at(cNow.year, cNow.month, cNow.day + daysAhead, l.startMinutes ?? 0);
  if (target.isBefore(cNow) || (skipToday && daysAhead == 0)) {
    target = CairoTime.at(cNow.year, cNow.month, cNow.day + daysAhead + 7, l.startMinutes ?? 0);
  }
  return target;
}

/// Card for one liturgy on the schedule page.
class LiturgyCard extends StatelessWidget {
  final Liturgy liturgy;
  final bool showWeekday;
  final bool showDate;

  /// Services held at the same time in another hall (ADR-041), e.g.
  /// «القاعة السفلية (شباب)»; '' = none.
  final String parallelText;

  /// A regular service a season supersedes TODAY ([regularSupersededOn]):
  /// marked «لا يُقام اليوم» so the weekly tab never contradicts the home
  /// card (ADR-050).
  final bool notHeldToday;
  const LiturgyCard(
      {super.key,
      required this.liturgy,
      this.showWeekday = false,
      this.showDate = false,
      this.parallelText = '',
      this.notHeldToday = false,
      this.notHeldOn = ''});

  /// The days a listed season sample is not held (ADR-054), already
  /// formatted («٢٣ يونيو»); '' = none.
  final String notHeldOn;

  IconData get _icon => switch (liturgy.type) {
        'vespers' => Icons.nightlight_round,
        'praise' => Icons.music_note_rounded,
        'other' => Icons.menu_book_rounded,
        _ => Icons.church_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l = liturgy;
    final dayText = showDate && l.date != null
        ? formatDate(CairoTime.calendarDate(l.date!), arabic: context.isAr)
        : (showWeekday || showDate) ? weekdayLabel(context, l.weekday) : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.pal.barGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: Icon(_icon, color: context.pal.onBarAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dayText.isNotEmpty)
                Text(dayText,
                    style: TextStyle(color: context.pal.goldText, fontWeight: FontWeight.w800, fontSize: 12)),
              if (notHeldToday)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Pill(context.tr('notHeldToday'),
                      key: const Key('notHeldToday'), icon: Icons.event_busy, color: context.pal.muted),
                ),
              if (notHeldOn.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // Every date stays readable (no line limit; CodeRabbit on PR #48).
                  child: Pill(context.tr('notHeldOn', {'d': notHeldOn}),
                      key: const Key('notHeldOn'), icon: Icons.event_busy, color: context.pal.muted, maxLines: null),
                ),
              Text(context.pick(l.nameAr, l.nameEn),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              TimeRangeText(l.start, l.end),
              const SizedBox(height: 6),
              IconLine(Icons.place_outlined, context.pick(l.placeAr, l.placeEn)),
              IconLine(Icons.people_outline, context.pick(l.audienceAr, l.audienceEn)),
              ProgramDetails(l.program, parallelText: parallelText),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: RemindMeButton(
                  eventKey: EventKey.liturgy(l.id),
                  occurrence: l.date != null ? isoDate(CairoTime.calendarDate(l.date!)) : null,
                  title: {'ar': l.nameAr, 'en': l.nameEn},
                  startsAt: _nextLiturgyOccurrence(l, CairoTime.now(), skipToday: notHeldToday),
                  recurring: l.date == null,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "Next liturgy" smart card (top of Home).
class NextMassCard extends ConsumerWidget {
  const NextMassCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lits = ref.watch(liturgiesProvider);
    final seasons = ref.watch(seasonsProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    Widget body;
    NextMassResult? result;
    if (lits.isLoading || seasons.isLoading) {
      body = const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SkeletonBox(height: 14, width: 120),
        SizedBox(height: 10),
        SkeletonBox(height: 22, width: 220),
        SizedBox(height: 8),
        SkeletonBox(height: 16, width: 180),
      ]);
    } else if (lits.hasError && !lits.hasValue) {
      body = ErrorState(onRetry: () => ref.invalidate(liturgiesProvider));
    } else {
      final r = computeNextMass(liturgies: lits.value ?? const [], seasons: seasons.value ?? const [], now: now);
      result = r;
      final s = ref.watch(settingsProvider).value;
      // The next service's «وفي نفس الوقت: …» line, as on /mass-schedule
      // (ADR-041; CodeRabbit review on PR #32).
      final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
      // From that day's real occurrences, so a suppressed or out-of-season
      // service is never named (Sentry review); with the days either side,
      // so a service crossing midnight meets the next day's (ADR-049).
      final next = r.next;
      // A service the «يُقام الآن» box above already names is not repeated
      // under the next one (ADR-054, sims r3 P7 12:30).
      final parallel = next == null
          ? const <LiturgyOccurrence>[]
          : [
              for (final o in parallelOccurrencesOf(
              next,
              occurrencesAround(
                  liturgies: lits.value ?? const [],
                  seasons: seasons.value ?? const [],
                  day: next.start,
                  dayOffset: next.dayOffset),
              opts))
                if (!r.shownInNowBox(o, opts)) o,
            ];
      // One starting later, while the next service runs, is named with its
      // own time («وبعدها ٠٧:٠٠ ص: …»), not «في نفس الوقت» (ADR-053, sims
      // r2 P2 O-a); one already running when it starts stays «في نفس الوقت».
      final parallelText = parallelSummary(context, opts, [
        for (final o in parallel)
          if (!o.start.isAfter(next!.start)) o.liturgy,
      ]);
      final parallelThen = [
        for (final o in parallel)
          if (o.start.isAfter(next!.start)) parallelThenLine(context, opts, o.liturgy, _hm(context, o.start)),
      ];
      // The «يُقام الآن» box names the services running at this moment in
      // the other halls (ADR-049 item 1: youth and children's Pascha beside
      // the main church's): no extra read, the card already holds them.
      final nowParallelText = parallelSummary(context, opts, r.alsoRunning(opts));
      body = _content(context, r, now, ref.watch(todaySettingsProvider), s?.lat, s?.lng, parallelText, opts,
          nowParallelText, parallelThen);
    }

    final pal = context.pal;
    // During a season that replaces the weekly schedule the card lists its
    // prayers (Pascha hours…), not only masses (ADR-043); it is also «الصلاة
    // القادمة» whenever the service it shows is not a mass (a revival night,
    // ADR-045).
    final shown = [result?.happeningNow, result?.next].whereType<LiturgyOccurrence>();
    final seasonal = activeSeasonsAt(seasons.value ?? const [], now).any((s) => s.replacesRegular) ||
        shown.any((o) => o.liturgy.type != 'mass');
    // Warm panel with a title band in the theme's band colours (maroon on
    // the posters; charcoal with a crimson edge on Holy Week — ADR-043).
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(color: pal.ornamentLine),
        boxShadow: pal.panelShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const Key('nextMassBand'),
          decoration: BoxDecoration(
            gradient: pal.barGradient(),
            border: pal.barEdge == null ? null : Border(bottom: BorderSide(color: pal.barEdge!, width: 2)),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
          // Wrap: on narrow screens / large text "Full schedule" moves under
          // the title instead of overflowing.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time_filled_rounded, color: pal.onBarAccent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(context.tr(seasonal ? 'nextPrayer' : 'nextMass'),
                      style: displayStyle(context, size: 18, color: pal.onBar, height: 1.4)),
                ),
              ]),
              TextButton(
                onPressed: () => context.go('/mass-schedule'),
                style: TextButton.styleFrom(foregroundColor: pal.onBarAccent),
                child: Text(context.tr('fullSchedule')),
              ),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 16), child: body),
      ]),
    );
  }

  /// [t] (a Cairo instant) as «٠٣:٣٠ ص» / "03:30 AM".
  static String _hm(BuildContext context, DateTime t) {
    final c = CairoTime.fromInstant(t);
    final hm = '${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';
    return context.isAr ? formatTimeArabic(hm) : formatTimeLatin(hm);
  }

  Widget _content(BuildContext context, NextMassResult r, DateTime now, TodaySettings today, double? lat, double? lng,
      [String parallelText = '',
      ProgramOptions opts = ProgramOptions.defaults,
      String nowParallelText = '',
      List<String> parallelThen = const []]) {
    if (r.isEmpty) return EmptyState(message: context.tr('noUpcoming'), icon: Icons.event_busy);
    final children = <Widget>[];
    if (r.activeSeasons.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Pill(
          context.tr('seasonActive', {'s': r.activeSeasons.map((s) => context.pick(s.nameAr, s.nameEn)).join('، ')}),
          maxLines: null, // every active season name must stay readable
          // Balanced lines: a long name never leaves «ش)» alone (ADR-054).
          balanced: true,
          key: const Key('seasonActivePill'),
          color: context.pal.primary,
          icon: Icons.auto_awesome,
        ),
      ));
    }
    if (r.happeningNow != null) {
      final o = r.happeningNow!;
      // Without a free-text place the line already names the venue: no pill.
      final lineHasVenue = context.pick(o.liturgy.placeAr, o.liturgy.placeEn).trim().isEmpty;
      children.add(Container(
        key: const Key('happeningNowBox'),
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.pal.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(context.tr('happeningNow'), icon: Icons.circle, color: context.pal.success),
            const SizedBox(width: 8),
            Expanded(
              // Free-text place, else the venue; no dash when neither (ADR-043).
              child: Text(serviceWithPlace(context, opts, o.liturgy),
                  key: const Key('happeningNowLine'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          // When it ends («حتى ٠٣:٣٠ ص»), in the app's 12-hour ص/م format
          // (ADR-050, issue 15); a service without an end time runs its
          // default 120 minutes, as the card counts it.
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Text(context.tr('untilTime', {'t': _hm(context, o.end)}),
                key: const Key('happeningNowUntil'),
                style: TextStyle(color: context.pal.goldText, fontWeight: FontWeight.w700)),
          ),
          // While it runs (18:30–21:30 on a revival night, exactly when
          // visitors open the site) the programme stays: speaker, topic,
          // choir, audience and the PDF button (ADR-045, revival sim B2).
          ProgramDetails(o.liturgy.program, showVenue: !lineHasVenue, parallelText: nowParallelText),
        ]),
      ));
    }
    final n = r.next;
    if (n != null) {
      final dayLabel = switch (n.dayOffset) {
        0 => context.tr('today'),
        1 => context.tr('tomorrow'),
        _ => context.inDays(n.dayOffset),
      };
      final mins = n.start.difference(now).inMinutes;
      // A service after the liturgical day's start (18:00 by default)
      // belongs to the next day: «الليلة • ليلة الخميس» (ADR-039).
      final eve = today.isEveService(n.start, lat: lat, lng: lng);
      String? countdown;
      if (n.dayOffset == 0 && mins >= 0) {
        final h = mins ~/ 60, m = mins % 60;
        final t = h > 0
            ? '${localDigits(context, '$h')} ${context.tr('hoursShort')} ${localDigits(context, '$m')} ${context.tr('minutesShort')}'
            : '${localDigits(context, '$m')} ${context.tr('minutesShort')}';
        countdown = context.tr('startsIn', {'t': t});
      }
      children.add(Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill(
            eve
                ? '${n.dayOffset == 0 ? context.tr('tonight') : dayLabel} • ${context.tr('eveOf', {'d': weekdayLabel(context, n.start.add(const Duration(days: 1)).weekday)})}'
                : '$dayLabel • ${weekdayLabel(context, n.start.weekday)}',
            color: context.pal.primary),
        if (countdown != null) Pill(countdown, color: context.pal.goldText, icon: Icons.timer_outlined),
      ]));
      children.add(const SizedBox(height: 8));
      children.add(Text(context.pick(n.liturgy.nameAr, n.liturgy.nameEn),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)));
      children.add(const SizedBox(height: 4));
      children.add(TimeRangeText(n.liturgy.start, n.liturgy.end, large: true));
      children.add(const SizedBox(height: 6));
      children.add(IconLine(Icons.place_outlined, context.pick(n.liturgy.placeAr, n.liturgy.placeEn)));
      children.add(IconLine(Icons.people_outline, context.pick(n.liturgy.audienceAr, n.liturgy.audienceEn)));
      children.add(ProgramDetails(n.liturgy.program, parallelText: parallelText, parallelThen: parallelThen));
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: RemindMeButton(
          eventKey: EventKey.liturgy(n.liturgy.id),
          occurrence: n.liturgy.date != null ? isoDate(CairoTime.calendarDate(n.liturgy.date!)) : null,
          title: {'ar': n.liturgy.nameAr, 'en': n.liturgy.nameEn},
          startsAt: n.start,
          recurring: n.liturgy.date == null,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// Urgent alert banner — renders nothing unless an alert is visible now.
/// Shows the two highest-priority alerts, with a toggle for the rest.
class AlertBanner extends ConsumerStatefulWidget {
  const AlertBanner({super.key});

  @override
  ConsumerState<AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends ConsumerState<AlertBanner> {
  static const _collapsedCount = 2;
  bool _expanded = false;

  static bool _isInternal(String link) => link.startsWith('/') && !link.startsWith('//');

  // In-app routes start with a single '/'; '//host/...' is an external
  // protocol-relative link.
  Widget _learnMore(BuildContext context, String link) => TextButton(
        onPressed: () => _isInternal(link) ? context.go(link) : openUrl(link),
        // The notice box stays light on every theme: a light (dark-theme)
        // primary would vanish on it.
        style: context.pal.dark ? TextButton.styleFrom(foregroundColor: context.pal.alert) : null,
        child: Text(context.tr('learnMore')),
      );

  /// A link to a switched-off section would only open "not available"
  /// (golden rule #6): hide the button, like the announcement banner does.
  static bool _linkShown(String? link, FeatureSettings f) {
    if (link == null || link.trim().isEmpty) return false;
    final l = link.trim();
    return !_isInternal(l) || f.routeEnabled(Uri.tryParse(l)?.path ?? l);
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(featuresProvider);
    if (!features.enabled(Sections.alerts)) return const SizedBox.shrink();
    final alerts = ref.watch(alertsProvider).value;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (alerts == null) return const SizedBox.shrink();
    final visible = visibleAlerts(alerts, now);
    if (visible.isEmpty) return const SizedBox.shrink();
    final hidden = visible.length - _collapsedCount;
    final compact =
        MediaQuery.sizeOf(context).width < 600 || MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    return Column(children: [
      for (final a in _expanded ? visible : visible.take(_collapsedCount))
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: Space.m),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.pal.alertGround,
            borderRadius: BorderRadius.circular(14),
            border: BorderDirectional(start: BorderSide(color: context.pal.alert, width: 5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Card / banner style: the picture across the top (ADR-023).
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: CardCover(
                collection: 'alerts', itemStyle: a.imageStyle, image: a.image, label: context.pick(a.titleAr, a.titleEn)),
          ),
          Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardLead(
              collection: 'alerts',
              itemStyle: a.imageStyle,
              image: a.image,
              size: 52,
              label: context.pick(a.titleAr, a.titleEn),
              placeholder: Icon(Icons.campaign_rounded, color: context.pal.alert),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.pick(a.titleAr, a.titleEn),
                    style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.alert)),
                if (context.pick(a.bodyAr, a.bodyEn).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.pick(a.bodyAr, a.bodyEn),
                        style: TextStyle(height: 1.5, color: context.pal.ink)),
                  ),
                // Phones / large text: the button goes under the text so the
                // row never overflows.
                if (compact && _linkShown(a.link, features))
                  Align(alignment: AlignmentDirectional.centerEnd, child: _learnMore(context, a.link!.trim())),
              ]),
            ),
            if (!compact && _linkShown(a.link, features)) _learnMore(context, a.link!.trim()),
          ]),
        ),
          ]),
        ),
      if (hidden > 0)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(_expanded
                ? context.tr('showFewerAlerts')
                : context.tr('showAllAlerts', {'n': localDigits(context, '${visible.length}')})),
          ),
        ),
    ]);
  }
}

/// Square-ish directory card with icon + description + "Learn more".
class DirectoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const DirectoryCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = context.pal.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: EdgeAccent(
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Maroon badge (follows the admin colour preset).
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: context.pal.barGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: context.pal.onBarAccent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: displayStyle(context, size: 21, color: primary, height: 1.35)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: context.pal.muted, fontSize: 13.5, height: 1.55)),
                const SizedBox(height: 6),
                // Flexible: "Learn more" wraps instead of overflowing at 320 px / 200% text.
                Row(children: [
                  Flexible(
                    child: Text(context.tr('learnMore'),
                        style: TextStyle(
                            color: context.pal.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: context.pal.primary),
                ]),
              ]),
            ),
          ]),
        ),
        ),
      ),
    );
  }
}

/// Small round action buttons (call / WhatsApp / Facebook...).
class ActionChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  /// What screen readers announce instead of the short [label], naming the
  /// target (e.g. "Call — Dental clinic"), so repeated "Call" buttons on a
  /// page can be told apart.
  final String? semanticLabel;
  const ActionChipButton(
      {super.key, required this.icon, required this.label, required this.color, this.onTap, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        // Brand fills are dark (white text); a light fill (Holy Week's
        // silver primary) gets the theme's dark text.
        foregroundColor: color.computeLuminance() > 0.25
            ? context.pal.onPrimary
            : Colors.white, // palette-exempt: white on darkened brand / band fills (≥ 4.5:1 by construction)
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    final s = semanticLabel;
    if (s == null || s.isEmpty) return button;
    return Semantics(
      container: true,
      label: s,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// "Call — Dental clinic": an action label plus the item it acts on.
String actionSemanticLabel(String action, String target) => target.isEmpty ? action : '$action — $target';

// Darkened brand fills so white button text meets WCAG AA (>= 4.5:1).
// Third-party brand colours, not theme colours (palette-exempt).
const whatsappGreen = Color(0xFF157338); // palette-exempt: WhatsApp brand
const facebookBlue = Color(0xFF145DBF); // palette-exempt: Facebook brand
const youtubeRed = Color(0xFFD32F2F); // palette-exempt: YouTube brand
const instagramPink = Color(0xFFC13584); // palette-exempt: Instagram brand

/// Detail page of an item card, or null when an admin switched it off
/// (explicit `detailsEnabled: false`; missing = on since PR #14). The card
/// then has no Details link and no card tap.
String? cardDetailPath(DetailKind kind, String id, ItemDetails details) =>
    details.detailsEnabled ? detailPathFor(kind, id) : null;

/// Makes a card surface open [path] on tap (null = [child] unchanged).
/// Pointer-only: inner buttons still win their own taps, and screen readers
/// use the labelled [DetailsLink] instead of one big nested button.
class DetailTapArea extends StatelessWidget {
  final String? path;
  final Widget child;
  const DetailTapArea({super.key, required this.path, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => context.go(p),
        child: child,
      ),
    );
  }
}

/// "التفاصيل / Details ›" link at the end of a card whose detail page is on.
class DetailsLink extends StatelessWidget {
  final String path;

  /// Item title, announced with the action ("Details — Dental clinic").
  final String title;

  /// Item id (key `detailsLink-<id>` for tests / automation).
  final String id;
  const DetailsLink({super.key, required this.path, required this.title, required this.id});

  @override
  Widget build(BuildContext context) {
    final label = context.tr('details');
    void open() => context.go(path);
    return Align(
      key: const Key('detailsLink'),
      alignment: AlignmentDirectional.centerEnd,
      child: Semantics(
        container: true,
        button: true,
        link: true,
        label: actionSemanticLabel(label, title),
        onTap: open,
        excludeSemantics: true,
        child: TextButton.icon(
          key: ValueKey('detailsLink-$id'),
          onPressed: open,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// Optional card image leading a title row: nothing at all (no gap) when the
/// item has no image or images are switched off, so such cards look exactly
/// as before.
class CardImageLead extends ConsumerWidget {
  final MediaImage image;
  final String label;
  final bool enlargeOnTap;
  final double size;
  const CardImageLead(
      {super.key, required this.image, required this.label, this.enlargeOnTap = true, this.size = 56});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featuresProvider.select((f) => f.showImages))) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: ItemImage(
        image: image,
        size: size,
        circle: false,
        label: label,
        enlargeOnTap: enlargeOnTap,
        placeholder: SizedBox.square(dimension: size),
      ),
    );
  }
}

/// Start-edge accent bar (3 px, primary) for listing cards: the UX standard's
/// "accent edge", drawn inside the card's clip so the card keeps its radius.
class EdgeAccent extends StatelessWidget {
  final Widget child;
  final Color? color;
  const EdgeAccent({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: color ?? context.pal.primary, width: 3)),
        ),
        child: child,
      );
}
