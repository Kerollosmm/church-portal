import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/coptic_cross.dart';
import '../widgets/item_image.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(featuresProvider);
    final showServing = f.enabled(Sections.priests);
    final showDeparted = f.enabled(Sections.departedPriests);
    return PageBody(
      header: PageHeader(title: context.tr('about'), subtitle: context.tr('dir_about'), icon: Icons.church_rounded),
      children: [
        if (f.enabled(Sections.history)) ...[
        SectionTitle(context.tr('history'), icon: Icons.history_edu_rounded),
        AsyncSection<ChurchSettings>(
          provider: settingsProvider,
          retry: settingsProvider,
          loading: const SkeletonBox(height: 160, radius: 16),
          builder: (context, s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (context.pick(s.bishopAr, s.bishopEn).isNotEmpty) ...[
                    IconLine(Icons.workspace_premium_rounded, '${context.tr('bishop')}: ${context.pick(s.bishopAr, s.bishopEn)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 8),
                  ],
                  Text(context.pick(s.historyAr, s.historyEn), style: const TextStyle(height: 1.9, fontSize: 15)),
                ]),
              ),
            ),
            if (s.altars.isNotEmpty) SectionTitle(context.tr('altars'), icon: Icons.local_fire_department_rounded),
            if (s.altars.isNotEmpty) ResponsiveGrid(minItemWidth: 260, children: [
              for (final a in s.altars)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CopticCross(
                          size: 30,
                          color: a.kind == 'main'
                              ? AppColors.gold
                              : Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, 0.15)!),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(context.pick(a.nameAr, a.nameEn),
                            style: TextStyle(
                                fontWeight: a.kind == 'main' ? FontWeight.w800 : FontWeight.w600, height: 1.5)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
        ],
        if (f.enabled(Sections.saints)) ...[
        SectionTitle(context.tr('patronSaints'), icon: Icons.auto_awesome_rounded),
        AsyncSection<List<Saint>>(
          provider: saintsProvider,
          retry: saintsProvider,
          isEmpty: (d) => d.isEmpty,
          builder: (context, saints) => ResponsiveGrid(minItemWidth: 420, children: [
            for (final s in saints)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      // No image: nothing here, the card keeps its text-only look.
                      ItemImage(
                        image: s.image,
                        size: 64,
                        label: context.pick(s.nameAr, s.nameEn),
                        placeholder: const SizedBox.shrink(),
                      ),
                      if (s.image != null && f.showImages) const SizedBox(width: 12),
                      Expanded(
                        child: Text(context.pick(s.nameAr, s.nameEn),
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Theme.of(context).colorScheme.primary)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      Pill('${context.tr('feast')}: ${context.pick(s.feastCopticAr, s.feastCopticEn)}',
                          color: Theme.of(context).colorScheme.primary, icon: Icons.event),
                      if (context.pick(s.feastGregorianAr, s.feastGregorian).isNotEmpty)
                        Pill(context.pick(s.feastGregorianAr, s.feastGregorian), color: AppColors.muted),
                    ]),
                    const SizedBox(height: 10),
                    Text(context.pick(s.bioAr, s.bioEn), style: const TextStyle(height: 1.8)),
                  ]),
                ),
              ),
          ]),
        ),
        ],
        if (showServing || showDeparted)
        AsyncSection<List<Priest>>(
          provider: priestsProvider,
          retry: priestsProvider,
          builder: (context, priests) {
            final serving = showServing ? priests.where((p) => !p.departed).toList() : <Priest>[];
            final departed = showDeparted ? priests.where((p) => p.departed).toList() : <Priest>[];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (showServing) ...[
                SectionTitle(context.tr('priests'), icon: Icons.person_rounded),
                if (serving.isEmpty)
                  const EmptyState()
                else
                  ResponsiveGrid(minItemWidth: 300, children: [for (final p in serving) PriestCard(p)]),
              ],
              if (departed.isNotEmpty) ...[
                SectionTitle(context.tr('departedPriests'), icon: Icons.local_florist_rounded),
                ResponsiveGrid(minItemWidth: 300, children: [for (final p in departed) PriestCard(p)]),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class PriestCard extends StatelessWidget {
  final Priest p;
  const PriestCard(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.isAr ? p.name : (p.nameEn.isNotEmpty ? p.nameEn : p.name);
    return Card(
      color: p.departed ? const Color(0xFFF7F3EC) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ItemImage(
            image: p.displayImage,
            size: 68,
            label: name,
            placeholder: CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.parchment,
              child: Icon(Icons.person, size: 36, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TitleWithBadge(name,
                  sample: p.sample, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.4)),
              Text(context.tr(p.rank == 'hegumen' ? 'hegumen' : 'priest'),
                  style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 4),
              if (p.ordinationDate.isNotEmpty)
                IconLine(Icons.event_outlined,
                    '${context.tr('ordained')}: ${formatLooseDate(p.ordinationDate, arabic: context.isAr)}'),
              if (p.hegumenDate.isNotEmpty)
                IconLine(Icons.workspace_premium_outlined,
                    '${context.tr('hegumenSince')}: ${formatLooseDate(p.hegumenDate, arabic: context.isAr)}'),
              if (p.departed && p.departedDate.isNotEmpty)
                IconLine(Icons.local_florist_outlined,
                    '${context.tr('departedOn')}: ${formatLooseDate(p.departedDate, arabic: context.isAr)}'),
              if (context.pick(p.bioAr, p.bioEn).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.pick(p.bioAr, p.bioEn),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.6)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
