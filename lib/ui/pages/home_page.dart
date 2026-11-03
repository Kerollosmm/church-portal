import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/item_image.dart';
import '../widgets/map_embed.dart';
import '../widgets/ornaments.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final features = ref.watch(featuresProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final blocks = features.visibleHomeBlocks;

    final children = <Widget>[];
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
          SectionTitle(context.tr('ourStory'), icon: Icons.history_edu_rounded),
          AsyncSection<List<Milestone>>(
            provider: milestonesProvider,
            retry: milestonesProvider,
            isEmpty: (d) => d.isEmpty,
            loading: const SkeletonList(count: 4, itemHeight: 120),
            builder: (context, items) => ResponsiveGrid(
              minItemWidth: 240,
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
          SectionTitle(context.tr('directory'), icon: Icons.grid_view_rounded),
          ResponsiveGrid(minItemWidth: 320, children: cards),
        ]);
      case HomeBlocks.map:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(context.tr('location'), icon: Icons.location_on_rounded),
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
        borderRadius: BorderRadius.circular(4),
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

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(context.tr('heroKicker'),
          style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
      const SizedBox(height: 6),
      if (s == null) ...[
        const SkeletonBox(height: 28, width: 280),
        const SizedBox(height: 10),
        const SkeletonBox(height: 18, width: 200),
      ] else ...[
        Semantics(
          header: true,
          child: Text(title.isNotEmpty ? title : context.pick(s.nameAr, s.nameEn),
              style: displayStyle(context, size: wide ? 42 : (narrow ? 26 : 32), color: AppColors.ink, height: 1.4)),
        ),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.only(top: 3), child: Icon(Icons.place_outlined, size: 18, color: AppColors.goldText)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(subtitle.isNotEmpty ? subtitle : context.pick(s.addressAr, s.addressEn),
                style: const TextStyle(color: AppColors.muted, height: 1.6)),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsetsDirectional.only(start: 16),
          decoration: const BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: AppColors.gold, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('« ${context.pick(s.verseAr, s.verseEn)} »',
                style: const TextStyle(
                    fontFamily: AppFonts.naskh, fontSize: 19, height: 1.8, color: AppColors.ink, fontWeight: FontWeight.w400)),
            if (s.verseRef.isNotEmpty || s.verseRefAr.isNotEmpty)
              Text(
                  context.isAr
                      ? (s.verseRefAr.isNotEmpty ? s.verseRefAr : toArabicDigits(s.verseRef))
                      : (s.verseRef.isNotEmpty ? s.verseRef : s.verseRefAr),
                  style: const TextStyle(color: AppColors.goldText, fontSize: 13)),
          ]),
        ),
      ],
      const SizedBox(height: 22),
      Wrap(spacing: 10, runSpacing: 10, children: [
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

    final arcade = _Arcade(heroImageUrl: s?.heroImageUrl ?? '', wide: wide, narrow: narrow, features: f);

    return Container(
      color: AppColors.cream,
      child: Column(children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 48 : 18, pad, 0),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(flex: 23, child: Padding(padding: const EdgeInsets.only(bottom: 36), child: text)),
                      const SizedBox(width: 32),
                      Expanded(flex: 20, child: Align(alignment: AlignmentDirectional.bottomEnd, child: arcade)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(child: arcade),
                      const SizedBox(height: 18),
                      text,
                      const SizedBox(height: 26),
                    ]),
            ),
          ),
        ),
        // The ledge the arches stand on.
        Container(
          height: 14,
          decoration: const BoxDecoration(
            color: AppColors.parchment,
            border: Border(top: BorderSide(color: AppColors.gold, width: 2), bottom: BorderSide(color: AppColors.hairline)),
          ),
        ),
      ]),
    );
  }
}

/// The hero "iconostasis": the patron saints' icons in gold-leaf arches (the
/// admin hero image takes the large arch when set). Without images, or with
/// images / saints switched off, the arches hold a drawn Coptic cross.
class _Arcade extends ConsumerWidget {
  final String heroImageUrl;
  final bool wide, narrow;
  final FeatureSettings features;
  const _Arcade({required this.heroImageUrl, required this.wide, required this.narrow, required this.features});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saints = features.enabled(Sections.saints) ? (ref.watch(saintsProvider).value ?? const <Saint>[]) : const <Saint>[];
    final big = wide ? const Size(232, 310) : (narrow ? const Size(144, 186) : const Size(176, 230));
    final small = wide ? const Size(150, 214) : (narrow ? const Size(96, 136) : const Size(116, 166));
    Widget arch(Size size, Saint? saint, {String? url}) {
      final name = saint == null ? '' : context.pick(saint.nameAr, saint.nameEn);
      final MediaImage? img = url != null && url.isNotEmpty ? MediaImage.url(url) : saint?.image;
      final frame = ArchFrame(
        width: size.width,
        height: size.height,
        child: ItemImage(
          image: img,
          size: size.width,
          circle: false,
          radius: 0,
          label: name,
          enlargeOnTap: false,
          placeholder: const ArchCrossFill(),
        ),
      );
      final path = saint == null ? null : cardDetailPath(DetailKind.saint, saint.id, saint.details);
      final caption = name.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: size.width + 24,
                child: Text(name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
              ),
            );
      final col = Column(mainAxisSize: MainAxisSize.min, children: [frame, if (wide || !narrow) caption]);
      if (path == null || !features.routeEnabled('/about')) return col;
      return Semantics(
        link: true,
        label: name,
        excludeSemantics: true,
        child: InkWell(onTap: () => context.go(path), child: col),
      );
    }

    final first = saints.isNotEmpty ? saints.first : null;
    final second = saints.length > 1 ? saints[1] : null;
    return ExcludeSemantics(
      excluding: first == null,
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        arch(small, second),
        SizedBox(width: wide ? 16 : 12),
        arch(big, first, url: heroImageUrl),
      ]),
    );
  }
}

/// Patron saints teaser (UX standard: "who the church is" before "what it
/// offers"): small arches, name, two lines of the life, link to the saint.
class _PatronsTeaser extends ConsumerWidget {
  const _PatronsTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(featuresProvider);
    if (!f.enabled(Sections.saints) || !f.routeEnabled('/about')) return const SizedBox.shrink();
    final saints = ref.watch(saintsProvider).value ?? const <Saint>[];
    if (saints.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        context.tr('patronSaints'),
        trailing: TextButton(onPressed: () => context.go('/about'), child: Text(context.tr('aboutChurchCta'))),
      ),
      ResponsiveGrid(minItemWidth: 420, children: [
        for (final saint in saints.take(2))
          Card(
            key: ValueKey('homePatron-${saint.id}'),
            child: DetailTapArea(
              path: cardDetailPath(DetailKind.saint, saint.id, saint.details),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ArchFrame(
                    width: 76,
                    height: 96,
                    inset: 3,
                    child: ItemImage(
                      image: saint.image,
                      size: 76,
                      circle: false,
                      radius: 0,
                      enlargeOnTap: false,
                      label: context.pick(saint.nameAr, saint.nameEn),
                      placeholder: const ArchCrossFill(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.pick(saint.nameAr, saint.nameEn),
                          style: displayStyle(context, size: 18, color: AppColors.ink, height: 1.4)),
                      const SizedBox(height: 2),
                      Text(context.pick(saint.bioAr, saint.bioEn),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.6)),
                      if (cardDetailPath(DetailKind.saint, saint.id, saint.details) case final path?)
                        DetailsLink(path: path, title: context.pick(saint.nameAr, saint.nameEn), id: saint.id),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
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
    return Card(
      child: DetailTapArea(
        path: detail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ItemImage(
                image: m.image,
                size: 48,
                label: title,
                enlargeOnTap: detail == null,
                placeholder: CircleAvatar(
                  backgroundColor: AppColors.gold.withValues(alpha: 0.18),
                  child: Icon(_icon, color: Theme.of(context).colorScheme.primary),
                ),
              ),
              const Spacer(),
              if (m.year != null)
                Text(localDigits(context, '${m.year}'),
                    style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(context.pick(m.descAr, m.descEn), style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13)),
            if (detail != null) DetailsLink(path: detail, title: title, id: m.id),
          ]),
        ),
      ),
    );
  }
}
