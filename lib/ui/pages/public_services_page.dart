import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

IconData facilityIcon(String t) => switch (t) {
      'nursery' => Icons.child_friendly_rounded,
      'employment' => Icons.work_rounded,
      'halls' => Icons.meeting_room_rounded,
      'service' => Icons.volunteer_activism_rounded,
      _ => Icons.domain_rounded,
    };

class PublicServicesPage extends ConsumerWidget {
  const PublicServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showClinics = ref.watch(featuresProvider).routeEnabled('/clinics');
    return PageBody(
      header: PageHeader(
          title: context.tr('publicServices'), subtitle: context.tr('dir_services'), icon: Icons.volunteer_activism_rounded),
      children: [
        if (showClinics)
        Card(
          color: AppColors.parchment,
          child: ListTile(
            leading: Icon(Icons.local_hospital_rounded, color: Theme.of(context).colorScheme.primary),
            title: Text(context.tr('charityClinics'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(context.tr('dir_clinics')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/clinics'),
          ),
        ),
        SectionTitle(context.tr('facilities'), icon: Icons.domain_rounded),
        AsyncSection<List<Facility>>(
          provider: facilitiesProvider,
          retry: facilitiesProvider,
          isEmpty: (d) => d.isEmpty,
          builder: (context, items) => ResponsiveGrid(minItemWidth: 340, children: [
            for (final f in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration:
                            BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
                        child: Icon(facilityIcon(f.type), color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TitleWithBadge(context.pick(f.nameAr, f.nameEn),
                            sample: f.sample, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(context.pick(f.descAr, f.descEn), style: const TextStyle(height: 1.7)),
                    const SizedBox(height: 6),
                    IconLine(Icons.schedule_rounded, context.pick(f.hoursAr, f.hoursEn)),
                    if (f.phone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ActionChipButton(
                          icon: Icons.call,
                          label: '${context.tr('call')} ${f.phone}',
                          semanticLabel:
                              actionSemanticLabel('${context.tr('call')} ${f.phone}', context.pick(f.nameAr, f.nameEn)),
                          color: Theme.of(context).colorScheme.primary,
                          onTap: () => callPhone(f.phone)),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}
