import 'package:material_ui/material_ui.dart';

/// No playing frame within this time = autoplay blocked / network too slow.
const kHeroYouTubeTimeout = Duration(seconds: 12);

/// A 16:9 frame covering a [w]×[h] stage (scaled a little further so the
/// player's edges and any title bar stay outside the crop), placed by
/// [alignment]: returns left, top, width, height.
({double left, double top, double width, double height}) youtubeCover(double w, double h, Alignment alignment) {
  const ratio = 16 / 9;
  var iw = w, ih = w / ratio;
  if (ih < h) {
    ih = h;
    iw = h * ratio;
  }
  iw *= 1.18;
  ih *= 1.18;
  return (
    left: (w - iw) * (alignment.x + 1) / 2,
    top: (h - ih) * (alignment.y + 1) / 2,
    width: iw,
    height: ih,
  );
}
