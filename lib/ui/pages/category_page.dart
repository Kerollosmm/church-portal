import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/custom_content.dart';
import '../../domain/features.dart' show Sections;
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
/// sections. Hidden → "not available" (noindex); unknown slug → 404 (noindex).
class CategoryPage extends ConsumerWidget {
  final String slug;
  const CategoryPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = categoryPath(slug);
    final cats = ref.watch(rawCategoriesProvider);
    return cats.when(
      skipLoadingOnReload: true,
      loading: () => const PageBody(children: [SizedBox(height: 24), SkeletonList(count: 3)]),
      error: (_, _) {
        setDocumentRouteMeta(path: path, indexable: false);
        return PageBody(children: [ErrorState(onRetry: () => ref.invalidate(rawCategoriesProvider))]);
      },
      data: (allCats) {
        final list = publicCategories(allCats);
        CustomCategory? cat;
        for (final c in list) {
          if (c.slug == slug) {
            cat = c;
            break;
          }
        }
        setDocumentRouteMeta(path: path, indexable: cat != null);
        if (cat == null) {
          if (allCats.any((c) => c.slug == slug)) {
            return const ContentUnavailable(key: Key('categoryUnavailable'));
          }
          return const NotFoundPage(key: Key('categoryNotFound'));
        }
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
                final f = ref.watch(featuresProvider);
                final pagesAsync = f.enabled(Sections.customPages) ? ref.watch(customPagesProvider) : null;
                final pagesList = pagesAsync?.value;
                final sPages = pagesList != null ? sectionPages(c.id, pagesList) : const <CustomPage>[];
                if (items.isEmpty && sPages.isEmpty) {
                  if (pagesAsync != null && pagesList == null) {
                    if (pagesAsync.hasError) {
                      return ErrorState(onRetry: () => ref.invalidate(rawPagesProvider));
                    }
                    if (pagesAsync.isLoading) {
                      return const SkeletonList(count: 2);
                    }
                  }
                  return EmptyState(message: context.tr('categoryEmpty'));
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (items.isNotEmpty)
                    ResponsiveGrid(children: [for (final e in items) EntryCard(entry: e, category: c)]),
                  if (sPages.isNotEmpty) ...[
                    if (items.isNotEmpty) const SizedBox(height: 16),
                    ResponsiveGrid(children: [
                      for (final p in sPages) CustomPageCard(key: Key('sectionPage-${p.slug}'), page: p),
                    ]),
                  ],
                  if (pagesAsync != null && pagesList == null && pagesAsync.hasError) ...[
                    if (items.isNotEmpty || sPages.isNotEmpty) const SizedBox(height: 16),
                    ErrorState(onRetry: () => ref.invalidate(rawPagesProvider)),
                  ] else if (pagesAsync != null && pagesList == null && pagesAsync.isLoading) ...[
                    if (items.isNotEmpty || sPages.isNotEmpty) const SizedBox(height: 16),
                    const SkeletonList(count: 1),
                  ],
                ]);
              },
            ),
          ],
        );
      },
    );
  }
}

/// Linked custom pages (`placement == 'section'`) for a built-in section page.
class BuiltInSectionPages extends ConsumerWidget {
  final String sectionId;
  const BuiltInSectionPages({super.key, required this.sectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featuresProvider.select((f) => f.enabled(Sections.customPages)))) {
      return const SizedBox.shrink();
    }
    final pagesAsync = ref.watch(customPagesProvider);
    if (pagesAsync.hasError && !pagesAsync.hasValue) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ErrorState(onRetry: () => ref.invalidate(rawPagesProvider)),
      );
    }
    final pages = pagesAsync.value;
    if (pages == null) return const SizedBox.shrink();
    final list = sectionPages(sectionId, pages);
    if (list.isEmpty) return const SizedBox.shrink();
    return Reveal(
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ResponsiveGrid(children: [
          for (final p in list) CustomPageCard(key: Key('sectionPage-${p.slug}'), page: p),
        ]),
      ),
    );
  }
}

/// Card linking to a custom page (used in section pages and featured home cards).
class CustomPageCard extends StatelessWidget {
  final CustomPage page;
  const CustomPageCard({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final p = page;
    final title = context.pick(p.titleAr, p.titleEn);
    final sub = context.pick(p.subtitleAr, p.subtitleEn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        excludeFromSemantics: true,
        canRequestFocus: false,
        onTap: () => context.go(p.path),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardCover(collection: 'pages', itemStyle: '', image: p.image, label: title, enlargeOnTap: false),
            Padding(
              padding: const EdgeInsets.all(Space.card),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: context.pal.surfaceAlt, borderRadius: BorderRadius.circular(4)),
                    child: Icon(Icons.article_rounded, color: context.pal.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.4)),
                  ),
                ]),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Text(sub, style: const TextStyle(height: 1.6)),
                ],
                const SizedBox(height: 10),
                ActionChipButton(
                  icon: Icons.arrow_forward_rounded,
                  label: context.tr('learnMore'),
                  semanticLabel: actionSemanticLabel(context.tr('learnMore'), title),
                  color: context.pal.bar,
                  onTap: () => context.go(p.path),
                ),
              ]),
            ),
          ],
        ),
      ),
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
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.4)),
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
