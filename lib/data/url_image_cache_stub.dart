// Web stub for URL image disk caching (0 B overhead on web; Image.network uses
// the browser cache directly).

import 'dart:typed_data';

class UrlImageCache {
  UrlImageCache();

  static final UrlImageCache instance = UrlImageCache();

  Future<Uint8List?> get(String url) async => null;
}
