import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/coptic_cross.dart';
import '../widgets/map_embed.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final features = ref.watch(featuresProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final blocks = features.visibleHomeBlocks;

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
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
    final link = features.bannerLink.trim();
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
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

class _Hero extends StatelessWidget {
  final ChurchSettings? settings;
  final FeatureSettings features;
  const _Hero({required this.settings, required this.features});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final t = Theme.of(context).textTheme;
    final hasImage = s != null && s.heroImageUrl.isNotEmpty;
    final f = features;
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Color.lerp(primary, Colors.black, 0.3)!;
    final title = s == null ? '' : context.pick(f.heroTitleAr, f.heroTitleEn);
    final subtitle = s == null ? '' : context.pick(f.heroSubtitleAr, f.heroSubtitleEn);
    return Container(
      constraints: BoxConstraints(minHeight: narrow ? 300 : 380),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [dark, primary, Color.lerp(primary, Colors.white, 0.15)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(s.heroImageUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(dark.withValues(alpha: 0.65), BlendMode.multiply),
              )
            : null,
      ),
      child: Stack(children: [
        if (!hasImage)
          PositionedDirectional(
            end: -40,
            top: -30,
            child: Opacity(opacity: 0.08, child: CopticCross(size: narrow ? 260 : 380, color: Colors.white)),
          ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 32, vertical: narrow ? 28 : 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CopticCross(size: 46),
                const SizedBox(height: 14),
                if (s == null) ...[
                  const SkeletonBox(height: 28, width: 280),
                  const SizedBox(height: 10),
                  const SkeletonBox(height: 18, width: 200),
                ] else ...[
                  Text(title.isNotEmpty ? title : context.pick(s.nameAr, s.nameEn),
                      style: (narrow ? t.headlineSmall : t.headlineMedium)
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35)),
                  const SizedBox(height: 4),
                  Text(subtitle.isNotEmpty ? subtitle : context.pick(s.addressAr, s.addressEn),
                      style: t.bodyLarge?.copyWith(color: AppColors.goldLight)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('« ${context.pick(s.verseAr, s.verseEn)} »',
                          style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.7)),
                      if (s.verseRef.isNotEmpty || s.verseRefAr.isNotEmpty)
                        Text('(${context.isAr ? (s.verseRefAr.isNotEmpty ? s.verseRefAr : toArabicDigits(s.verseRef)) : (s.verseRef.isNotEmpty ? s.verseRef : s.verseRefAr)})',
                            style: const TextStyle(color: AppColors.goldLight)),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (f.routeEnabled('/mass-schedule'))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.ink),
                      onPressed: () => context.go('/mass-schedule'),
                      icon: const Icon(Icons.access_time_filled_rounded),
                      label: Text(context.tr('massSchedule')),
                    ),
                  if (f.routeEnabled('/clinics'))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primary),
                      onPressed: () => context.go('/clinics'),
                      icon: const Icon(Icons.local_hospital_rounded),
                      label: Text(context.tr('clinics')),
                    ),
                  if (f.routeEnabled('/contact'))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    onPressed: () => context.go('/contact'),
                    icon: const Icon(Icons.call_rounded),
                    label: Text(context.tr('contact')),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
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
              const Icon(Icons.call_rounded, color: AppColors.burgundy),
              const SizedBox(width: 8),
              Text(context.tr('phones'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.burgundy)),
              const Spacer(),
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
  const PhoneRow({super.key, required this.phone});

  @override
  Widget build(BuildContext context) {
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
          tooltip: context.tr('call'),
          onPressed: () => callPhone(phone.number),
          icon: const Icon(Icons.call, color: AppColors.burgundy),
        ),
        if (phone.isMobile)
          IconButton.filledTonal(
            tooltip: context.tr('whatsapp'),
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
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.gold.withValues(alpha: 0.18),
                child: Icon(_icon, color: AppColors.burgundy),
              ),
              const Spacer(),
              if (m.year != null)
                Text(localDigits(context, '${m.year}'),
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Text(context.pick(m.titleAr, m.titleEn), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(context.pick(m.descAr, m.descEn), style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13)),
          ]),
        ),
      );
}
