import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../data/media_repository.dart';
import '../../domain/media.dart';
import '../../state/providers.dart';

typedef MediaLoader = Future<Uint8List?> Function(String mediaId);

/// Renders a [MediaImage]: network for url/storage images, lazily fetched +
/// cached bytes for inline (`media/{id}`) images. Shows [placeholder] while
/// loading and on any error, and fades the picture in.
class MediaImageView extends StatefulWidget {
  final MediaImage image;
  final MediaLoader? loader;
  final Widget placeholder;
  final BoxFit fit;
  final String semanticLabel;
  final MediaCache? cache;

  const MediaImageView({
    super.key,
    required this.image,
    required this.placeholder,
    this.loader,
    this.fit = BoxFit.cover,
    this.semanticLabel = '',
    this.cache,
  });

  @override
  State<MediaImageView> createState() => _MediaImageViewState();
}

class _MediaImageViewState extends State<MediaImageView> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MediaImageView old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image || old.loader != widget.loader) _resolve();
  }

  void _resolve() {
    final id = widget.image.ownedMediaId;
    final loader = widget.loader;
    _bytes = (id == null || loader == null) ? null : (widget.cache ?? MediaCache.instance).get(id, loader);
  }

  Widget _frame(BuildContext context, Widget child, int? frame, bool wasSync) {
    if (wasSync) return child;
    return Stack(fit: StackFit.passthrough, children: [
      if (frame == null) Positioned.fill(child: widget.placeholder),
      AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: child,
      ),
    ]);
  }

  Widget _error(BuildContext context, Object error, StackTrace? stack) => widget.placeholder;

  @override
  Widget build(BuildContext context) {
    final label = widget.semanticLabel.isEmpty ? null : widget.semanticLabel;
    if (widget.image.isRemote) {
      return Image.network(
        widget.image.url,
        key: const Key('itemImage'),
        fit: widget.fit,
        semanticLabel: label,
        excludeFromSemantics: label == null,
        // Hosts without CORS headers still display on the web (<img> fallback).
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        frameBuilder: _frame,
        errorBuilder: _error,
      );
    }
    final future = _bytes;
    if (future == null) return widget.placeholder;
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null || data.isEmpty) return widget.placeholder;
        return Image.memory(
          data,
          key: const Key('itemImage'),
          fit: widget.fit,
          gaplessPlayback: true,
          semanticLabel: label,
          excludeFromSemantics: label == null,
          frameBuilder: _frame,
          errorBuilder: _error,
        );
      },
    );
  }
}

/// Avatar / thumbnail for a content card. With no image (or images switched
/// off in /admin → Sections → Images) it is exactly [placeholder], so cards
/// keep their current look.
class ItemImage extends ConsumerWidget {
  final MediaImage? image;
  final Widget placeholder;
  final double size;
  final bool circle;
  final double radius;

  /// Accessible description (falls back to the image's alt text).
  final String label;

  /// Tap opens a larger view.
  final bool enlargeOnTap;

  const ItemImage({
    super.key,
    required this.image,
    required this.placeholder,
    required this.size,
    this.circle = true,
    this.radius = 12,
    this.label = '',
    this.enlargeOnTap = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = image;
    final show = ref.watch(featuresProvider.select((f) => f.showImages));
    if (img == null || !show) return placeholder;
    final loader = ref.watch(mediaRepositoryProvider)?.load;
    final alt = img.alt.isNotEmpty ? img.alt : label;
    final framed = SizedBox.square(
      dimension: size,
      child: MediaImageView(
        image: img,
        loader: loader,
        semanticLabel: alt,
        placeholder: Center(child: placeholder),
      ),
    );
    final clipped = circle
        ? ClipOval(child: framed)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: framed);
    if (!enlargeOnTap) return clipped;
    return Semantics(
      button: true,
      hint: context.tr('enlargeImage'),
      child: InkWell(
        key: const Key('itemImageTap'),
        customBorder: circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        onTap: () => showImageViewer(context, img, loader: loader, label: alt),
        child: clipped,
      ),
    );
  }
}

/// Full-size view of an image (pinch / scroll to zoom).
Future<void> showImageViewer(BuildContext context, MediaImage image, {MediaLoader? loader, String label = ''}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(children: [
          InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: MediaImageView(
                image: image,
                loader: loader,
                fit: BoxFit.contain,
                semanticLabel: label,
                placeholder: const SizedBox(
                    width: 120, height: 120, child: Icon(Icons.image_outlined, size: 64, color: Colors.white54)),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: IconButton.filled(
              tooltip: ctx.tr('close'),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
            ),
          ),
        ]),
      ),
    );
