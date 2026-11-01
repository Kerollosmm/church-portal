// Pure-Dart codec (Android, iOS, tests): `image` package, JPEG output.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/media.dart';
import '../image_processing.dart';
import '../media_repository.dart';

Future<DecodedImage> decode(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) throw const ImageDecodeException();
  return _IoImage(img.bakeOrientation(decoded));
}

class _IoImage implements DecodedImage {
  final img.Image src;
  _IoImage(this.src);

  @override
  int get width => src.width;
  @override
  int get height => src.height;

  final _resized = <int, img.Image>{};

  img.Image _at(int maxEdge) => _resized.putIfAbsent(maxEdge, () {
        final t = fitWithin(src.width, src.height, maxEdge);
        var out = (t.w == src.width && t.h == src.height)
            ? src
            : img.copyResize(src, width: t.w, height: t.h, interpolation: img.Interpolation.average);
        if (out.hasAlpha) {
          // JPEG has no alpha: flatten transparent pixels onto white.
          final bg = img.Image(width: out.width, height: out.height);
          img.fill(bg, color: img.ColorRgb8(255, 255, 255));
          out = img.compositeImage(bg, out);
        }
        return out;
      });

  @override
  Future<EncodedImage> encode(int maxEdge, double quality) async {
    final r = _at(maxEdge);
    final bytes = img.encodeJpg(r, quality: (quality * 100).round().clamp(1, 100));
    return EncodedImage(bytes, 'image/jpeg', r.width, r.height);
  }

  @override
  void close() => _resized.clear();
}
