import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

const stageOrder = [
  'angels', 'primary', 'preparatory', 'secondary', //
  'youth', 'university', 'graduates', //
  'family', 'men', 'women', 'elderly',
];

const stageLabels = <String, List<String>>{
  'angels': ['الملائكة (حضانة وروضة)', 'Angels (kindergarten)'],
  'primary': ['ابتدائي', 'Primary'],
  'preparatory': ['إعدادي', 'Preparatory'],
  'secondary': ['ثانوي', 'Secondary'],
  'youth': ['الشباب', 'Youth'],
  'university': ['الجامعيون', 'University'],
  'graduates': ['الخريجون', 'Graduates'],
  'family': ['الأسرة', 'Family'],
  'men': ['الرجال', 'Men'],
  'women': ['السيدات', 'Women'],
  'elderly': ['كبار السن', 'Elderly'],
};

const _groups = <(List<String>, String, String, IconData)>[
  (['angels', 'primary', 'preparatory', 'secondary'], 'مدارس الأحد', 'Sunday school', Icons.child_care_rounded),
  (['youth', 'university', 'graduates'], 'الشباب والجامعة والخريجون', 'Youth, university & graduates', Icons.school_rounded),
  (['family', 'men', 'women', 'elderly'], 'اجتماعات خاصة', 'Special meetings', Icons.diversity_3_rounded),
];

class EducationPage extends ConsumerWidget {
  const EducationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      header: PageHeader(title: context.tr('education'), subtitle: context.tr('dir_edu'), icon: Icons.school_rounded),
      children: [
        AsyncSection<List<Meeting>>(
          provider: meetingsProvider,
          retry: meetingsProvider,
          isEmpty: (d) => d.isEmpty,
          loading: const SkeletonList(count: 6),
          builder: (context, meetings) {
            final sorted = [...meetings]..sort((a, b) {
                final ia = stageOrder.indexOf(a.stage), ib = stageOrder.indexOf(b.stage);
                return ia != ib ? ia.compareTo(ib) : a.start.compareTo(b.start);
              });
            final children = <Widget>[];
            for (final g in _groups) {
              final items = sorted.where((m) => g.$1.contains(m.stage)).toList();
              if (items.isEmpty) continue;
              children.add(SectionTitle(context.pick(g.$2, g.$3), icon: g.$4));
              for (var i = 0; i < items.length; i++) {
                children.add(_TimelineItem(meeting: items[i], isLast: i == items.length - 1));
              }
            }
            final other = sorted.where((m) => !stageOrder.contains(m.stage)).toList();
            if (other.isNotEmpty) {
              children.add(SectionTitle(context.tr('otherStages'), icon: Icons.event_note));
              for (var i = 0; i < other.length; i++) {
                children.add(_TimelineItem(meeting: other[i], isLast: i == other.length - 1));
              }
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
          },
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Meeting meeting;
  final bool isLast;
  const _TimelineItem({required this.meeting, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    final label = stageLabels[m.stage];
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            const SizedBox(height: 18),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.burgundy, width: 2),
              ),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: AppColors.gold.withValues(alpha: 0.5))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (label != null) Pill(context.pick(label[0], label[1]), color: AppColors.burgundy),
                    const Spacer(),
                    if (m.sample) const SampleBadge(),
                  ]),
                  const SizedBox(height: 6),
                  Text(context.pick(m.nameAr, m.nameEn), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(weekdayLabel(context, m.weekday),
                      style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  TimeRangeText(m.start, m.end),
                  const SizedBox(height: 4),
                  IconLine(Icons.meeting_room_outlined, context.pick(m.hallAr, m.hallEn)),
                  IconLine(Icons.info_outline, m.notes),
                  if (m.facebookUrl.isNotEmpty || m.whatsappUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (m.facebookUrl.isNotEmpty)
                        ActionChipButton(
                            icon: Icons.facebook,
                            label: context.tr('facebook'),
                            color: facebookBlue,
                            onTap: () => openUrl(m.facebookUrl)),
                      if (m.whatsappUrl.isNotEmpty)
                        ActionChipButton(
                            icon: Icons.chat_rounded,
                            label: context.tr('whatsapp'),
                            color: whatsappGreen,
                            onTap: () => openUrl(m.whatsappUrl)),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
