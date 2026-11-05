import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/item_detail.dart';
import '../../domain/models.dart';
import 'cards.dart';
import 'common.dart';

/// One church milestone («محطات تاريخية»): year, title, short text, optional
/// cover / lead image and the "Details" link. Shared by the Home "Our story"
/// block and the About page's «محطات الكنيسة» section (ADR-052) so both show
/// the same card.
class MilestoneCard extends StatelessWidget {
  final Milestone m;
  const MilestoneCard(this.m, {super.key});

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
                  backgroundColor: context.pal.ornament.withValues(alpha: 0.18),
                  child: Icon(_icon, color: context.pal.primary),
                ),
              ),
              if (m.year != null)
                Flexible(
                  child: Text(localDigits(context, '${m.year}'),
                      style: displayStyle(context, size: 22, color: context.pal.goldText)),
                ),
            ]),
            const SizedBox(height: Space.s),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(desc, style: TextStyle(color: context.pal.muted, height: 1.5, fontSize: 13)),
            ],
            if (detail != null) DetailsLink(path: detail, title: title, id: m.id),
          ]),
        ),
        ]),
      ),
    );
  }
}
