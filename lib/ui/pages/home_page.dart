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
import '../../domain/season_verses.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/item_image.dart';
import '../widgets/map_embed.dart';
import '../widgets/milestone_card.dart';
import '../widgets/golden.dart';
import '../widgets/today_widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final features = ref.watch(featuresProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final blocks = features.visibleHomeBlocks;

    // The verse of the day lives in the hero ([HeroVerse]). The top event of
    // the day (church event > feast / commemoration, ADR-040) leads the page.
    final children = <Widget>[const KeyedSubtree(key: ValueKey('home-topEvent'), child: TopEventCard())];
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
              children: [for (final m in items) MilestoneCard(m, key: ValueKey('homeMilestone-${m.id}'))],
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
    final primary = context.pal.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.pal.ornament.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.pal.ornament.withValues(alpha: 0.6)),
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
/// shimmering sun rays and the muted cloud loop on desktop web —
/// crossfading in over its poster frame. Phones keep that poster still
/// (no clip, no continuous light or cloud motion). With the red calligraphic welcome, the heavy maroon
/// name on a cream scrim, the optional subtitle / address ribbon, the verse
/// of the day and the CTAs.
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
    final address = s == null ? '' : context.pick(s.addressAr, s.addressEn);
    final heroLine = subtitle.isNotEmpty ? subtitle : (f.heroShowAddress ? address : '');

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
        // The admin's hero subtitle as a ribbon; the address only when the
        // admin switches it on (features.heroShowAddress, default off): it
        // lives on the contact page, in the footer and on the map.
        if (heroLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          TitleRibbon(heroLine, key: const Key('heroRibbon'), icon: subtitle.isNotEmpty ? null : Icons.place_outlined),
        ],
        const SizedBox(height: 18),
        // Verse of the day (settings/features.dailyVerse, ADR-024): daily
        // rotation or the admin's fixed verse, in the hero's own verse
        // panel; sections.dailyVerse shows / hides it.
        const HeroVerse(),
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
            tint: f.heroSeasonTint,
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
                      : Image.asset(
                          painting,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.6),
                          cacheWidth: (halo * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 720),
                          cacheHeight: (halo * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 894),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: displayStyle(context, size: narrow ? 20 : 24, color: context.pal.primary)),
                  const SizedBox(height: 2),
                  Text(context.pick(saint.bioAr, saint.bioEn),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.pal.ink, fontSize: 14, height: 1.7)),
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
              placeholder: ColoredBox(color: context.pal.surfaceAlt),
              builder: (_) => ExcludeSemantics(
                child: sceneArt(
                    context, Image.asset(ArtAssets.nile, fit: BoxFit.cover, alignment: const Alignment(0, 0.2))),
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
            colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)], // palette-exempt: alpha mask
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
              Icon(Icons.call_rounded, color: context.pal.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.tr('phones'),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.primary)),
              ),
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
            Text(context.pick(phone.labelAr, phone.labelEn), style: TextStyle(color: context.pal.muted, fontSize: 12)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(phone.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
            ),
          ]),
        ),
        IconButton.filledTonal(
          tooltip: actionSemanticLabel(context.tr('call'), target),
          onPressed: () => callPhone(phone.number),
          icon: Icon(Icons.call, color: context.pal.primary),
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

/// "Verse of the day" (settings/features.dailyVerse, ADR-024) in the hero,
/// set straight on the hero like the title (no panel): Ruqaa verse in ink
/// between « », reference in gold (the fixed settings verse's typography
/// before PR #17), on the title's kind of soft radial glow plus a halo of
/// the scene colour around every glyph ([HaloText], like the title's halo) —
/// no box. Both colours are checked ≥ 4.5:1 on every theme (`verseGrounds`). Today's Cairo verse or the
/// admin's fixed one. Nothing while the section ([Sections.dailyVerse]) is
/// off, before settings/features arrives (no flash) or while the bundled
/// list loads.
/// Text with a halo of the scene colour [ground] hugging every glyph: a solid
/// outline ([outline] px each side, painted under the text by an unlabelled
/// copy) that fades out through soft shadows — like the hero title's halo, no
/// box. The hero verse's colours are checked on the scene colour at
/// [ThemePalette.verseScrimAlpha] (`verseGrounds`); the halo keeps at least
/// that ground beside every stroke even where the radial glow fades (tested
/// over black and white frames in `test/golden_hour_test.dart`).
class HaloText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color ground;
  final double outline;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  const HaloText(this.text,
      {super.key, required this.style, required this.ground, this.outline = 3.0, this.textAlign, this.textDirection});

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final halo = base.copyWith(
      color: null,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline * 2
        ..strokeJoin = StrokeJoin.round
        ..color = ground,
      shadows: [
        Shadow(color: ground.withValues(alpha: 0.9), blurRadius: 8),
        Shadow(color: ground.withValues(alpha: 0.7), blurRadius: 18),
      ],
    );
    final dir = textDirection ?? Directionality.of(context);
    return Stack(children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: RichText(
            text: TextSpan(text: text, style: halo),
            textAlign: textAlign ?? TextAlign.start,
            textDirection: dir,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
      Text(text, style: style, textAlign: textAlign, textDirection: dir),
    ]);
  }
}

class HeroVerse extends ConsumerWidget {
  const HeroVerse({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featuresReadyProvider)) return const SizedBox.shrink();
    final features = ref.watch(featuresProvider);
    if (!features.enabled(Sections.dailyVerse)) return const SizedBox.shrink();
    final verses = ref.watch(dailyVersesProvider).value ?? const <Verse>[];
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    // Season verse set (ADR-042): read only when an admin set season verses.
    // The seasons stream is usually already open for the next-service card;
    // when that card is hidden (or the schedule is off) this opens the one
    // seasons listener itself (CodeRabbit review on PR #33).
    final seasons = features.seasonVerses.isEmpty ? null : ref.watch(seasonsProvider);
    // Hold the verse until the seasons settle, so the general verse never
    // flashes before the season's (CodeRabbit review on PR #33).
    if (seasons != null && !seasons.hasValue && !seasons.hasError) return const SizedBox.shrink();
    final seasonSet = seasons == null
        ? const <Verse>[]
        : features.seasonVerses.activeSet(seasons.value ?? const [], now);
    final verse = resolveSeasonalVerse(features.dailyVerse, verses, now,
        day: ref.watch(liturgicalDayProvider).date, seasonSet: seasonSet);
    if (verse == null) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 600;
    // ADR-047: English text on the English site when the verse has it, else
    // the Arabic text with its Arabic reference (never mixed).
    final shown = verse.display(english: !context.isAr);
    final reference = shown.ref;
    final ground = context.pal.background;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: TextScrim(
        key: const Key('heroVerse'),
        opacity: ThemePalette.verseScrimAlpha,
        bleed: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 26, vertical: 6),
          child: Semantics(
            container: true,
            label: context.tr('dailyVerse'),
            child: Column(children: [
              HaloText(shown.rtl ? '« ${shown.text} »' : '“${shown.text}”',
                  key: const Key('dailyVerseText'),
                  ground: ground,
                  textAlign: TextAlign.center,
                  textDirection: shown.rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: AppFonts.script(
                      size: shown.rtl ? (narrow ? 20 : 24) : (narrow ? 18 : 22),
                      color: context.pal.ink,
                      height: shown.rtl ? 1.8 : 1.5)),
              if (reference.isNotEmpty)
                HaloText(reference,
                    key: const Key('dailyVerseRef'),
                    ground: ground,
                    textDirection: shown.rtl || reference != verse.refEn.trim() ? TextDirection.rtl : TextDirection.ltr,
                    style: TextStyle(color: context.pal.goldText, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
