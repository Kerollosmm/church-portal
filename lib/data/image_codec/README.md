# image_codec

## Overview
Platform-conditional image decoding and encoding backend for client-side image processing. Provides dedicated implementations for IO platforms (Android, iOS, desktop, test runners) via pure-Dart `package:image` and for Web platforms via browser canvas and `createImageBitmap` APIs (leveraging browser WebP capabilities and canvas blob conversion).

## Interface
- `Future<DecodedImage> decode(Uint8List bytes)`: Platform-specific image decoder entry point ([`image_codec_io.dart:decode`](file:///c:/Users/Kerollos/church-portal/lib/data/image_codec/image_codec_io.dart#L10), [`image_codec_web.dart:decode`](file:///c:/Users/Kerollos/church-portal/lib/data/image_codec/image_codec_web.dart#L12)).
- `_IoImage`: Pure-Dart `DecodedImage` implementation caching resized variants and encoding to JPEG with alpha flattened onto white ([`image_codec_io.dart:_IoImage`](file:///c:/Users/Kerollos/church-portal/lib/data/image_codec/image_codec_io.dart#L16)).
- `_WebImage`: Web browser `DecodedImage` implementation utilizing `HTMLCanvasElement`, `ImageBitmap`, and `toBlob` supporting WebP with JPEG/PNG fallback ([`image_codec_web.dart:_WebImage`](file:///c:/Users/Kerollos/church-portal/lib/data/image_codec/image_codec_web.dart#L27)).

## Invariants
- `[image_codec_io.dart:decode]`: Throws `ImageDecodeException` if decoded image is null or dimensions (`width`, `height`) are non-positive (`<= 0`). Automatically bakes EXIF orientation into pixels via `img.bakeOrientation`.
- `[image_codec_io.dart:_IoImage.encode]`: Transparent alpha channels must be flattened onto a solid white background (`#FFFFFF`) prior to JPEG compression since JPEG lacks alpha channel support.
- `[image_codec_io.dart:_IoImage.encode]`: Quality parameter is scaled and clamped strictly between 1 and 100 integer range (`(quality * 100).round().clamp(1, 100)`).
- `[image_codec_web.dart:decode]`: Throws `ImageDecodeException` on any decoding failure or when decoded bitmap dimensions are non-positive (`bitmap.width <= 0 || bitmap.height <= 0`). EXIF orientation is handled automatically by the browser bitmap loader.
- `[image_codec_web.dart:_WebImage.encode]`: Canvas background is filled with white (`#ffffff`) before drawing to guarantee transparent PNG alpha blends to white instead of black.
- `[image_codec_web.dart:_WebImage.encode]`: Probes WebP support once (`_webpSupported`); if supported, outputs `image/webp`. If unsupported (e.g. Safari < 17 where `toBlob` ignores WebP), falls back to `image/jpeg` or `image/png`.
- `[image_codec_io.dart:_IoImage.close]`, `[image_codec_web.dart:_WebImage.close]`: Releasing allocated resources (`_resized.clear()` on IO, `bitmap.close()` on Web) must be callable when compression attempts finish.

## Side Effects
- `[image_codec_io.dart:_IoImage]`: In-memory mutation and allocation of resized `img.Image` buffer caches in `_resized` map.
- `[image_codec_web.dart:_WebImage]`: DOM element creation (`HTMLCanvasElement`), GPU texture allocation via `ImageBitmap`, and asynchronous DOM canvas rendering and blob conversion.

## Verification
- Run: `flutter test`
