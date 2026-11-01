// Client-side resize + compression for admin image uploads.
// Web uses the browser's canvas (WebP when supported, else JPEG) so the web
// bundle does not include a Dart image codec; Android / tests use the pure
// Dart `image` package (JPEG).

import 'dart:typed_data';

import '../domain/media.dart';
import 'image_codec/image_codec_io.dart' if (dart.library.js_interop) 'image_codec/image_codec_web.dart' as codec;
import 'media_repository.dart';

/// A decoded source image that can be re-encoded at several sizes/qualities.
abstract class DecodedImage {
  int get width;
  int get height;

  /// Resized to fit [maxEdge] and encoded at [quality] (0–1).
  Future<EncodedImage> encode(int maxEdge, double quality);
  void close();
}

/// Decodes [bytes] with the platform codec. Throws [ImageDecodeException].
Future<DecodedImage> decodeImage(Uint8List bytes) => codec.decode(bytes);

/// Raw files above this size are refused before decoding (memory safety).
const maxInputBytes = 25 * 1024 * 1024;

/// Resize to ≤ 800 px long edge and lower the quality until the result fits
/// ~250 KB (then retry at 640 px). Returns the smallest attempt that fits;
/// throws [ImageTooLargeException] when nothing gets under 700 KB.
Future<EncodedImage> compressDecoded(DecodedImage img) async {
  EncodedImage? best;
  for (final edge in const [MediaLimits.maxEdge, MediaLimits.fallbackEdge]) {
    for (final q in MediaLimits.qualities) {
      final out = await img.encode(edge, q);
      if (best == null || out.length < best.length) best = out;
      if (out.length <= MediaLimits.targetBytes) return out;
    }
  }
  if (best == null || validateMediaBytes(best.length) != null) throw const ImageTooLargeException();
  return best;
}

/// Full pipeline for a picked file.
Future<EncodedImage> prepareUpload(Uint8List bytes) async {
  if (bytes.isEmpty) throw const ImageDecodeException();
  if (bytes.length > maxInputBytes) throw const ImageTooLargeException();
  final img = await decodeImage(bytes);
  try {
    return await compressDecoded(img);
  } finally {
    img.close();
  }
}
