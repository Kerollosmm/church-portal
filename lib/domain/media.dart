// Optional images on content items (priests, saints, milestones, activities,
// alerts, seasons). Pure Dart: no Flutter / Firebase imports.
//
// A content document MAY carry an `image` map; absent / null = no image and
// the UI keeps its icon / initials placeholder:
//   {source: 'url'|'inline'|'storage', url?, mediaId?, alt?, w?, h?}
// * url     — an external https:// image the admin pasted.
// * inline  — bytes stored in Firestore `media/{mediaId}` (Spark plan: no
//             Cloud Storage). Lists never download the bytes; the card
//             fetches `media/{mediaId}` lazily.
// * storage — Cloud Storage for Firebase (needs the Blaze plan). `url` holds
//             the download URL and `mediaId` the object name, so the public
//             UI renders it exactly like a `url` image.

/// Limits shared by the client (resize/compress) and firestore.rules.
class MediaLimits {
  MediaLimits._();

  /// Long edge after resizing (px).
  static const maxEdge = 800;

  /// Second attempt when the first pass is still above [targetBytes].
  static const fallbackEdge = 640;

  /// Size we aim for after compression (~250 KB).
  static const targetBytes = 250000;

  /// Hard reject above this many bytes after compression (700 KB; also the
  /// `bytes` cap in firestore.rules).
  static const maxBytes = 700000;

  /// Base64 length cap enforced by firestore.rules (`dataBase64`). 700,000
  /// bytes encode to 933,336 chars, so the client limit always fits under it
  /// (and a media doc stays well below Firestore's 1 MiB document limit).
  static const maxBase64Chars = 950000;

  /// Encoder qualities tried in order until the result fits [targetBytes].
  static const qualities = [0.8, 0.7, 0.6, 0.5];

  static const contentTypes = ['image/jpeg', 'image/webp', 'image/png'];

  /// Max length of a pasted URL (matches the other URL fields and the rules).
  static const maxUrlLength = 500;
  static const maxAltLength = 300;
}

class MediaSource {
  MediaSource._();
  static const url = 'url';
  static const inline = 'inline';
  static const storage = 'storage';
  static const all = [url, inline, storage];
}

final _mediaIdRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// The `image` map of a content document.
class MediaImage {
  final String source;
  final String url;
  final String mediaId;
  final String alt;
  final int? w, h;

  const MediaImage({required this.source, this.url = '', this.mediaId = '', this.alt = '', this.w, this.h});

  const MediaImage.url(this.url, {this.alt = '', this.w, this.h})
      : source = MediaSource.url,
        mediaId = '';

  /// Tolerant reader: anything unusable (wrong type, unknown source, missing
  /// url / mediaId) is "no image" (null), never an exception.
  static MediaImage? fromMap(Object? v) {
    if (v is! Map) return null;
    final source = v['source'];
    if (source is! String || !MediaSource.all.contains(source)) return null;
    String s(Object? x) => x is String ? x.trim() : '';
    int? n(Object? x) => x is int ? x : (x is num ? x.toInt() : null);
    final img = MediaImage(
      source: source,
      url: s(v['url']),
      mediaId: s(v['mediaId']),
      alt: s(v['alt']),
      w: n(v['w']),
      h: n(v['h']),
    );
    return img.isUsable ? img : null;
  }

  /// Can be rendered: a url image needs an https URL; an inline image a media id.
  bool get isUsable => switch (source) {
        MediaSource.url => isValidImageUrl(url),
        MediaSource.inline => _mediaIdRe.hasMatch(mediaId),
        MediaSource.storage => isValidImageUrl(url),
        _ => false,
      };

  /// Rendered from the network (url / storage) rather than from `media/`.
  bool get isRemote => source != MediaSource.inline;

  /// `media/{mediaId}` this image owns (inline only), for clean-up.
  String? get ownedMediaId => source == MediaSource.inline && mediaId.isNotEmpty ? mediaId : null;

  double? get aspectRatio => (w != null && h != null && w! > 0 && h! > 0) ? w! / h! : null;

  Map<String, dynamic> toMap() => {
        'source': source,
        if (url.isNotEmpty) 'url': url,
        if (mediaId.isNotEmpty) 'mediaId': mediaId,
        if (alt.isNotEmpty) 'alt': alt,
        if (w != null) 'w': w,
        if (h != null) 'h': h,
      };

  MediaImage copyWith({String? alt}) =>
      MediaImage(source: source, url: url, mediaId: mediaId, alt: alt ?? this.alt, w: w, h: h);

  @override
  bool operator ==(Object other) =>
      other is MediaImage &&
      other.source == source &&
      other.url == url &&
      other.mediaId == mediaId &&
      other.alt == alt &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(source, url, mediaId, alt, w, h);
}

/// Same pattern as `validImage` in firestore.rules.
final _httpsImageRe = RegExp(r'^https://[^/\s]+[.][^/\s]+([/?#]\S*)?$');

/// https only, with a host, no spaces, ≤ 500 chars (mirrors firestore.rules).
bool isValidImageUrl(String v) {
  final s = v.trim();
  if (s.isEmpty || s.length > MediaLimits.maxUrlLength || !_httpsImageRe.hasMatch(s)) return false;
  final u = Uri.tryParse(s);
  return u != null && u.scheme == 'https' && u.host.contains('.');
}

/// Error key for l10n (`imageTooLarge`, `imageEmpty`) or null when the
/// compressed bytes may be stored.
String? validateMediaBytes(int bytes) {
  if (bytes <= 0) return 'imageEmpty';
  if (bytes > MediaLimits.maxBytes) return 'imageTooLarge';
  return null;
}

/// Base64 length of [bytes] raw bytes.
int base64Length(int bytes) => ((bytes + 2) ~/ 3) * 4;

/// Target size that fits [maxEdge] on the long edge, never upscaling.
({int w, int h}) fitWithin(int w, int h, [int maxEdge = MediaLimits.maxEdge]) {
  if (w <= 0 || h <= 0) return (w: 0, h: 0);
  final long = w > h ? w : h;
  if (long <= maxEdge) return (w: w, h: h);
  final scale = maxEdge / long;
  int r(double v) => v.round() < 1 ? 1 : v.round();
  return (w: r(w * scale), h: r(h * scale));
}

/// Media ids an edit leaves behind (old inline image replaced or removed),
/// so the caller can delete them best effort.
List<String> orphanedMediaIds(Object? before, Object? after) {
  final old = MediaImage.fromMap(before)?.ownedMediaId;
  if (old == null) return const [];
  final now = MediaImage.fromMap(after)?.ownedMediaId;
  return now == old ? const [] : [old];
}
