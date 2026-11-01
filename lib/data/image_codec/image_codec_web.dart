// Browser codec: createImageBitmap + canvas.toBlob (WebP, else JPEG).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../domain/media.dart';
import '../image_processing.dart';
import '../media_repository.dart';

Future<DecodedImage> decode(Uint8List bytes) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    // Browsers apply the EXIF orientation by default.
    final bitmap = await web.window.createImageBitmap(blob).toDart;
    if (bitmap.width <= 0 || bitmap.height <= 0) throw const ImageDecodeException();
    return _WebImage(bitmap);
  } catch (_) {
    throw const ImageDecodeException();
  }
}

/// null = not probed yet; false = toBlob ignored 'image/webp' (Safari < 17).
bool? _webpSupported;

class _WebImage implements DecodedImage {
  final web.ImageBitmap bitmap;
  _WebImage(this.bitmap);

  @override
  int get width => bitmap.width;
  @override
  int get height => bitmap.height;

  @override
  Future<EncodedImage> encode(int maxEdge, double quality) async {
    final t = fitWithin(bitmap.width, bitmap.height, maxEdge);
    final canvas = web.HTMLCanvasElement()
      ..width = t.w
      ..height = t.h;
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    ctx.fillStyle = '#ffffff'.toJS; // transparent PNGs become white, not black
    ctx.fillRect(0, 0, t.w, t.h);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, t.w, t.h);
    if (_webpSupported != false) {
      final b = await _toBlob(canvas, 'image/webp', quality);
      if (b != null && b.type == 'image/webp') {
        _webpSupported = true;
        return EncodedImage(await _bytes(b), 'image/webp', t.w, t.h);
      }
      _webpSupported = false;
    }
    final b = await _toBlob(canvas, 'image/jpeg', quality);
    if (b == null) throw const ImageDecodeException();
    return EncodedImage(await _bytes(b), b.type == 'image/png' ? 'image/png' : 'image/jpeg', t.w, t.h);
  }

  @override
  void close() => bitmap.close();
}

Future<web.Blob?> _toBlob(web.HTMLCanvasElement canvas, String type, double quality) {
  final c = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? b) => c.complete(b)).toJS, type, quality.toJS);
  return c.future;
}

Future<Uint8List> _bytes(web.Blob b) async => (await b.arrayBuffer().toDart).toDart.asUint8List();
