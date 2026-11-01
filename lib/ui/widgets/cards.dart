import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../domain/schedule.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import 'common.dart';
import 'item_image.dart';

/// Card for one liturgy on the schedule page.
class LiturgyCard extends StatelessWidget {
  final Liturgy liturgy;
  final bool showWeekday;
  final bool showDate;
  const LiturgyCard({super.key, required this.liturgy, this.showWeekday = false, this.showDate = false});

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
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dayText.isNotEmpty)
                Text(dayText,
                    style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w800, fontSize: 12)),
              TitleWithBadge(context.pick(l.nameAr, l.nameEn),
                  sample: l.sample, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              TimeRangeText(l.start, l.end),
              const SizedBox(height: 6),
              IconLine(Icons.place_outlined, context.pick(l.placeAr, l.placeEn)),
              IconLine(Icons.people_outline, context.pick(l.audienceAr, l.audienceEn)),
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
      body = _content(context, r, now);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFFAF0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold, width: 1.4),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Wrap: on narrow screens / large text "Full schedule" moves under
        // the title instead of overflowing.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.access_time_filled_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(context.tr('nextMass'),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
              ),
            ]),
            TextButton(onPressed: () => context.go('/mass-schedule'), child: Text(context.tr('fullSchedule'))),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ]),
    );
  }

  Widget _content(BuildContext context, NextMassResult r, DateTime now) {
    if (r.isEmpty) return EmptyState(message: context.tr('noUpcoming'), icon: Icons.event_busy);
    final children = <Widget>[];
    if (r.activeSeasons.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Pill(
          context.tr('seasonActive', {'s': r.activeSeasons.map((s) => context.pick(s.nameAr, s.nameEn)).join('، ')}),
          maxLines: null, // every active season name must stay readable
          color: Theme.of(context).colorScheme.primary,
          icon: Icons.auto_awesome,
        ),
      ));
    }
    if (r.happeningNow != null) {
      final o = r.happeningNow!;
      children.add(Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Pill(context.tr('happeningNow'), icon: Icons.circle, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${context.pick(o.liturgy.nameAr, o.liturgy.nameEn)} — ${context.pick(o.liturgy.placeAr, o.liturgy.placeEn)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ));
    }
    final n = r.next;
    if (n != null) {
      final dayLabel = switch (n.dayOffset) {
        0 => context.tr('today'),
        1 => context.tr('tomorrow'),
        _ => context.tr('inDays', {'n': localDigits(context, '${n.dayOffset}')}),
      };
      final mins = n.start.difference(now).inMinutes;
      String? countdown;
      if (n.dayOffset == 0 && mins >= 0) {
        final h = mins ~/ 60, m = mins % 60;
        final t = h > 0
            ? '${localDigits(context, '$h')} ${context.tr('hoursShort')} ${localDigits(context, '$m')} ${context.tr('minutesShort')}'
            : '${localDigits(context, '$m')} ${context.tr('minutesShort')}';
        countdown = context.tr('startsIn', {'t': t});
      }
      children.add(Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill('$dayLabel • ${weekdayLabel(context, n.start.weekday)}', color: Theme.of(context).colorScheme.primary),
        if (countdown != null) Pill(countdown, color: AppColors.goldText, icon: Icons.timer_outlined),
      ]));
      children.add(const SizedBox(height: 8));
      children.add(Text(context.pick(n.liturgy.nameAr, n.liturgy.nameEn),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)));
      children.add(const SizedBox(height: 4));
      children.add(TimeRangeText(n.liturgy.start, n.liturgy.end, large: true));
      children.add(const SizedBox(height: 6));
      children.add(IconLine(Icons.place_outlined, context.pick(n.liturgy.placeAr, n.liturgy.placeEn)));
      children.add(IconLine(Icons.people_outline, context.pick(n.liturgy.audienceAr, n.liturgy.audienceEn)));
      if (n.liturgy.sample) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr('timesPending'),
              style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w700, fontSize: 12)),
        ));
      }
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
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E0),
            borderRadius: BorderRadius.circular(14),
            border: const BorderDirectional(start: BorderSide(color: AppColors.alert, width: 5)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ItemImage(
              image: a.image,
              size: 48,
              circle: false,
              radius: 10,
              label: context.pick(a.titleAr, a.titleEn),
              placeholder: const Icon(Icons.campaign_rounded, color: AppColors.alert),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.pick(a.titleAr, a.titleEn),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.alert)),
                if (context.pick(a.bodyAr, a.bodyEn).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.pick(a.bodyAr, a.bodyEn), style: const TextStyle(height: 1.5)),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Theme.of(context).colorScheme.primary,
                  Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.15)!,
                ]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.goldLight, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  Text(context.tr('learnMore'),
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ]),
              ]),
            ),
          ]),
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
        foregroundColor: Colors.white,
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
const whatsappGreen = Color(0xFF157338);
const facebookBlue = Color(0xFF145DBF);
const youtubeRed = Color(0xFFD32F2F);
const instagramPink = Color(0xFFC13584);
