import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/rules.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import 'coptic_cross.dart';

const double kMaxContentWidth = 1100;

/// Scrollable page body: centred, width-capped content + footer.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Widget? header;
  const PageBody({super.key, required this.children, this.header});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return CustomScrollView(
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 20, pad, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ),
        ),
        const SliverFillRemaining(hasScrollBody: false, child: Align(alignment: Alignment.bottomCenter, child: Footer())),
      ],
    );
  }
}

/// Burgundy page banner with title + subtitle.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  const PageHeader({super.key, required this.title, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryDarkOf(context), primary],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.goldLight, size: 28),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: AppColors.goldLight)),
                      ),
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

class SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, color: AppColors.goldText, size: 22), const SizedBox(width: 8)],
          Flexible(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1.2, color: AppColors.gold.withValues(alpha: 0.4))),
          if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
        ],
      ),
    );
  }
}

/// Responsive grid of cards (1 column on phones, 2-3 on wider screens).
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 300, this.spacing = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minItemWidth).floor().clamp(1, 4);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// Pulsing grey block used for loading skeletons.
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = 10});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion (OS setting): no pulsing, a static placeholder instead.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE3CF),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0xFFEDE3CF), const Color(0xFFF7F0E1), _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A list of card-shaped skeletons.
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const SkeletonList({super.key, this.count = 3, this.itemHeight = 96});

  @override
  Widget build(BuildContext context) => ResponsiveGrid(
        children: List.generate(count, (_) => SkeletonBox(height: itemHeight, radius: 16)),
      );
}

class EmptyState extends StatelessWidget {
  final String? message;
  final IconData icon;
  const EmptyState({super.key, this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppColors.muted.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text(message ?? context.tr('noItems'),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );
}

class ErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const ErrorState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.alert),
            const SizedBox(height: 8),
            Text(context.tr('loadError'), style: const TextStyle(color: AppColors.alert)),
            if (onRetry != null)
              TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(context.tr('retry'))),
          ],
        ),
      );
}

/// Renders an AsyncValue with skeleton / error / empty states.
class AsyncSection<T> extends ConsumerWidget {
  final ProviderListenable<AsyncValue<T>> provider;
  final ProviderOrFamily? retry;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final bool Function(T data)? isEmpty;
  final String? emptyMessage;

  const AsyncSection({
    super.key,
    required this.provider,
    required this.builder,
    this.retry,
    this.loading,
    this.isEmpty,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(provider);
    return v.when(
      skipLoadingOnReload: true,
      data: (d) => (isEmpty?.call(d) ?? false) ? EmptyState(message: emptyMessage) : builder(context, d),
      loading: () => loading ?? const SkeletonList(),
      error: (e, _) => ErrorState(onRetry: retry == null ? null : () => ref.invalidate(retry!)),
    );
  }
}

/// Page-level notice shown above schedules whose entries are still
/// placeholders (sample: true) awaiting the church's confirmation.
class PendingConfirmationNote extends StatelessWidget {
  const PendingConfirmationNote({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0C36A)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.goldText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('timesPending'),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.goldText)),
              const SizedBox(height: 2),
              Text(context.tr('timesPendingHint'), style: const TextStyle(height: 1.5, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

class SampleBadge extends StatelessWidget {
  const SampleBadge({super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: context.tr('sampleData'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE0C36A)),
          ),
          child: Text(context.tr('sampleData'), style: const TextStyle(fontSize: 10, color: AppColors.goldText)),
        ),
      );
}

/// A title followed by the "sample data" badge. The badge moves under the
/// title on narrow screens / large text instead of overflowing (BUG-11).
class TitleWithBadge extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool sample;
  const TitleWithBadge(this.text, {super.key, this.style, this.sample = false});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(text, style: style), if (sample) const SampleBadge()],
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = AppColors.success, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          // Long labels (e.g. several active seasons) wrap/ellipsize instead
          // of overflowing narrow cards.
          Flexible(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
      );
}

class IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle? style;
  const IconLine(this.icon, this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 16, color: AppColors.muted)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style ?? const TextStyle(color: AppColors.ink, height: 1.4))),
      ]),
    );
  }
}

/// "06:30 AM – 08:30 AM" plus Arabic-digit version underneath (spec: both
/// digit systems). Shown in the current language first.
class TimeRangeText extends StatelessWidget {
  final String start, end;
  final bool large;
  const TimeRangeText(this.start, this.end, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final latin = formatRangeLatin(start, end);
    final arabic = formatRangeArabic(start, end);
    final primary = context.isAr ? arabic : latin;
    final secondary = context.isAr ? latin : arabic;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(primary,
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: large ? 22 : 16,
              color: Theme.of(context).colorScheme.primary,
              height: 1.3)),
      // The secondary line is Latin in Arabic mode and Arabic in English mode:
      // give it its own script's base direction.
      Directionality(
        textDirection: context.isAr ? TextDirection.ltr : TextDirection.rtl,
        child: Text(secondary, style: TextStyle(fontSize: large ? 14 : 12, color: AppColors.muted)),
      ),
    ]);
  }
}

String weekdayLabel(BuildContext context, int? wd) => weekdayName(wd, arabic: context.isAr);

/// Localised digits for small numbers in running text.
String localDigits(BuildContext context, String s) => context.isAr ? toArabicDigits(s) : s;

class Footer extends ConsumerWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final servingSeed = ref.watch(repositoryProvider).servingSeed;
    final year = DateTime.now().year;
    final features = ref.watch(featuresProvider);
    final links = <(String, String)>[
      ('massSchedule', '/mass-schedule'),
      ('clinics', '/clinics'),
      ('education', '/church-education'),
      ('contact', '/contact'),
    ].where((l) => features.routeEnabled(l.$2)).toList();
    return Container(
      width: double.infinity,
      color: primaryDarkOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const ChurchSeal(size: 34),
              const SizedBox(width: 10),
              Flexible(
                child: Text(s == null ? context.tr('appName') : context.pick(s.nameAr, s.nameEn),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ]),
            if (s != null && features.enabled(Sections.contactInfo))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.pick(s.addressAr, s.addressEn),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.goldLight, fontSize: 13)),
              ),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
              for (final l in links)
                TextButton(
                  onPressed: () => context.go(l.$2),
                  child: Text(context.tr(l.$1), style: const TextStyle(color: Colors.white70)),
                ),
            ]),
            const SizedBox(height: 6),
            Text('© ${localDigits(context, '$year')} — ${context.tr('rights')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ValueListenableBuilder<bool>(
              valueListenable: servingSeed,
              builder: (context, onSeed, _) => onSeed
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(context.tr('offlineData'),
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}
