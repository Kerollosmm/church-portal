import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/custom_content.dart';
import '../../domain/media.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/golden.dart';
import '../widgets/styled_image.dart';
import 'category_page.dart' show ContentUnavailable, openLink;

/// `/page/<slug>`: an admin-built page (ADR-027): optional hero image, then
/// heading / paragraph / image / button / link / donation-info blocks.
/// Hidden / unknown → "not available" (noindex).
class CustomPageView extends ConsumerWidget {
  final String slug;
  const CustomPageView({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = customPagePath(slug);
    return ref.watch(customPagesProvider).when(
          skipLoadingOnReload: true,
          loading: () => const PageBody(children: [SizedBox(height: 24), SkeletonList(count: 3)]),
          error: (_, _) {
            setDocumentRouteMeta(path: path, indexable: false);
            return PageBody(children: [ErrorState(onRetry: () => ref.invalidate(customPagesProvider))]);
          },
          data: (pages) {
            CustomPage? page;
            for (final p in pages) {
              if (p.slug == slug) page = p;
            }
            setDocumentRouteMeta(path: path, indexable: page != null);
            if (page == null) return const ContentUnavailable(key: Key('pageUnavailable'));
            final p = page;
            final title = context.pick(p.titleAr, p.titleEn);
            final subtitle = context.pick(p.subtitleAr.trim(), p.subtitleEn.trim());
            final hero = p.image;
            return PageBody(
              key: Key('page-${p.slug}'),
              header: PageHeader(title: title, subtitle: subtitle.isEmpty ? null : subtitle),
              children: [
                if (hero != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FittedCover(
                        key: const Key('pageHero'), image: hero, label: title, aspectRatio: 16 / 7, maxHeight: 420),
                  ),
                for (final b in p.blocks)
                  if (!b.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 14), child: PageBlockView(block: b)),
              ],
            );
          },
        );
  }
}

/// Renders one [PageBlock] with the active theme's readable colours.
class PageBlockView extends StatelessWidget {
  final PageBlock block;
  const PageBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final b = block;
    final text = context.pick(b.textAr.trim(), b.textEn.trim());
    final primary = context.pal.primary;
    switch (b.type) {
      case BlockTypes.heading:
        return Semantics(
          header: true,
          child: Text(text,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.5, color: context.pal.ink)),
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
            onPressed: () => openLink(context, b.url),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(text.isEmpty ? context.tr('learnMore') : text),
          ),
        );
      case BlockTypes.link:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: primary),
            onPressed: () => openLink(context, b.url),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(text.isEmpty ? b.url : text,
                style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
          ),
        );
      case BlockTypes.donation:
        return DonationInfoCard(block: b);
    }
    return const SizedBox.shrink();
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
