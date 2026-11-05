import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
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
      header: CustomizablePageHeader(
          pageKey: CustomizablePages.services,
          
          title: context.tr('publicServices'), subtitle: context.tr('dir_services'), icon: Icons.volunteer_activism_rounded),
      children: [
        const PageIntro(pageKey: CustomizablePages.services),
        if (showClinics)
        Card(
          color: context.pal.surfaceAlt,
          child: ListTile(
            leading: Icon(Icons.local_hospital_rounded, color: context.pal.primary),
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
          builder: (context, items) => ResponsiveGrid(children: [
            for (final f in items) _FacilityCard(f),
          ]),
        ),
      ],
    );
  }
}

class _FacilityCard extends StatelessWidget {
  final Facility f;
  const _FacilityCard(this.f);

  @override
  Widget build(BuildContext context) {
    final name = context.pick(f.nameAr, f.nameEn);
    final detail = cardDetailPath(DetailKind.facility, f.id, f.details);
    final desc = context.pick(f.descAr, f.descEn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DetailTapArea(
        path: detail,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardCover(collection: 'facilities', itemStyle: f.imageStyle, image: f.image, label: name, enlargeOnTap: detail == null),
          Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CardLead(
                collection: 'facilities',
                itemStyle: f.imageStyle,
                image: f.image,
                size: 56,
                label: name,
                enlargeOnTap: detail == null,
                placeholder: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(4)),
                  child: Icon(facilityIcon(f.type), color: context.pal.primary),
                ),
              ),
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Text(desc, style: const TextStyle(height: 1.7)),
            ],
            if (context.pick(f.hoursAr, f.hoursEn).isNotEmpty) const SizedBox(height: Space.xs),
            IconLine(Icons.schedule_rounded, context.pick(f.hoursAr, f.hoursEn)),
            if (f.phone.isNotEmpty && f.details.showContacts) ...[
              const SizedBox(height: 8),
              ActionChipButton(
                  icon: Icons.call,
                  label: '${context.tr('call')} ${f.phone}',
                  semanticLabel: actionSemanticLabel('${context.tr('call')} ${f.phone}', name),
                  color: context.pal.bar,
                  onTap: () => callPhone(f.phone)),
            ],
            if (detail != null) DetailsLink(path: detail, title: name, id: f.id),
          ]),
        ),
        ]),
      ),
    );
  }
}
