import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/custom_content.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/golden.dart';

/// Material icon for a category's admin-chosen icon key ([CategoryIcons]).
IconData categoryIcon(String key) => switch (key) {
      'church' => Icons.church_rounded,
      'people' => Icons.groups_rounded,
      'heart' => Icons.favorite_rounded,
      'book' => Icons.menu_book_rounded,
      'music' => Icons.queue_music_rounded,
      'medical' => Icons.local_hospital_rounded,
      'school' => Icons.school_rounded,
      'event' => Icons.event_rounded,
      'volunteer' => Icons.volunteer_activism_rounded,
      'donate' => Icons.savings_rounded,
      'info' => Icons.info_rounded,
      _ => Icons.star_rounded,
    };

/// Opens an in-app path with go_router, anything else in the browser.
void openLink(BuildContext context, String link) {
  final l = link.trim();
  if (l.startsWith('/') && !l.startsWith('//')) {
    context.go(l);
  } else {
    openUrl(l);
  }
}

/// `/section/<slug>`: an admin-defined category and its items (ADR-027),
/// with the same cards, grid and image styles (ADR-023) as the built-in
/// sections. Hidden / deleted / unknown → "not available" (noindex).
class CategoryPage extends ConsumerWidget {
  final String slug;
  const CategoryPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = categoryPath(slug);
    final cats = ref.watch(categoriesProvider);
    return cats.when(
      skipLoadingOnReload: true,
      loading: () => const PageBody(children: [SizedBox(height: 24), SkeletonList(count: 3)]),
      error: (_, _) {
        setDocumentRouteMeta(path: path, indexable: false);
        return PageBody(children: [ErrorState(onRetry: () => ref.invalidate(categoriesProvider))]);
      },
      data: (list) {
        CustomCategory? cat;
        for (final c in list) {
          if (c.slug == slug) cat = c;
        }
        setDocumentRouteMeta(path: path, indexable: cat != null);
        if (cat == null) return const ContentUnavailable(key: Key('categoryUnavailable'));
        final c = cat;
        final intro = context.pick(c.introAr.trim(), c.introEn.trim());
        return PageBody(
          key: Key('category-${c.slug}'),
          header: PageHeader(title: context.pick(c.nameAr, c.nameEn), icon: categoryIcon(c.icon)),
          children: [
            if (intro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WarmPanel(
                  padding: const EdgeInsets.all(16),
                  child: Text(intro, style: TextStyle(height: 1.75, color: context.pal.ink)),
                ),
              ),
            AsyncSection(
              provider: entriesProvider,
              retry: entriesProvider,
              builder: (context, all) {
                final items = entriesOf(c.id, all);
                if (items.isEmpty) return EmptyState(message: context.tr('categoryEmpty'));
                return ResponsiveGrid(children: [for (final e in items) EntryCard(entry: e, category: c)]);
              },
            ),
          ],
        );
      },
    );
  }
}

/// "This page is not available" with a Back-home button.
class ContentUnavailable extends StatelessWidget {
  const ContentUnavailable({super.key});

  @override
  Widget build(BuildContext context) => PageBody(children: [
        const SizedBox(height: 40),
        Icon(Icons.visibility_off_rounded, size: 64, color: context.pal.muted),
        const SizedBox(height: 12),
        Text(context.tr('itemUnavailable'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: () => context.go('/'), child: Text(context.tr('backHome'))),
        ),
      ]);
}

/// One item of a custom category (card with optional image, description,
/// call / WhatsApp and an external or in-app link).
class EntryCard extends ConsumerWidget {
  final CategoryEntry entry;
  final CustomCategory category;
  const EntryCard({super.key, required this.entry, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final title = context.pick(e.titleAr, e.titleEn);
    final desc = context.pick(e.descAr, e.descEn);
    // The item's own style, else the category's default (ADR-023).
    final style = e.imageStyle.isNotEmpty ? e.imageStyle : category.imageStyle;
    final linkLabel = context.pick(e.externalLabelAr.trim(), e.externalLabelEn.trim());
    final primary = context.pal.primary;
    return Card(
      key: Key('entry-${e.id}'),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardCover(collection: 'entries', itemStyle: style, image: e.image, label: title),
        Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CardLead(
                collection: 'entries',
                itemStyle: style,
                image: e.image,
                size: 56,
                label: title,
                placeholder: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(4)),
                  child: Icon(categoryIcon(category.icon), color: primary),
                ),
              ),
              Expanded(
                child: TitleWithBadge(title,
                    sample: e.sample, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.4)),
              ),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Text(desc, style: const TextStyle(height: 1.7)),
            ],
            if (e.contactPhone.isNotEmpty || e.externalUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (e.contactPhone.isNotEmpty)
                  ActionChipButton(
                      icon: Icons.call,
                      label: context.tr('call'),
                      semanticLabel: actionSemanticLabel(context.tr('call'), title),
                      color: context.pal.bar,
                      onTap: () => callPhone(e.contactPhone)),
                if (e.contactPhone.isNotEmpty && isEgyptianMobile(e.contactPhone))
                  ActionChipButton(
                      icon: Icons.chat_rounded,
                      label: context.tr('whatsapp'),
                      semanticLabel: actionSemanticLabel(context.tr('whatsapp'), title),
                      color: whatsappGreen,
                      onTap: () => openWhatsApp(e.contactPhone)),
                if (e.externalUrl.isNotEmpty)
                  ActionChipButton(
                      icon: Icons.open_in_new_rounded,
                      label: linkLabel.isEmpty ? context.tr('learnMore') : linkLabel,
                      semanticLabel: actionSemanticLabel(linkLabel.isEmpty ? context.tr('learnMore') : linkLabel, title),
                      color: context.pal.bar,
                      onTap: () => openLink(context, e.externalUrl)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
