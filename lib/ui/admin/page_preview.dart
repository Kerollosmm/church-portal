import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/media_repository.dart';
import '../../domain/custom_content.dart';
import '../../state/providers.dart';
import '../pages/custom_page.dart' show PageBlockView;
import '../widgets/common.dart' show kMaxContentWidth;
import '../widgets/golden.dart' show ArtAssets, HeroStage, PosterHeading, TextScrim, TitleRibbon;
import '../widgets/styled_image.dart' show FittedCover;
import 'admin_strings.dart' show registerAdminStrings;

/// Fullscreen preview of an unsaved [CustomPage] draft from the admin editor.
///
/// Renders the golden-hour header, optional pending or saved hero cover, and
/// visible [PageBlockView] blocks while keeping admin chrome in the admin's UI
/// language and intercepting links/buttons with a safe SnackBar notice.
class PagePreviewScreen extends StatefulWidget {
  final CustomPage page;
  final Uint8List? pendingHeroBytes;
  final String pendingHeroAlt;
  final MediaRepository? media;
  final bool englishEnabled;

  const PagePreviewScreen({
    super.key,
    required this.page,
    this.pendingHeroBytes,
    this.pendingHeroAlt = '',
    this.media,
    this.englishEnabled = true,
  });

  @override
  State<PagePreviewScreen> createState() => _PagePreviewScreenState();
}

class _PagePreviewScreenState extends State<PagePreviewScreen> {
  late Locale _previewLocale;
  bool _initializedLocale = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedLocale) {
      _initializedLocale = true;
      final adminLocale = Localizations.localeOf(context);
      _previewLocale = widget.englishEnabled
          ? (adminLocale.languageCode == 'en' ? const Locale('en') : const Locale('ar'))
          : const Locale('ar');
    }
  }

  @override
  void didUpdateWidget(covariant PagePreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.englishEnabled && _previewLocale.languageCode != 'ar') {
      _previewLocale = const Locale('ar');
    }
  }

  void _toggleLanguage() {
    setState(() {
      _previewLocale = _previewLocale.languageCode == 'ar'
          ? const Locale('en')
          : const Locale('ar');
    });
  }

  void _showPreviewLinkNotice(String url) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.tr('previewLinkDisabled', {'url': url}))),
      );
  }

  @override
  Widget build(BuildContext context) {
    registerAdminStrings();
    final p = widget.page;
    final previewDir = _previewLocale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

    return Scaffold(
      backgroundColor: context.pal.background,
      appBar: AppBar(
        title: Text(context.tr('previewPage'), overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.englishEnabled)
            TextButton.icon(
              key: const Key('preview-lang-toggle'),
              onPressed: _toggleLanguage,
              icon: Icon(Icons.translate_rounded, size: 18, color: context.pal.onPrimaryAccent),
              label: Text(
                _previewLocale.languageCode == 'ar' ? 'English' : 'العربية',
                style: TextStyle(color: context.pal.onPrimaryAccent, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('preview-unsaved-banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: context.pal.surfaceAlt,
              border: Border(bottom: BorderSide(color: context.pal.hairline)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_outlined, size: 18, color: context.pal.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr('previewUnsavedBanner'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.ink),
                      ),
                    ),
                  ],
                ),
                if (!p.visible)
                  Container(
                    key: const Key('preview-hidden-badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.pal.alertGround,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: context.pal.alert.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      context.tr('previewHiddenBadge'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.pal.alert,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: previewDir,
              child: Localizations.override(
                context: context,
                locale: _previewLocale,
                child: Builder(
                  builder: (previewCtx) {
                    final rawTitle = previewCtx.pick(p.titleAr.trim(), p.titleEn.trim());
                    final title = rawTitle.isEmpty ? previewCtx.tr('previewUntitled') : rawTitle;
                    final subtitle = previewCtx.pick(p.subtitleAr.trim(), p.subtitleEn.trim());
                    final hero = p.image;
                    final hasHero = widget.pendingHeroBytes != null || hero != null;
                    final visibleBlocks = [for (final b in p.blocks) if (!b.isEmpty) b];

                    final w = MediaQuery.sizeOf(previewCtx).width;
                    final wide = w >= 900;
                    final phone = w < 600;
                    final headerPad = phone ? 16.0 : (wide ? 40.0 : 24.0);
                    final bodyPad = phone ? 16.0 : 24.0;

                    final header = Stack(
                      children: [
                        Positioned.fill(
                          child: HeroStage(
                            image: phone ? ArtAssets.heroWideSmall : ArtAssets.heroWide,
                            alignment: const Alignment(0, -0.35),
                            motion: false,
                            tint: false,
                            rays: 1,
                          ),
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(headerPad, wide ? 44 : 40, headerPad, wide ? 52 : 36),
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextScrim(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                                        child: PosterHeading(
                                          title,
                                          size: wide ? 54 : (phone ? 34 : 44),
                                          glow: true,
                                        ),
                                      ),
                                    ),
                                    if (subtitle.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 720),
                                        child: TitleRibbon(subtitle),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );

                    final article = SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(bodyPad, 20, bodyPad, 32),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 700),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        if (widget.pendingHeroBytes != null)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxHeight: 420),
                                              child: AspectRatio(
                                                aspectRatio: 16 / 7,
                                                child: Image.memory(
                                                  widget.pendingHeroBytes!,
                                                  key: const Key('pagePreviewPendingHero'),
                                                  fit: BoxFit.contain,
                                                  semanticLabel:
                                                      widget.pendingHeroAlt.isEmpty ? title : widget.pendingHeroAlt,
                                                ),
                                              ),
                                            ),
                                          )
                                        else if (hero != null)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            child: FittedCover(
                                              key: const Key('pageHero'),
                                              image: hero,
                                              label: title,
                                              aspectRatio: 16 / 7,
                                              maxHeight: 420,
                                              enlargeOnTap: false,
                                            ),
                                          ),
                                        if (visibleBlocks.isEmpty)
                                          Padding(
                                            key: const Key('preview-empty-content'),
                                            padding: const EdgeInsets.symmetric(vertical: 24),
                                            child: Center(
                                              child: Text(
                                                previewCtx.tr('previewEmptyContent'),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(color: previewCtx.pal.muted, fontSize: 15),
                                              ),
                                            ),
                                          ),
                                        for (var i = 0; i < visibleBlocks.length; i++)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: (visibleBlocks[i].type == BlockTypes.heading &&
                                                      (i > 0 || hasHero))
                                                  ? 12
                                                  : 0,
                                              bottom: 16,
                                            ),
                                            child: PageBlockView(
                                              block: visibleBlocks[i],
                                              onLinkTap: _showPreviewLinkNotice,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    // Provide MediaRepository (or default null scope) so FittedCover
                    // resolves inline/url images even under bare test harnesses.
                    return ProviderScope(
                      key: ValueKey(widget.media != null),
                      overrides: [
                        if (widget.media != null) mediaRepositoryProvider.overrideWithValue(widget.media),
                      ],
                      child: article,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
