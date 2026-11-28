import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/custom_content.dart';
import '../../domain/media.dart';
import '../../domain/rules.dart' show toArabicDigits;
import '../../state/providers.dart';
import '../widgets/cards.dart' show ShareLinkButton;
import '../widgets/common.dart';
import '../widgets/golden.dart';
import '../widgets/styled_image.dart';
import 'category_page.dart' show ContentUnavailable, openLink;

/// `/page/<slug>`: an admin-built page (ADR-027): optional hero image, then
/// heading / paragraph / image / button / link / donation-info blocks.
/// Hidden → "not available" (noindex); unknown slug → 404 (noindex).
class CustomPageView extends ConsumerWidget {
  final String slug;
  const CustomPageView({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = customPagePath(slug);
    return ref.watch(rawPagesProvider).when(
          skipLoadingOnReload: true,
          loading: () => const PageBody(children: [SizedBox(height: 24), SkeletonList(count: 3)]),
          error: (_, _) {
            setDocumentRouteMeta(path: path, indexable: false);
            return PageBody(children: [ErrorState(onRetry: () => ref.invalidate(rawPagesProvider))]);
          },
          data: (allPages) {
            final pages = publicPages(allPages);
            CustomPage? page;
            for (final p in pages) {
              if (p.slug == slug) {
                page = p;
                break;
              }
            }
            setDocumentRouteMeta(path: path, indexable: page != null);
            if (page == null) {
              if (allPages.any((p) => p.slug == slug)) {
                return const ContentUnavailable(key: Key('pageUnavailable'));
              }
              return const NotFoundPage(key: Key('pageNotFound'));
            }
            final p = page;
            final features = ref.watch(featuresProvider);
            final categories = ref.watch(categoriesProvider).value;
            final title = context.pick(p.titleAr, p.titleEn);
            final subtitle = context.pick(p.subtitleAr.trim(), p.subtitleEn.trim());
            final shareUrl = shareableUrlForPath(path, english: !context.isAr);
            final hero = p.image;
            final visibleBlocks = [
              for (final b in p.blocks)
                if (!b.isEmpty &&
                    isPageBlockVisible(b, features: features, pages: pages, categories: categories))
                  b,
            ];
            return PageBody(
              key: Key('page-${p.slug}'),
              header: PageHeader(title: title, subtitle: subtitle.isEmpty ? null : subtitle),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hero != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: FittedCover(
                                key: const Key('pageHero'),
                                image: hero,
                                label: title,
                                aspectRatio: 16 / 7,
                                maxHeight: 420),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ShareLinkButton(key: const Key('pageShare'), url: shareUrl, title: title),
                          ),
                        ),
                        for (var i = 0; i < visibleBlocks.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              top: (visibleBlocks[i].type == BlockTypes.heading && (i > 0 || hero != null)) ? 12 : 0,
                              bottom: 16,
                            ),
                            child: PageBlockView(block: visibleBlocks[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
  }
}

/// Renders one [PageBlock] with the active theme's readable colours.
class PageBlockView extends StatelessWidget {
  final PageBlock block;

  /// Optional link/button handler (defaults to [openLink]; used by admin preview
  /// to intercept links without navigating away from `/admin`).
  final void Function(String url)? onLinkTap;

  const PageBlockView({super.key, required this.block, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final b = block;
    final text = context.pick(b.textAr.trim(), b.textEn.trim());
    final primary = context.pal.primary;
    void tapLink() => (onLinkTap ?? (u) => openLink(context, u))(b.url);
    switch (b.type) {
      case BlockTypes.heading:
        return Semantics(
          header: true,
          child: Text(text,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.45, color: context.pal.ink)),
        );
      case BlockTypes.paragraph:
        return SelectableText(text, style: TextStyle(fontSize: 16, height: 1.8, color: context.pal.ink));
      case BlockTypes.image:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FittedCover(image: MediaImage.url(b.url, alt: text), label: text, maxHeight: 460),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.pal.muted, fontSize: 13.5)),
            ),
        ]);
      case BlockTypes.button:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: tapLink,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(text.isEmpty ? context.tr('learnMore') : text),
          ),
        );
      case BlockTypes.link:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: primary),
            onPressed: tapLink,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(text.isEmpty ? b.url : text,
                style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
          ),
        );
      case BlockTypes.donation:
        return DonationInfoCard(block: b);
      case BlockTypes.list:
        return _ListBlockView(block: b);
      case BlockTypes.details:
        return _DetailsBlockView(block: b);
    }
    return const SizedBox.shrink();
  }
}

/// Renders one [BlockTypes.details] block as a collapsed-by-default card
/// built on [WarmPanel], [InkWell], [Semantics], and [AnimatedSize] (no
/// `ExpansionTile`, keeping `main.dart.js` lean). Language is resolved at the
/// block level via [PageBlock.resolveDetails].
class _DetailsBlockView extends StatefulWidget {
  final PageBlock block;
  const _DetailsBlockView({required this.block});

  @override
  State<_DetailsBlockView> createState() => _DetailsBlockViewState();
}

class _DetailsBlockViewState extends State<_DetailsBlockView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final resolved = widget.block.resolveDetails(isAr: context.isAr);
    if (resolved == null) return const SizedBox.shrink();

    final animDuration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180);
    return WarmPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kPanelRadius),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: _expanded,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              resolved.summary,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                                color: context.pal.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ExcludeSemantics(
                            child: AnimatedRotation(
                              turns: _expanded ? 0.5 : 0.0,
                              duration: animDuration,
                              child: Icon(Icons.expand_more_rounded, color: context.pal.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: animDuration,
                alignment: AlignmentDirectional.topStart,
                curve: Curves.easeOutCubic,
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(height: 1, color: context.pal.hairline),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
                            child: SelectableText(
                              resolved.body,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.8,
                                color: context.pal.ink,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders one [BlockTypes.list] block (`bullet` or `numbered`) with localized
/// items and Arabic-Indic numerals in Arabic.
class _ListBlockView extends StatelessWidget {
  final PageBlock block;
  const _ListBlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    for (final item in block.listItems) {
      final text = context.pick(item.ar.trim(), item.en.trim());
      if (text.isNotEmpty) items.add(text);
    }
    if (items.isEmpty) return const SizedBox.shrink();

    final numbered = block.listStyle == ListStyles.numbered;
    final ar = context.isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (numbered)
                  Text(
                    ar ? '${toArabicDigits('${i + 1}')}.' : '${i + 1}.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.75,
                      fontWeight: FontWeight.w800,
                      color: context.pal.primary,
                    ),
                  )
                else
                  ExcludeSemantics(
                    child: Text(
                      '•',
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.55,
                        fontWeight: FontWeight.w800,
                        color: context.pal.primary,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    items[i],
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.75,
                      color: context.pal.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Donation details (display only: no payment is processed on the site).
class DonationInfoCard extends StatelessWidget {
  final PageBlock block;
  const DonationInfoCard({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final notes = context.pick(block.textAr.trim(), block.textEn.trim());
    Widget row(String labelKey, IconData icon, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(icon, color: context.pal.goldText, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(labelKey), style: TextStyle(color: context.pal.muted, fontSize: 13)),
                SelectableText(value,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.ink)),
              ]),
            ),
            IconButton(
              tooltip: context.tr('copy'),
              icon: Icon(Icons.copy_rounded, color: context.pal.primary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('copied'))));
              },
            ),
          ]),
        );
    return WarmPanel(
      key: const Key('donationBlock'),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.volunteer_activism_rounded, color: context.pal.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.tr('donationTitle'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.ink)),
          ),
        ]),
        const SizedBox(height: 12),
        if (block.account.trim().isNotEmpty) row('donationAccount', Icons.account_balance_rounded, block.account.trim()),
        if (block.instapay.trim().isNotEmpty) row('donationInstapay', Icons.bolt_rounded, block.instapay.trim()),
        if (block.wallet.trim().isNotEmpty) row('donationWallet', Icons.account_balance_wallet_rounded, block.wallet.trim()),
        if (notes.isNotEmpty) Text(notes, style: TextStyle(height: 1.7, color: context.pal.ink)),
        const SizedBox(height: 8),
        Text(context.tr('donationDisplayOnly'), style: TextStyle(fontSize: 12.5, color: context.pal.muted)),
      ]),
    );
  }
}
