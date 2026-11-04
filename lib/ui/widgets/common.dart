import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'golden.dart';

/// Max width of page content (cards grid, text); wider screens centre it.
const double kMaxContentWidth = 1200;

/// Scrollable page body: centred, width-capped content + footer. Each
/// section fades and rises in the first time it scrolls into view (static
/// under reduced motion).
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final c in children) Reveal(child: c)],
                ),
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

/// Standard inner-page header ("Golden hour"): the golden-hour painting of
/// the church in the clouds (slow drift + light rays, still under reduced
/// motion), a cream scrim, the calligraphic accent word above the heavy
/// maroon title, and the subtitle on a pill ribbon. Same anatomy on every
/// inner page. [portrait] (a saint's icon in a halo) and [backdrop] (e.g. the
/// Nile for saints) let detail pages vary it.
class PageHeader extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final String? accent;

  /// Kept for API compatibility (section icons are not shown in the header).
  final IconData? icon;
  final Widget? portrait;
  final String backdrop;
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.portrait,
    this.backdrop = ArtAssets.heroWide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final phone = w < 600;
    final pad = phone ? 16.0 : (wide ? 40.0 : 24.0);
    final motion = ref.watch(featuresProvider.select((f) => f.heroMotion));
    final sub = subtitle?.trim() ?? '';
    return Stack(
      children: [
        Positioned.fill(
          child: HeroStage(
            image: backdrop == ArtAssets.heroWide && phone ? ArtAssets.heroWideSmall : backdrop,
            alignment: backdrop == ArtAssets.heroWide ? const Alignment(0, -0.35) : Alignment.center,
            motion: motion,
            rays: backdrop == ArtAssets.heroWide ? 1 : 0.6,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Padding(
              // Top room for the seal tab hanging from the app bar.
              padding: EdgeInsets.fromLTRB(pad, wide ? 44 : 40, pad, wide ? 52 : 36),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (portrait != null) ...[portrait!, const SizedBox(height: 14)],
                    TextScrim(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                        child: PosterHeading(title, accent: accent, size: wide ? 54 : (phone ? 34 : 44), glow: true),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: TitleRibbon(sub),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [PageHeader] of a customizable public page ([CustomizablePages]): the
/// admin's title / subtitle for the current language
/// (`settings/features.pageHeaders.<pageKey>`) replace the built-in ones;
/// an empty override keeps the built-in text. The calligraphic accent word
/// is the page's own (`accent_<pageKey>`).
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
    return PageHeader(
      title: t.isNotEmpty ? t : title,
      subtitle: st.isNotEmpty ? st : subtitle,
      icon: icon,
      accent: context.trOrNull('accent_$pageKey'),
    );
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
    return Padding(
      key: const Key('pageIntro'),
      padding: const EdgeInsets.only(bottom: 12),
      child: WarmPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign_outlined, color: context.pal.goldText),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(height: 1.75, color: context.pal.ink))),
          ],
        ),
      ),
    );
  }
}

/// Poster-style section title: optional calligraphic [accent] word above the
/// heavy title (primary colour), a soft sepia rule, then [trailing] (e.g. a
/// "see all" link) underneath. Centred like the posters.
class SectionTitle extends StatelessWidget {
  final String text;

  /// Kept for API compatibility (no section icons in the poster style).
  final IconData? icon;
  final Widget? trailing;
  final String? accent;
  const SectionTitle(this.text, {super.key, this.icon, this.trailing, this.accent});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final primary = context.pal.primary;
    return Padding(
      padding: EdgeInsets.only(top: wide ? 44 : 30, bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent != null)
            ExcludeSemantics(
              child: Text(accent!, textAlign: TextAlign.center, style: AppFonts.script(size: wide ? 30 : 24, height: 1.1, color: context.pal.script)),
            ),
          Semantics(
            header: true,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: displayStyle(context, size: wide ? 38 : 28, color: primary, height: 1.3),
            ),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Container(
              width: 170,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(99)),
                gradient: LinearGradient(colors: [
                  context.pal.ribbon.withValues(alpha: 0),
                  context.pal.ribbon.withValues(alpha: 0.7),
                  context.pal.ribbon.withValues(alpha: 0),
                ]), // decorative
              ),
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(top: 4), child: trailing!),
        ],
      ),
    );
  }
}

/// Columns for a grid [width] wide: phone 1, tablet 2, desktop 3 (the
/// breakpoints are on the grid's own width, so a grid inside a narrower
/// panel follows its panel), capped at [maxColumns].
int gridColumns(double width, {int maxColumns = 3}) {
  final cols = width < 560 ? 1 : (width < 900 ? 2 : 3);
  return cols.clamp(1, maxColumns);
}

/// Responsive grid of cards: 1 column on phones, 2 on tablets, 3 on desktop
/// (see [gridColumns]). Cards keep their own height (they size to their
/// content: nothing is stretched to fill a row) and start at the reading
/// edge (right in Arabic). [minItemWidth] only lowers the column count when
/// cards would get narrower than it (e.g. wide saint panels).
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 260,
    this.spacing = Space.grid,
    this.maxColumns = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        var cols = gridColumns(c.maxWidth, maxColumns: maxColumns);
        while (cols > 1 && (c.maxWidth - spacing * (cols - 1)) / cols < minItemWidth) {
          cols--;
        }
        final w = ((c.maxWidth - spacing * (cols - 1)) / cols).floorToDouble();
        // Full width even under loose constraints, so runs start at the
        // reading edge (right in Arabic) instead of shrink-wrapping left.
        return SizedBox(
          width: c.maxWidth.isFinite ? c.maxWidth : null,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [for (final ch in children) SizedBox(width: w, child: ch)],
          ),
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
        decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(widget.radius)),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(context.pal.surfaceAlt, context.pal.surface, _c.value),
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
        Icon(icon, size: 44, color: context.pal.muted.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Text(
          message ?? context.tr('noItems'),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.pal.muted),
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
        Icon(Icons.cloud_off_rounded, size: 44, color: context.pal.alert),
        const SizedBox(height: 8),
        Text(context.tr('loadError'), style: TextStyle(color: context.pal.alert)),
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
      color: context.pal.notice,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.pal.noticeEdge),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: context.pal.goldText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('timesPending'),
                style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.goldText),
              ),
              const SizedBox(height: 2),
              Text(context.tr('timesPendingHint'), style: TextStyle(height: 1.5, fontSize: 13, color: context.pal.noticeInk)),
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
        color: context.pal.notice,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.pal.noticeEdge),
      ),
      child: Text(context.tr('sampleData'), style: TextStyle(fontSize: 10, color: context.pal.goldText)),
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
  /// null = the theme's success green.
  final Color? color;
  final IconData? icon;

  /// Lines before the label is ellipsized (null = wrap freely, for labels
  /// that list content shown nowhere else, e.g. the active seasons).
  final int? maxLines;
  const Pill(this.text, {super.key, this.color, this.icon, this.maxLines = 2});

  @override
  Widget build(BuildContext context) {
    // The tint sits on a panel or on the page: the label keeps 4.5:1 on both
    // (a status green is lightened on a dark theme).
    final pal = context.pal;
    final color = this.color ?? pal.success;
    final fg = readableOn(color, [
      Color.alphaBlend(color.withValues(alpha: 0.12), pal.surface),
      Color.alphaBlend(color.withValues(alpha: 0.12), pal.background),
    ]);
    return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        // Long labels (e.g. several active seasons) wrap/ellipsize instead
        // of overflowing narrow cards.
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    ),
  );
  }
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
            child: Icon(icon, size: 16, color: context.pal.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: style ?? TextStyle(color: context.pal.ink, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// "٠٦:٣٠ ص – ٠٨:٣٠ ص" with the Latin-digit version underneath in Arabic
/// (spec: both digit systems for Arabic readers); Latin digits only on the
/// English site (live check 4 Nov 2026, ADR-038: Arabic digits there read as
/// untranslated text).
class TimeRangeText extends StatelessWidget {
  final String start, end;
  final bool large;
  const TimeRangeText(this.start, this.end, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    // No time set: nothing (no empty line reserving space).
    if (start.trim().isEmpty) return const SizedBox.shrink();
    final latin = formatRangeLatin(start, end);
    final primary = context.isAr ? formatRangeArabic(start, end) : latin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          style: displayStyle(context, size: large ? 28 : 21, color: context.pal.primary, height: 1.3),
        ),
        // Arabic mode: the Latin secondary line keeps its own script's base
        // direction (BUG-10).
        if (context.isAr)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              latin,
              style: TextStyle(fontSize: large ? 14 : 12, color: context.pal.muted),
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
/// "Golden hour": a warm panel over the church in the mist, then the
/// posters' signature line with the Facebook / WhatsApp icons.
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
    final primary = context.pal.primary;
    final links = <(String, String)>[
      ('massSchedule', '/mass-schedule'),
      ('clinics', '/clinics'),
      ('education', '/church-education'),
      ('contact', '/contact'),
      // Clinics is off on the live site: never offer it before the switches
      // have arrived (same rule as the Services menu, app_shell.dart).
    ].where((l) => features.routeEnabled(l.$2) && (ready || l.$2 != '/clinics')).toList();
    final phones = ready && s != null && footer.showPhones && features.enabled(Sections.contactInfo)
        ? s.phones.where((p) => p.number.trim().isNotEmpty).toList()
        : const <PhoneEntry>[];
    final socialsOn = ready && s != null && footer.showSocials && features.enabled(Sections.socials);
    final socials = <(String, IconData, String, VoidCallback)>[
      if (socialsOn) ...[
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
    // The signature line carries Facebook and WhatsApp (as on the posters).
    final sigIcons = <(String, IconData, String, VoidCallback)>[
      if (socialsOn) ...[
        if (s.facebook.isNotEmpty) ('facebook', Icons.facebook, context.tr('facebook'), () => openUrl(s.facebook)),
        if (s.whatsappChannel.isNotEmpty)
          ('whatsapp', Icons.chat_rounded, context.tr('whatsappChannel'), () => openUrl(s.whatsappChannel))
        else if (s.whatsapp.isNotEmpty)
          ('whatsapp', Icons.chat_rounded, context.tr('whatsapp'), () => openWhatsApp(s.whatsapp)),
      ],
    ];
    final note = context.pick(footer.noteAr.trim(), footer.noteEn.trim());
    final screen = MediaQuery.sizeOf(context).width;
    final side = screen > kMaxContentWidth ? (screen - kMaxContentWidth) / 2 : 0.0;
    final wide = screen >= 900;
    final pad = screen < 600 ? 16.0 : (wide ? 40.0 : 24.0);
    final heading = displayStyle(context, size: 19, color: primary, height: 1.4);
    final name = s == null ? context.tr('appName') : context.pick(s.nameAr, s.nameEn);

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ChurchSeal(size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: displayStyle(context, size: 18, color: primary, height: 1.45)),
                  Text(context.tr('denomination'), style: TextStyle(color: context.pal.goldText, fontSize: 13)),
                  if (s != null && features.enabled(Sections.contactInfo))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        context.pick(s.addressAr, s.addressEn),
                        style: TextStyle(color: context.pal.muted, fontSize: 13, height: 1.6),
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
                        backgroundColor: context.pal.bar,
                      ),
                      icon: Icon(x.$2, color: context.pal.onBarAccent, size: 20),
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
                          icon: Icon(Icons.call, size: 18, color: primary),
                          label: Text(
                            p.number.trim(),
                            // Digits read left-to-right in Arabic too.
                            textDirection: TextDirection.ltr,
                            semanticsLabel:
                                '${context.tr('call')} ${context.pick(p.labelAr, p.labelEn)} ${p.number.trim()}'.trim(),
                            style: TextStyle(
                              color: context.pal.ink,
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
                            style: TextStyle(color: context.pal.ink, fontWeight: FontWeight.w400),
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
    final signature = Text(
      context.tr('footerSignature'),
      key: const Key('footerSignature'),
      textAlign: TextAlign.center,
      style: displayStyle(context, size: wide ? 20 : 17, color: context.pal.primaryDeep, height: 1.5),
    );
    final sigButtons = [
      for (final x in sigIcons)
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: Key('footerSig-${x.$1}'),
            tooltip: x.$3,
            onPressed: x.$4,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
              backgroundColor: context.pal.bar,
            ),
            icon: Icon(x.$2, color: context.pal.onBar, size: 18),
          ),
        ),
    ];

    return Stack(
      key: const Key('footerStage'),
      children: [
        // The church in the mist behind the footer (decorative, positioned:
        // ignored by the intrinsic height SliverFillRemaining measures).
        Positioned.fill(
          child: ExcludeSemantics(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xFF000000)], // palette-exempt: alpha mask, not a colour
                stops: [0.05, 0.5],
              ).createShader(r),
              child: sceneArt(
                context,
                Image.asset(
                  wide ? ArtAssets.heroWide : ArtAssets.heroWideSmall,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, 0.75),
                ),
              ),
            ),
          ),
        ),
        // Centred by padding, not ConstrainedBox(maxWidth): the footer sits in
        // SliverFillRemaining, which sizes it from its intrinsic height, and
        // ConstrainedBox would measure that at the full (wider) width.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? 80 : 56, pad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const Key('footerPanel'),
                  padding: EdgeInsets.all(wide ? 28 : 18),
                  decoration: BoxDecoration(
                    color: context.pal.panel,
                    borderRadius: BorderRadius.circular(kPanelRadius),
                    border: Border.all(color: context.pal.ornamentLine),
                    boxShadow: context.pal.panelShadow,
                  ),
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
                        for (var i = 0; i < columns.length; i++) ...[if (i > 0) const SizedBox(height: 18), columns[i]],
                      if (note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            note,
                            key: const Key('footerNote'),
                            style: TextStyle(color: context.pal.muted, fontSize: 13, height: 1.6),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // The posters' signature line and the legal line, on a soft
                // cream band (text never sits on the bare painting).
                Container(
                  key: const Key('footerSignatureBand'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.pal.background.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wide)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ...sigButtons,
                            if (sigButtons.isNotEmpty) const SizedBox(width: 8),
                            Flexible(child: signature),
                          ],
                        )
                      else ...[
                        if (sigButtons.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.center, children: sigButtons),
                        signature,
                      ],
                      const SizedBox(height: 2),
                      Text(
                        '© ${localDigits(context, '$year')} — ${context.tr('rights')}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.pal.muted, fontSize: 12.5),
                      ),
                      SteadySeedNote(
                        servingSeed: servingSeed,
                        // Live Firestore: only a lasting fallback is worth a
                        // note (a stream briefly on the seed during a cold
                        // start made it flash for 1-2 s, PR #30 live check).
                        delay: ref.watch(repositoryProvider).isLive ? SteadySeedNote.liveDelay : Duration.zero,
                        child: Text(
                          context.tr('offlineData'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.pal.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows [child] once [servingSeed] has stayed true for [delay] (ADR-039:
/// the footer's "bundled content" note no longer flashes while a stream
/// sits on the seed for a second or two during a cold start).
class SteadySeedNote extends StatefulWidget {
  final ValueListenable<bool> servingSeed;
  final Duration delay;
  final Widget child;
  const SteadySeedNote({super.key, required this.servingSeed, required this.delay, required this.child});

  static const liveDelay = Duration(seconds: 4);

  @override
  State<SteadySeedNote> createState() => _SteadySeedNoteState();
}

class _SteadySeedNoteState extends State<SteadySeedNote> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.servingSeed.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(covariant SteadySeedNote old) {
    super.didUpdateWidget(old);
    if (old.servingSeed != widget.servingSeed) {
      old.servingSeed.removeListener(_update);
      widget.servingSeed.addListener(_update);
      _update();
    }
  }

  void _update() {
    final on = widget.servingSeed.value;
    if (!on) {
      _timer?.cancel();
      _timer = null;
      if (_shown && mounted) setState(() => _shown = false);
      return;
    }
    if (_shown || _timer != null) return;
    if (widget.delay == Duration.zero) {
      if (mounted) setState(() => _shown = true);
      return;
    }
    _timer = Timer(widget.delay, () {
      _timer = null;
      if (mounted && widget.servingSeed.value) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.servingSeed.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shown ? widget.child : const SizedBox.shrink();
}
