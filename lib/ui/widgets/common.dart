import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import 'coptic_cross.dart';
import 'ornaments.dart';

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
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Align(alignment: Alignment.bottomCenter, child: Footer()),
        ),
      ],
    );
  }
}

/// Standard inner-page header ("Iconostasis"): a plaster band with the church
/// short name as a kicker, the title in the display face (primary colour),
/// the subtitle, a faint arch watermark at the end edge and the interlace
/// band underneath. Same anatomy on every inner page.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Kept for API compatibility; the header no longer shows a section icon
  /// (the arch watermark and kicker carry the identity).
  final IconData? icon;
  const PageHeader({super.key, required this.title, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final pad = w < 600 ? 16.0 : (wide ? 40.0 : 24.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: AppColors.parchment,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              PositionedDirectional(
                end: wide ? 60 : 16,
                bottom: wide ? -40 : -36,
                child: ArchWatermark(width: wide ? 200 : 120, height: wide ? 240 : 150),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, wide ? 36 : 20, pad, wide ? 32 : 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              context.tr('appShort'),
                              style: const TextStyle(
                                color: AppColors.goldText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: displayStyle(context, size: wide ? 34 : 26, color: primary),
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 680),
                                child: Text(subtitle!, style: const TextStyle(color: AppColors.muted, height: 1.65)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const InterlaceBand(),
      ],
    );
  }
}

/// [PageHeader] of a customizable public page ([CustomizablePages]): the
/// admin's title / subtitle for the current language
/// (`settings/features.pageHeaders.<pageKey>`) replace the built-in ones;
/// an empty override keeps the built-in text.
class CustomizablePageHeader extends ConsumerWidget {
  final String pageKey;
  final String title;
  final String? subtitle;
  final IconData? icon;
  const CustomizablePageHeader({super.key, required this.pageKey, required this.title, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(featuresProvider.select((f) => f.pageHeader(pageKey)));
    // Current language only: the built-in title exists in both languages, so
    // an Arabic-only override never replaces the English title with Arabic.
    String own(String ar, String en) => (context.isAr ? ar : en).trim();
    final t = own(c.titleAr, c.titleEn);
    final st = own(c.subtitleAr, c.subtitleEn);
    return PageHeader(title: t.isNotEmpty ? t : title, subtitle: st.isNotEmpty ? st : subtitle, icon: icon);
  }
}

/// Optional admin intro note at the top of a customizable page (nothing
/// when `introAr` / `introEn` are empty).
class PageIntro extends ConsumerWidget {
  final String pageKey;
  const PageIntro({super.key, required this.pageKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(featuresProvider.select((f) => f.pageHeader(pageKey)));
    final text = context.pick(c.introAr.trim(), c.introEn.trim());
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('pageIntro'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_outlined, color: AppColors.goldText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(height: 1.7, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

/// Section title on a "register" line: Coptic-cross medallion, the title in
/// the display face (primary colour), then a gold-leaf rule to the end edge.
class SectionTitle extends StatelessWidget {
  final String text;

  /// Kept for API compatibility: the medallion cross replaces section icons.
  final IconData? icon;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Padding(
      padding: EdgeInsets.only(top: wide ? 32 : 24, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: CopticCross(size: wide ? 24 : 20, color: primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: displayStyle(context, size: wide ? 26 : 21, color: primary, height: 1.35),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: AppColors.gold)),
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
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minItemWidth).floor().clamp(1, 4);
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
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
        decoration: BoxDecoration(color: const Color(0xFFEDE3CF), borderRadius: BorderRadius.circular(widget.radius)),
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
  Widget build(BuildContext context) =>
      ResponsiveGrid(children: List.generate(count, (_) => SkeletonBox(height: itemHeight, radius: 16)));
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
        Text(
          message ?? context.tr('noItems'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
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
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0xFFE0C36A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.goldText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('timesPending'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.goldText),
              ),
              const SizedBox(height: 2),
              Text(context.tr('timesPendingHint'), style: const TextStyle(height: 1.5, fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
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
    children: [
      Text(text, style: style),
      if (sample) const SampleBadge(),
    ],
  );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  /// Lines before the label is ellipsized (null = wrap freely, for labels
  /// that list content shown nowhere else, e.g. the active seasons).
  final int? maxLines;
  const Pill(this.text, {super.key, this.color = AppColors.success, this.icon, this.maxLines = 2});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        // Long labels (e.g. several active seasons) wrap/ellipsize instead
        // of overflowing narrow cards.
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 16, color: AppColors.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: style ?? const TextStyle(color: AppColors.ink, height: 1.4)),
          ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: large ? 22 : 16,
            color: Theme.of(context).colorScheme.primary,
            height: 1.3,
          ),
        ),
        // The secondary line is Latin in Arabic mode and Arabic in English mode:
        // give it its own script's base direction.
        Directionality(
          textDirection: context.isAr ? TextDirection.ltr : TextDirection.rtl,
          child: Text(
            secondary,
            style: TextStyle(fontSize: large ? 14 : 12, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

String weekdayLabel(BuildContext context, int? wd) => weekdayName(wd, arabic: context.isAr);

/// Localised digits for small numbers in running text.
String localDigits(BuildContext context, String s) => context.isAr ? toArabicDigits(s) : s;

/// Site footer (FR-G-04): church name and address, quick phone numbers,
/// official social icons, quick links and an optional admin note, each
/// switchable in `settings/features.footer` (and hidden with its section).
class Footer extends ConsumerWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final servingSeed = ref.watch(repositoryProvider).servingSeed;
    final year = DateTime.now().year;
    final features = ref.watch(featuresProvider);
    // Until settings/features arrives the defaults are "everything on": wait
    // before showing phones / social links an admin may have switched off.
    final ready = ref.watch(featuresReadyProvider);
    final footer = features.footer;
    final links = <(String, String)>[
      ('massSchedule', '/mass-schedule'),
      ('clinics', '/clinics'),
      ('education', '/church-education'),
      ('contact', '/contact'),
    ].where((l) => features.routeEnabled(l.$2)).toList();
    final phones = ready && s != null && footer.showPhones && features.enabled(Sections.contactInfo)
        ? s.phones.where((p) => p.number.trim().isNotEmpty).toList()
        : const <PhoneEntry>[];
    final socials = <(String, IconData, String, VoidCallback)>[
      if (ready && s != null && footer.showSocials && features.enabled(Sections.socials)) ...[
        if (s.whatsappChannel.isNotEmpty)
          ('whatsappChannel', Icons.campaign_rounded, context.tr('whatsappChannel'), () => openUrl(s.whatsappChannel)),
        if (s.whatsapp.isNotEmpty)
          ('whatsapp', Icons.chat_rounded, context.tr('whatsapp'), () => openWhatsApp(s.whatsapp)),
        if (s.facebook.isNotEmpty) ('facebook', Icons.facebook, context.tr('facebook'), () => openUrl(s.facebook)),
        if (s.youtube.isNotEmpty) ('youtube', Icons.live_tv_rounded, context.tr('youtube'), () => openUrl(s.youtube)),
        if (s.instagram.isNotEmpty)
          ('instagram', Icons.photo_camera_rounded, context.tr('instagram'), () => openUrl(s.instagram)),
      ],
    ];
    final note = context.pick(footer.noteAr.trim(), footer.noteEn.trim());
    final screen = MediaQuery.sizeOf(context).width;
    final side = screen > kMaxContentWidth ? (screen - kMaxContentWidth) / 2 : 0.0;
    final wide = screen >= 900;
    final pad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : (wide ? 40.0 : 24.0);
    const heading = TextStyle(
      fontFamily: AppFonts.naskh,
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: AppColors.goldLight,
    );
    final name = s == null ? context.tr('appName') : context.pick(s.nameAr, s.nameEn);

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ChurchSeal(size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: AppFonts.naskh,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  Text(context.tr('denomination'), style: const TextStyle(color: AppColors.goldLight, fontSize: 13)),
                  if (s != null && features.enabled(Sections.contactInfo))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        context.pick(s.addressAr, s.addressEn),
                        style: const TextStyle(color: Color(0xFFD9CCB2), fontSize: 13, height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (socials.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final x in socials)
                  SizedBox.square(
                    dimension: 48,
                    child: IconButton(
                      key: Key('footerSocial-${x.$1}'),
                      tooltip: x.$3,
                      onPressed: x.$4,
                      // minimumSize (not `constraints`): keeps the intrinsic height
                      // equal to the laid-out 48 dp inside SliverFillRemaining.
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        side: const BorderSide(color: Color(0xFF5A4630)),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
                      ),
                      icon: Icon(x.$2, color: AppColors.goldLight, size: 20),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    final contact = phones.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('getInTouch'), style: heading),
              const SizedBox(height: 4),
              Semantics(
                container: true,
                label: context.tr('footerPhones'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in phones)
                      // Fixed 48 dp rows: exact intrinsic height inside SliverFillRemaining.
                      SizedBox(
                        height: 48,
                        child: TextButton.icon(
                          key: Key('footerPhone-${p.number.trim()}'),
                          onPressed: () => callPhone(p.number),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                          icon: const Icon(Icons.call, size: 18, color: AppColors.goldLight),
                          label: Text(
                            p.number.trim(),
                            // Digits read left-to-right in Arabic too.
                            textDirection: TextDirection.ltr,
                            semanticsLabel:
                                '${context.tr('call')} ${context.pick(p.labelAr, p.labelEn)} ${p.number.trim()}'.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

    final quick = !(footer.showQuickLinks && links.isNotEmpty)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('quickLinks'), style: heading),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final buttons = [
                    for (final l in links)
                      SizedBox(
                        height: 48,
                        child: TextButton(
                          onPressed: () => context.go(l.$2),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                          child: Text(
                            context.tr(l.$1),
                            style: const TextStyle(color: Color(0xFFE9DFC9), fontWeight: FontWeight.w400),
                          ),
                        ),
                      ),
                  ];
                  // A Column on wide screens (Wrap's vertical intrinsic height is
                  // unreliable inside SliverFillRemaining), a Wrap on phones.
                  return wide
                      ? Column(
                          key: const Key('footerQuickLinks'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: buttons,
                        )
                      : Wrap(key: const Key('footerQuickLinks'), spacing: 4, children: buttons);
                },
              ),
            ],
          );

    final columns = <Widget>[identity, ?contact, ?quick];
    return Container(
      width: double.infinity,
      color: AppColors.night,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const InterlaceBand.dark(),
          // Centred by padding, not ConstrainedBox(maxWidth): the footer sits in
          // SliverFillRemaining, which sizes it from its intrinsic height, and
          // ConstrainedBox would measure that at the full (wider) width.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 40 : 28, pad, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < columns.length; i++) ...[
                          if (i > 0) const SizedBox(width: 32),
                          Expanded(flex: i == 0 ? 13 : 10, child: columns[i]),
                        ],
                      ],
                    )
                  else
                    for (var i = 0; i < columns.length; i++) ...[if (i > 0) const SizedBox(height: 20), columns[i]],
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        note,
                        key: const Key('footerNote'),
                        style: const TextStyle(color: Color(0xFFD9CCB2), fontSize: 13, height: 1.6),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 1, child: ColoredBox(color: Color(0xFF3A2A1C))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        '© ${localDigits(context, '$year')} — ${context.tr('rights')}',
                        style: const TextStyle(color: Color(0xFFBFB096), fontSize: 12),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: servingSeed,
                        builder: (context, onSeed, _) => onSeed
                            ? Text(
                                context.tr('offlineData'),
                                style: const TextStyle(color: Color(0xFFBFB096), fontSize: 12),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
