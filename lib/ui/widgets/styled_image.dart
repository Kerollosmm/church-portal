import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/image_style.dart';
import '../../domain/media.dart';
import '../../state/providers.dart';
import 'golden.dart';
import 'item_image.dart';

/// The display style (ADR-023) of an item's image: the item's own
/// `imageStyle`, else the admin's section default, else the built-in one.
String resolveImageStyle(WidgetRef ref, String collection, String itemStyle) =>
    ref.watch(featuresProvider.select((f) => f.imageStyleFor(collection, itemStyle)));

/// Image shown on a card, or null when there is none or images are off.
MediaImage? _shown(WidgetRef ref, MediaImage? image) =>
    image != null && ref.watch(featuresProvider.select((f) => f.showImages)) ? image : null;

/// Saints' "card" image is a portrait (icons are tall).
bool _portrait(String collection) => collection == 'saints';

/// Cover at the top of a card for the `card` and `banner` styles. Renders
/// nothing (zero size, no gap) for `avatar`, a missing image or images off,
/// so a card without an image looks exactly as before.
///
/// Put it first in a `Card(clipBehavior: Clip.antiAlias)` column with
/// `crossAxisAlignment: stretch`.
class CardCover extends ConsumerWidget {
  final String collection;
  final String itemStyle;
  final MediaImage? image;
  final String label;
  final bool enlargeOnTap;
  const CardCover({
    super.key,
    required this.collection,
    required this.itemStyle,
    required this.image,
    required this.label,
    this.enlargeOnTap = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = _shown(ref, image);
    final style = resolveImageStyle(ref, collection, itemStyle);
    if (img == null || style == ImageStyles.avatar) return const SizedBox.shrink();
    if (style == ImageStyles.banner) {
      return FittedCover(
        key: const Key('cardBanner'),
        image: img,
        label: label,
        aspectRatio: 16 / 7,
        maxHeight: 240,
        radius: 0,
        enlargeOnTap: enlargeOnTap,
      );
    }
    final portrait = _portrait(collection);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(Space.m, Space.m, Space.m, 0),
      child: FittedCover(
        key: const Key('cardCover'),
        image: img,
        label: label,
        aspectRatio: portrait ? 4 / 5 : 4 / 3,
        maxHeight: portrait ? 360 : 280,
        radius: 14,
        enlargeOnTap: enlargeOnTap,
      ),
    );
  }
}

/// Leading slot of a card's title row. `avatar` style with an image: the
/// picture in a round gold halo. `card` / `banner` with an image: nothing
/// (the picture is the card's [CardCover]). No image: [placeholder] (the
/// section icon), or nothing at all (no gap) when there is no placeholder.
class CardLead extends ConsumerWidget {
  final String collection;
  final String itemStyle;
  final MediaImage? image;
  final String label;
  final bool enlargeOnTap;
  final Widget? placeholder;
  final double size;
  const CardLead({
    super.key,
    required this.collection,
    required this.itemStyle,
    required this.image,
    required this.label,
    this.enlargeOnTap = true,
    this.placeholder,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = _shown(ref, image);
    final style = resolveImageStyle(ref, collection, itemStyle);
    final Widget? lead = img == null
        ? placeholder
        : style == ImageStyles.avatar
            ? HaloAvatar(key: const Key('cardAvatar'), image: img, size: size, label: label, enlargeOnTap: enlargeOnTap)
            : null;
    if (lead == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsetsDirectional.only(end: Space.m), child: lead);
  }
}

/// Round picture in a gold halo ring (the posters' saints).
class HaloAvatar extends ConsumerWidget {
  final MediaImage image;
  final double size;
  final String label;
  final bool enlargeOnTap;
  final Widget? placeholder;
  const HaloAvatar({
    super.key,
    required this.image,
    required this.size,
    required this.label,
    this.enlargeOnTap = true,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(mediaRepositoryProvider)?.load;
    final alt = imageAltFor(image.alt, label, english: !context.isAr);
    final halo = HaloPortrait(
      size: size,
      child: MediaImageView(
        image: image,
        loader: loader,
        semanticLabel: alt,
        placeholder: placeholder ?? const HaloCrossFill(),
      ),
    );
    return _enlargeable(context, image, loader, alt, enlargeOnTap, halo, circle: true);
  }
}

/// The whole picture, never cropped: shown with `contain` over a blurred,
/// sepia-toned copy of itself that fills the frame. The frame keeps
/// [aspectRatio] up to [maxHeight].
class FittedCover extends ConsumerWidget {
  final MediaImage image;
  final String label;
  final double aspectRatio;
  final double maxHeight;
  final double radius;
  final bool enlargeOnTap;
  const FittedCover({
    super.key,
    required this.image,
    required this.label,
    this.aspectRatio = 4 / 3,
    this.maxHeight = 280,
    this.radius = 14,
    this.enlargeOnTap = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(mediaRepositoryProvider)?.load;
    final alt = imageAltFor(image.alt, label, english: !context.isAr);
    final fill = ColoredBox(color: context.pal.surfaceAlt);
    // AspectRatio (not LayoutBuilder) so the cover also works inside
    // IntrinsicHeight (the meetings timeline): height = width / ratio, capped
    // at maxHeight (contain keeps the whole picture visible either way).
    final framed = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          // Blurred, warm-toned backdrop (decorative).
          ExcludeSemantics(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(_sepia),
                child: MediaImageView(image: image, loader: loader, fit: BoxFit.cover, placeholder: fill, keyed: false),
              ),
            ),
          ),
          const DecoratedBox(decoration: BoxDecoration(color: Color(0x33FBF3E4))),
          MediaImageView(
            image: image,
            loader: loader,
            fit: BoxFit.contain,
            semanticLabel: alt,
            placeholder: const SizedBox.shrink(),
          ),
        ]),
      ),
    );
    // Always clipped: the blurred backdrop would otherwise bleed past the frame.
    final clipped = radius == 0 ? ClipRect(child: framed) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: framed);
    return _enlargeable(context, image, loader, alt, enlargeOnTap, clipped, radius: radius);
  }
}

/// Image on an item's detail page, in the item's display style: a large
/// halo for `avatar`, the whole picture for `card`, full width for `banner`.
class DetailCover extends StatelessWidget {
  final String style;
  final MediaImage image;
  final String label;
  final bool portrait;
  const DetailCover({super.key, required this.style, required this.image, required this.label, this.portrait = false});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return switch (style) {
      ImageStyles.avatar => Align(
          alignment: AlignmentDirectional.centerStart,
          child: HaloAvatar(image: image, size: narrow ? 148 : 180, label: label),
        ),
      ImageStyles.banner =>
        FittedCover(image: image, label: label, aspectRatio: 16 / 7, maxHeight: 360, radius: kPanelRadius),
      _ => FittedCover(
          image: image,
          label: label,
          aspectRatio: portrait ? 4 / 5 : 4 / 3,
          maxHeight: portrait ? 480 : 420,
          radius: kPanelRadius,
        ),
    };
  }
}

Widget _enlargeable(BuildContext context, MediaImage image, MediaLoader? loader, String alt, bool enlarge, Widget child,
    {bool circle = false, double radius = 0}) {
  if (!enlarge) return child;
  return Semantics(
    button: true,
    hint: context.tr('enlargeImage'),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('itemImageTap'),
        customBorder: circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        onTap: () => showImageViewer(context, image, loader: loader, label: alt),
        child: child,
      ),
    ),
  );
}

// Classic sepia matrix, softened (decorative backdrop only).
const List<double> _sepia = [
  0.393, 0.769, 0.189, 0, 0, //
  0.349, 0.686, 0.168, 0, 0, //
  0.272, 0.534, 0.131, 0, 0, //
  0, 0, 0, 1, 0, //
];
