import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/item_image.dart';

const _categoryOrder = [
  'service', 'choir', 'hymns', 'youth', 'servants', 'media', 'drama', //
  'scouts', 'deacons', 'bible', 'summer', 'sports', 'exhibitions',
];

IconData activityIcon(String c) => switch (c) {
      'scouts' => Icons.hiking_rounded,
      'deacons' => Icons.menu_book_rounded,
      'hymns' => Icons.music_note_rounded,
      'bible' => Icons.auto_stories_rounded,
      'summer' => Icons.wb_sunny_rounded,
      'sports' => Icons.sports_soccer_rounded,
      'exhibitions' => Icons.storefront_rounded,
      'service' => Icons.volunteer_activism_rounded,
      'choir' => Icons.queue_music_rounded,
      'youth' => Icons.groups_2_rounded,
      'servants' => Icons.school_rounded,
      'media' => Icons.smart_display_rounded,
      'drama' => Icons.theater_comedy_rounded,
      _ => Icons.event_rounded,
    };

class ActivitiesPage extends ConsumerWidget {
  const ActivitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      header: PageHeader(title: context.tr('activities'), subtitle: context.tr('dir_act'), icon: Icons.groups_rounded),
      children: [
        AsyncSection<List<Activity>>(
          provider: activitiesProvider,
          retry: activitiesProvider,
          isEmpty: (d) => d.isEmpty,
          builder: (context, items) {
            int idx(String c) {
              final i = _categoryOrder.indexOf(c);
              return i < 0 ? 99 : i;
            }

            // Stable: within a category the admin's order (already applied
            // by the provider) is kept.
            final indexed = items.asMap().entries.toList()
              ..sort((a, b) {
                final c = idx(a.value.category).compareTo(idx(b.value.category));
                return c != 0 ? c : a.key.compareTo(b.key);
              });
            final sorted = [for (final e in indexed) e.value];
            return ResponsiveGrid(minItemWidth: 340, children: [for (final a in sorted) _ActivityCard(a)]);
          },
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity a;
  const _ActivityCard(this.a);

  @override
  Widget build(BuildContext context) {
    final schedule = context.pick(a.scheduleAr, a.scheduleEn);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ItemImage(
              image: a.image,
              size: 56,
              circle: false,
              label: context.pick(a.titleAr, a.titleEn),
              placeholder: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
                child: Icon(activityIcon(a.category), color: AppColors.burgundy),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.pick(a.titleAr, a.titleEn),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.4)),
            ),
            if (a.sample) const SampleBadge(),
          ]),
          const SizedBox(height: 10),
          Text(context.pick(a.descAr, a.descEn), style: const TextStyle(height: 1.7)),
          const SizedBox(height: 8),
          IconLine(Icons.schedule_rounded, schedule.isEmpty ? '' : '${context.tr('schedule')}: $schedule'),
          IconLine(Icons.cake_outlined, a.ageRange.isEmpty ? '' : '${context.tr('ages')}: ${localDigits(context, a.ageRange)}'),
          if (a.link.isNotEmpty) ...[
            const SizedBox(height: 8),
            ActionChipButton(
                icon: _linkIcon(a.link),
                label: context.tr('openPage'),
                color: _linkColor(a.link),
                onTap: () => openUrl(a.link)),
          ],
          if (a.contactPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ActionChipButton(
                  icon: Icons.call, label: context.tr('call'), color: AppColors.burgundy, onTap: () => callPhone(a.contactPhone)),
              if (isEgyptianMobile(a.contactPhone))
                ActionChipButton(
                    icon: Icons.chat_rounded,
                    label: context.tr('whatsapp'),
                    color: whatsappGreen,
                    onTap: () => openWhatsApp(a.contactPhone)),
            ]),
          ],
        ]),
      ),
    );
  }
}

IconData _linkIcon(String url) => url.contains('youtube.com')
    ? Icons.smart_display_rounded
    : url.contains('facebook.com')
        ? Icons.facebook
        : Icons.open_in_new_rounded;

Color _linkColor(String url) => url.contains('youtube.com')
    ? youtubeRed
    : url.contains('facebook.com')
        ? facebookBlue
        : AppColors.burgundy;
