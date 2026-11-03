import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/daily_verse.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/item_image.dart';
import '../widgets/map_embed.dart';
import '../widgets/golden.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final features = ref.watch(featuresProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final blocks = features.visibleHomeBlocks;

    final children = <Widget>[
      // Verse of the day: right under the hero (admin switch, not an
      // orderable home block).
      const KeyedSubtree(key: ValueKey('home-dailyVerse'), child: DailyVerseCard()),
    ];
    // The patrons teaser (not admin-orderable yet: a new home block needs a
    // settings/features rules change) sits before the first "discover" block.
    var patronsPlaced = false;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (!patronsPlaced && (b == HomeBlocks.milestones || b == HomeBlocks.directory || b == HomeBlocks.map)) {
        children.add(const KeyedSubtree(key: ValueKey('home-patrons'), child: _PatronsTeaser()));
        patronsPlaced = true;
      }
      final next = i + 1 < blocks.length ? blocks[i + 1] : null;
      // On wide screens the next-liturgy card and the phones card share a row
      // when they are adjacent.
      if (wide &&
          ((b == HomeBlocks.nextMass && next == HomeBlocks.quickContacts) ||
              (b == HomeBlocks.quickContacts && next == HomeBlocks.nextMass))) {
        final first = b == HomeBlocks.nextMass;
        children.add(Padding(
          key: const ValueKey('home-nextMass+quickContacts'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: first ? 3 : 2, child: first ? const NextMassCard() : const _QuickContacts()),
            const SizedBox(width: 16),
            Expanded(flex: first ? 2 : 3, child: first ? const _QuickContacts() : const NextMassCard()),
          ]),
        ));
        i++;
        continue;
      }
      children.add(KeyedSubtree(key: ValueKey('home-$b'), child: _block(context, ref, b, settings.value, features)));
    }

    if (!patronsPlaced) children.add(const KeyedSubtree(key: ValueKey('home-patrons'), child: _PatronsTeaser()));
    return PageBody(
      header: _Hero(settings: settings.value, features: features),
      children: children,
    );
  }

  Widget _block(BuildContext context, WidgetRef ref, String b, ChurchSettings? s, FeatureSettings f) {
    switch (b) {
      case HomeBlocks.banner:
        return _AnnouncementBanner(features: f);
      case HomeBlocks.alerts:
        return const AlertBanner();
      case HomeBlocks.nextMass:
        return const Padding(padding: EdgeInsets.only(bottom: 12), child: NextMassCard());
      case HomeBlocks.quickContacts:
        return const Padding(padding: EdgeInsets.only(bottom: 12), child: _QuickContacts());
      case HomeBlocks.milestones:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(context.tr('ourStory'), accent: context.tr('accentStory')),
          AsyncSection<List<Milestone>>(
            provider: milestonesProvider,
            retry: milestonesProvider,
            isEmpty: (d) => d.isEmpty,
            loading: const SkeletonList(count: 4, itemHeight: 120),
            builder: (context, items) => ResponsiveGrid(
              children: [for (final m in items) _MilestoneCard(m)],
            ),
          ),
        ]);
      case HomeBlocks.directory:
        final showAsk = ref.watch(assistantVisibleProvider);
        final cards = [
          for (final d in _directory)
            if (f.routeEnabled(d.path))
              DirectoryCard(
                  icon: d.icon,
                  title: context.tr(d.title),
                  subtitle: context.tr(d.subtitle),
                  onTap: () => context.go(d.path)),
          if (showAsk)
            DirectoryCard(
                icon: Icons.auto_awesome_rounded,
                title: context.tr('ask'),
                subtitle: context.tr('dir_ask'),
                onTap: () => context.go('/ask')),
        ];
        if (cards.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(context.tr('directory'), accent: context.tr('accentServices')),
          ResponsiveGrid(children: cards),
        ]);
      case HomeBlocks.map:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(context.tr('location'), accent: context.tr('accentLocation')),
          if (s != null) ChurchMap(settings: s) else const SkeletonBox(height: 360, radius: 16),
        ]);
    }
    return const SizedBox.shrink();
  }
}

class _DirEntry {
  final IconData icon;
  final String title, subtitle, path;
  const _DirEntry(this.icon, this.title, this.subtitle, this.path);
}

const _directory = [
  _DirEntry(Icons.access_time_filled_rounded, 'massSchedule', 'dir_mass', '/mass-schedule'),
  _DirEntry(Icons.local_hospital_rounded, 'clinics', 'dir_clinics', '/clinics'),
  _DirEntry(Icons.school_rounded, 'education', 'dir_edu', '/church-education'),
  _DirEntry(Icons.groups_rounded, 'activities', 'dir_act', '/church-activities'),
  _DirEntry(Icons.volunteer_activism_rounded, 'publicServices', 'dir_services', '/public-services'),
  _DirEntry(Icons.church_rounded, 'about', 'dir_about', '/about'),
  _DirEntry(Icons.call_rounded, 'contact', 'dir_contact', '/contact'),
];

/// Admin-written announcement (settings/features banner fields).
class _AnnouncementBanner extends StatelessWidget {
  final FeatureSettings features;
  const _AnnouncementBanner({required this.features});

  @override
  Widget build(BuildContext context) {
    final text = context.pick(features.bannerAr, features.bannerEn);
    var link = features.bannerLink.trim();
    final internal = link.startsWith('/') && !link.startsWith('//');
    // A link to a switched-off section would only open "not available".
    if (internal && !features.routeEnabled(Uri.tryParse(link)?.path ?? link)) link = '';
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Icon(Icons.campaign_outlined, color: primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6))),
        if (link.isNotEmpty)
          TextButton(
            onPressed: () => link.startsWith('/') && !link.startsWith('//') ? context.go(link) : openUrl(link),
            child: Text(context.tr('learnMore')),
          ),
      ]),
    );
  }
}

/// The golden-hour hero (the posters' first panel): the painting of the
/// church in the heavenly clouds — slow Ken Burns, drifting gold haze,
/// shimmering sun rays and the muted cloud loop (a portrait crop on phones)
/// crossfading in over its poster frame — with the red calligraphic welcome, the heavy maroon
/// name on a cream scrim, the address ribbon, the verse panel and the CTAs.
class _Hero extends ConsumerWidget {
  final ChurchSettings? settings;
  final FeatureSettings features;
  const _Hero({required this.settings, required this.features});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settings;
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final narrow = w < 600;
    final f = features;
    final title = s == null ? '' : context.pick(f.heroTitleAr, f.heroTitleEn);
    final subtitle = s == null ? '' : context.pick(f.heroSubtitleAr, f.heroSubtitleEn);
    final pad = narrow ? 16.0 : (wide ? 40.0 : 24.0);

    final text = Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
      if (s == null) ...[
        const SkeletonBox(height: 34, width: 300),
        const SizedBox(height: 12),
        const SkeletonBox(height: 20, width: 220),
      ] else ...[
        TextScrim(
          opacity: 0.84,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 36, vertical: 12),
            child: PosterHeading(
              title.isNotEmpty ? title : context.pick(s.nameAr, s.nameEn),
              key: const Key('heroTitle'),
              accent: context.tr('heroAccent'),
              size: wide ? 56 : (narrow ? 34 : 44),
              glow: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TitleRibbon(subtitle.isNotEmpty ? subtitle : context.pick(s.addressAr, s.addressEn), icon: Icons.place_outlined),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: WarmPanel(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 26, vertical: 14),
            child: Column(children: [
              Text('« ${context.pick(s.verseAr, s.verseEn)} »',
                  textAlign: TextAlign.center,
                  style: AppFonts.script(size: narrow ? 20 : 24, color: AppColors.ink, height: 1.8)),
              if (s.verseRef.isNotEmpty || s.verseRefAr.isNotEmpty)
                Text(
                    context.isAr
                        ? (s.verseRefAr.isNotEmpty ? s.verseRefAr : toArabicDigits(s.verseRef))
                        : (s.verseRef.isNotEmpty ? s.verseRef : s.verseRefAr),
                    style: const TextStyle(color: AppColors.goldText, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 20),
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, children: [
        if (f.routeEnabled('/mass-schedule'))
          FilledButton.icon(
            onPressed: () => context.go('/mass-schedule'),
            icon: const Icon(Icons.access_time_filled_rounded, size: 20),
            label: Text(context.tr('massSchedule')),
          ),
        if (f.routeEnabled('/about'))
          OutlinedButton.icon(
            onPressed: () => context.go('/about'),
            icon: const Icon(Icons.church_outlined, size: 20),
            label: Text(context.tr('aboutChurchCta')),
          )
        else if (f.routeEnabled('/contact'))
          OutlinedButton.icon(
            onPressed: () => context.go('/contact'),
            icon: const Icon(Icons.call_rounded, size: 20),
            label: Text(context.tr('contact')),
          ),
      ]),
    ]);

    return ConstrainedBox(
      key: const Key('homeHero'),
      // Room under the content for the church rising from the mist.
      constraints: BoxConstraints(minHeight: wide ? 780 : (narrow ? 700 : 760)),
      child: Stack(children: [
        Positioned.fill(
          child: HeroStage(
            image: narrow ? ArtAssets.heroTall : ArtAssets.heroWide,
            alignment: Alignment.bottomCenter,
            motion: f.heroMotion,
            // Phones get the portrait centre crop (the church stays centred).
            video: narrow ? ArtAssets.heroVideoTall : ArtAssets.heroVideo,
            poster: narrow ? ArtAssets.heroPosterTall : ArtAssets.heroPoster,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 56 : 52, pad, wide ? 260 : 220),
              child: SizedBox(width: double.infinity, child: text),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Patron saints (UX standard: "who the church is" before "what it offers"),
/// as a poster card: the Nile at sunset with the painted patrons on either
/// side (decoration), «شفعاء كنيستنا», and one panel per saint with the
/// saint's own icon (when uploaded) in a gold halo, two lines of the life and
/// a link to the saint's page.
class _PatronsTeaser extends ConsumerWidget {
  const _PatronsTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(featuresProvider);
    if (!f.enabled(Sections.saints) || !f.routeEnabled('/about')) return const SizedBox.shrink();
    final saints = ref.watch(saintsProvider).value ?? const <Saint>[];
    if (saints.isEmpty) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 1000;
    final narrow = w < 600;
    final halo = narrow ? 92.0 : 128.0;

    Widget saintPanel(Saint saint) {
      final name = context.pick(saint.nameAr, saint.nameEn);
      final path = cardDetailPath(DetailKind.saint, saint.id, saint.details);
      final painting = ArtAssets.paintingForSaint(saint.id);
      return WarmPanel(
        key: ValueKey('homePatron-${saint.id}'),
        padding: EdgeInsets.zero,
        child: DetailTapArea(
          path: path,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              HaloPortrait(
                size: halo,
                child: ItemImage(
                  image: f.showImages ? saint.image : null,
                  size: halo,
                  circle: true,
                  enlargeOnTap: false,
                  label: name,
                  // No uploaded icon: the painted patron (decorative) or a cross.
                  placeholder: painting == null
                      ? const HaloCrossFill()
                      : Image.asset(painting, fit: BoxFit.cover, alignment: const Alignment(0, -0.6)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: displayStyle(context, size: narrow ? 20 : 24, color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 2),
                  Text(context.pick(saint.bioAr, saint.bioEn),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.ink, fontSize: 14, height: 1.7)),
                  if (path != null) DetailsLink(path: path, title: name, id: saint.id),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    final panels = ResponsiveGrid(maxColumns: 2, minItemWidth: 380, spacing: 18, children: [for (final s in saints.take(2)) saintPanel(s)]);

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: ClipRRect(
        key: const Key('patronsBand'),
        borderRadius: BorderRadius.circular(28),
        child: Stack(children: [
          // Lazy: the band is below the fold on every screen.
          Positioned.fill(
            child: LazyArt(
              placeholder: const ColoredBox(color: AppColors.parchment),
              builder: (_) => ExcludeSemantics(
                child: Image.asset(ArtAssets.nile, fit: BoxFit.cover, alignment: const Alignment(0, 0.2)),
              ),
            ),
          ),
          if (wide) ...[
            PositionedDirectional(
              start: -10,
              bottom: 0,
              width: 230,
              child: LazyArt(
                placeholder: const SizedBox(height: 280),
                builder: (_) => _PaintedPatron(ArtAssets.saintMoses),
              ),
            ),
            PositionedDirectional(
              end: -10,
              bottom: 0,
              width: 230,
              child: LazyArt(
                placeholder: const SizedBox(height: 280),
                builder: (_) => _PaintedPatron(ArtAssets.saintMaximusDomadius),
              ),
            ),
          ],
          Padding(
            // Top room so the title glow fades out before the band's edge.
            padding: EdgeInsets.fromLTRB(wide ? 190 : (narrow ? 12 : 24), 36, wide ? 190 : (narrow ? 12 : 24), 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextScrim(
                opacity: 0.8,
                bleed: const EdgeInsets.symmetric(horizontal: 56, vertical: 28),
                child: SectionTitle(
                  context.tr('patronsOfOurChurch'),
                  accent: context.tr('accentPatrons'),
                  trailing: TextButton(onPressed: () => context.go('/about'), child: Text(context.tr('aboutChurchCta'))),
                ),
              ),
              panels,
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A painted patron at the side of the patrons band, its edges dissolving
/// into the scene. Decorative (AI painting, not a real icon).
class _PaintedPatron extends StatelessWidget {
  final String asset;
  const _PaintedPatron(this.asset);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const RadialGradient(
            radius: 0.62,
            colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: [0, 0.6, 1],
          ).createShader(r),
          child: AspectRatio(aspectRatio: 4 / 5, child: Image.asset(asset, fit: BoxFit.cover)),
        ),
      );
}

class _QuickContacts extends ConsumerWidget {
  const _QuickContacts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncSection<ChurchSettings>(
      provider: settingsProvider,
      retry: settingsProvider,
      loading: const SkeletonBox(height: 200, radius: 20),
      builder: (context, s) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.call_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.tr('phones'),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.primary)),
              ),
              if (s.sample) const SampleBadge(),
            ]),
            const SizedBox(height: 8),
            for (final p in s.phones.take(3)) PhoneRow(phone: p),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => context.go('/contact'),
              icon: const Icon(Icons.more_horiz),
              label: Text(context.tr('contact')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Phone line with call (+ WhatsApp for mobiles) buttons.
class PhoneRow extends StatelessWidget {
  final PhoneEntry phone;

  /// Names the line in the buttons' tooltips / screen-reader labels
  /// ("Call — Church office 0100…"); defaults to the phone's label + number.
  final String? semanticLabel;
  const PhoneRow({super.key, required this.phone, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final target = semanticLabel ?? '${context.pick(phone.labelAr, phone.labelEn)} ${phone.number}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.pick(phone.labelAr, phone.labelEn), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(phone.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
            ),
          ]),
        ),
        IconButton.filledTonal(
          tooltip: actionSemanticLabel(context.tr('call'), target),
          onPressed: () => callPhone(phone.number),
          icon: Icon(Icons.call, color: Theme.of(context).colorScheme.primary),
        ),
        if (phone.isMobile)
          IconButton.filledTonal(
            tooltip: actionSemanticLabel(context.tr('whatsapp'), target),
            onPressed: () => openWhatsApp(phone.number),
            icon: const Icon(Icons.chat_rounded, color: whatsappGreen),
          ),
      ]),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final Milestone m;
  const _MilestoneCard(this.m);

  IconData get _icon => switch (m.icon) {
        'church' => Icons.church_rounded,
        'people' => Icons.diversity_3_rounded,
        'altar' => Icons.local_fire_department_rounded,
        'pope' => Icons.workspace_premium_rounded,
        _ => Icons.star_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final title = context.pick(m.titleAr, m.titleEn);
    final detail = cardDetailPath(DetailKind.milestone, m.id, m.details);
    final desc = context.pick(m.descAr, m.descEn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DetailTapArea(
        path: detail,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardCover(collection: 'milestones', itemStyle: m.imageStyle, image: m.image, label: title, enlargeOnTap: detail == null),
          Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CardLead(
                collection: 'milestones',
                itemStyle: m.imageStyle,
                image: m.image,
                size: 56,
                label: title,
                enlargeOnTap: detail == null,
                placeholder: CircleAvatar(
                  backgroundColor: AppColors.gold.withValues(alpha: 0.18),
                  child: Icon(_icon, color: Theme.of(context).colorScheme.primary),
                ),
              ),
              if (m.year != null)
                Flexible(
                  child: Text(localDigits(context, '${m.year}'),
                      style: displayStyle(context, size: 22, color: AppColors.goldText)),
                ),
            ]),
            const SizedBox(height: Space.s),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(desc, style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13)),
            ],
            if (detail != null) DetailsLink(path: detail, title: title, id: m.id),
          ]),
        ),
        ]),
      ),
    );
  }
}

/// "Verse of the day" (settings/features.dailyVerse): a warm golden-hour
/// panel with the Arabic verse in the calligraphic face and its reference
/// in «». Rotates by the Cairo calendar day; hidden when switched off or
/// while the bundled list loads.
class DailyVerseCard extends ConsumerWidget {
  const DailyVerseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(featuresProvider.select((f) => f.dailyVerse));
    if (!config.enabled) return const SizedBox.shrink();
    final verses = ref.watch(dailyVersesProvider).value ?? const <Verse>[];
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final verse = resolveDailyVerse(config, verses, now);
    if (verse == null) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final ref0 = context.isAr || verse.refEn.isEmpty ? verse.refAr : verse.refEn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Reveal(
            child: WarmPanel(
              key: const Key('dailyVerseCard'),
              padding: EdgeInsets.symmetric(horizontal: narrow ? 18 : 32, vertical: 18),
              child: Semantics(
                container: true,
                child: Column(children: [
                  Text(context.tr('accentDailyVerse'),
                      style: AppFonts.script(size: narrow ? 16 : 18, color: AppColors.script)),
                  Semantics(
                    header: true,
                    child: Text(context.tr('dailyVerse'),
                        style: AppFonts.heading(size: narrow ? 22 : 26, color: Theme.of(context).colorScheme.primary)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    verse.textAr,
                    key: const Key('dailyVerseText'),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontSize: narrow ? 19 : 22, height: 1.9, color: AppColors.ink, fontWeight: FontWeight.w700),
                  ),
                  if (ref0.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '« $ref0 »',
                      key: const Key('dailyVerseRef'),
                      textDirection: verse.refEn.isNotEmpty && !context.isAr ? TextDirection.ltr : TextDirection.rtl,
                      style: const TextStyle(color: AppColors.goldText, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
