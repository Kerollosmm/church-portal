import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/cairo_time.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../domain/schedule.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import 'common.dart';

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
            child: Icon(_icon, color: AppColors.burgundy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dayText.isNotEmpty)
                Text(dayText,
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12)),
              Text(context.pick(l.nameAr, l.nameEn),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
          BoxShadow(color: AppColors.burgundy.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.access_time_filled_rounded, color: AppColors.burgundy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.tr('nextMass'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.burgundy)),
          ),
          TextButton(onPressed: () => context.go('/mass-schedule'), child: Text(context.tr('fullSchedule'))),
        ]),
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
          color: AppColors.burgundy,
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
        Pill('$dayLabel • ${weekdayLabel(context, n.start.weekday)}', color: AppColors.burgundy),
        if (countdown != null) Pill(countdown, color: AppColors.gold.withValues(alpha: 1), icon: Icons.timer_outlined),
      ]));
      children.add(const SizedBox(height: 8));
      children.add(Text(context.pick(n.liturgy.nameAr, n.liturgy.nameEn),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)));
      children.add(const SizedBox(height: 4));
      children.add(TimeRangeText(n.liturgy.start, n.liturgy.end, large: true));
      children.add(const SizedBox(height: 6));
      children.add(IconLine(Icons.place_outlined, context.pick(n.liturgy.placeAr, n.liturgy.placeEn)));
      children.add(IconLine(Icons.people_outline, context.pick(n.liturgy.audienceAr, n.liturgy.audienceEn)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// Urgent alert banner — renders nothing unless an alert is visible now.
class AlertBanner extends ConsumerWidget {
  const AlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).value;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (alerts == null) return const SizedBox.shrink();
    final visible = visibleAlerts(alerts, now);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final a in visible.take(2))
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
            const Icon(Icons.campaign_rounded, color: AppColors.alert),
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
              ]),
            ),
            if (a.link != null && a.link!.isNotEmpty)
              TextButton(
                onPressed: () => a.link!.startsWith('/') ? context.go(a.link!) : openUrl(a.link!),
                child: Text(context.tr('learnMore')),
              ),
          ]),
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
                gradient: const LinearGradient(colors: [AppColors.burgundy, AppColors.burgundyLight]),
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
                      style: const TextStyle(color: AppColors.burgundy, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppColors.burgundy),
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
  const ActionChipButton({super.key, required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
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
}

const whatsappGreen = Color(0xFF1FA855);
const facebookBlue = Color(0xFF1877F2);
const youtubeRed = Color(0xFFD32F2F);
