import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ActivitiesPage extends ConsumerStatefulWidget {
  const ActivitiesPage({super.key});

  @override
  ConsumerState<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends ConsumerState<ActivitiesPage> {
  String _category = '';

  static String _normalizeCategory(String c) => _categoryOrder.contains(c) ? c : 'other';

  static String _categoryLabel(BuildContext context, String c) =>
      context.trOrNull('opt_$c') ?? context.tr('opt_other');

  @override
  Widget build(BuildContext context) {
    return PageBody(
      header: CustomizablePageHeader(
          pageKey: CustomizablePages.activities,
          title: context.tr('activities'), subtitle: context.tr('dir_act'), icon: Icons.groups_rounded),
      children: [
        const PageIntro(pageKey: CustomizablePages.activities),
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
            final grouped = <String, List<Activity>>{};
            for (final e in indexed) {
              final cat = _normalizeCategory(e.value.category);
              grouped.putIfAbsent(cat, () => []).add(e.value);
            }
            final categories = grouped.keys.toList();
            final selected = categories.length >= 2 && categories.contains(_category) ? _category : '';
            final visibleCategories = selected.isEmpty ? categories : [selected];

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (categories.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    ChoiceChip(
                      key: const Key('activityCat-all'),
                      label: Text(context.tr('allCategories')),
                      selected: selected.isEmpty,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: selected.isEmpty ? context.pal.onBar : context.pal.primary,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _category = ''),
                    ),
                    for (final cat in categories)
                      ChoiceChip(
                        key: Key('activityCat-$cat'),
                        label: Text(_categoryLabel(context, cat)),
                        selected: selected == cat,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected == cat ? context.pal.onBar : context.pal.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => setState(() => _category = cat),
                      ),
                  ]),
                ),
              for (final cat in visibleCategories) ...[
                SectionTitle(_categoryLabel(context, cat),
                    key: Key('activityHeader-$cat'), icon: activityIcon(cat)),
                ResponsiveGrid(children: [for (final a in grouped[cat]!) _ActivityCard(a)]),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  final Activity a;
  const _ActivityCard(this.a);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = context.pick(a.scheduleAr, a.scheduleEn);
    final title = context.pick(a.titleAr, a.titleEn);
    final detail = cardDetailPath(DetailKind.activity, a.id, a.details);
    final showLink = a.link.isNotEmpty && itemSocialsShown(a.details, ref.watch(featuresProvider));
    final showPhone = a.contactPhone.isNotEmpty && a.details.showContacts;
    final desc = context.pick(a.descAr, a.descEn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DetailTapArea(
        path: detail,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardCover(
              collection: 'activities', itemStyle: a.imageStyle, image: a.image, label: title, enlargeOnTap: detail == null),
          Padding(
        padding: const EdgeInsets.all(Space.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CardLead(
              collection: 'activities',
              itemStyle: a.imageStyle,
              image: a.image,
              size: 56,
              label: title,
              enlargeOnTap: detail == null,
              placeholder: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(4)),
                child: Icon(activityIcon(a.category), color: context.pal.primary),
              ),
            ),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.4)),
            ),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text(desc, style: const TextStyle(height: 1.7)),
          ],
          if (schedule.isNotEmpty || a.ageRange.isNotEmpty) const SizedBox(height: Space.s),
          IconLine(Icons.schedule_rounded, schedule.isEmpty ? '' : '${context.tr('schedule')}: $schedule'),
          IconLine(Icons.cake_outlined, a.ageRange.isEmpty ? '' : '${context.tr('ages')}: ${localDigits(context, a.ageRange)}'),
          if (showLink) ...[
            const SizedBox(height: 8),
            ActionChipButton(
                icon: _linkIcon(a.link),
                label: context.tr('openPage'),
                semanticLabel: actionSemanticLabel(context.tr('openPage'), title),
                color: _linkColor(context, a.link),
                onTap: () => openUrl(a.link)),
          ],
          if (showPhone) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChipButton(
                  icon: Icons.call,
                  label: context.tr('call'),
                  semanticLabel: actionSemanticLabel(context.tr('call'), title),
                  color: context.pal.bar,
                  onTap: () => callPhone(a.contactPhone)),
              if (isEgyptianMobile(a.contactPhone))
                ActionChipButton(
                    icon: Icons.chat_rounded,
                    label: context.tr('whatsapp'),
                    semanticLabel: actionSemanticLabel(context.tr('whatsapp'), title),
                    color: whatsappGreen,
                    onTap: () => openWhatsApp(a.contactPhone)),
            ]),
          ],
          if (detail != null) DetailsLink(path: detail, title: title, id: a.id),
        ]),
      ),
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

Color _linkColor(BuildContext context, String url) => url.contains('youtube.com')
    ? youtubeRed
    : url.contains('facebook.com')
        ? facebookBlue
        : context.pal.bar;
