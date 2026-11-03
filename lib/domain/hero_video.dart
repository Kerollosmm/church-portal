// Hero video library (ADR-026): named YouTube links an admin can switch
// between (and attach to an occasion theme) instead of uploading video, so
// the Spark plan never stores or serves video bytes. The bundled cloud loop
// stays the built-in default and the fallback. Pure Dart.

import 'occasion_theme.dart';

final _idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// The 11-character video id of a youtube.com / youtu.be link, or null.
/// Accepted: `youtu.be/ID`, `youtube.com/watch?v=ID`, `/embed/ID`,
/// `/shorts/ID`, `/live/ID` (www., m. or music. hosts; http or https;
/// youtube-nocookie.com embeds). Anything else (other hosts, playlists
/// without a video, channel pages) is rejected.
String? youtubeVideoId(String? input) {
  var s = (input ?? '').trim();
  if (s.isEmpty || s.length > 300) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) s = 'https://$s';
  final Uri u;
  try {
    u = Uri.parse(s);
  } on FormatException {
    return null;
  }
  if (u.scheme != 'https' && u.scheme != 'http') return null;
  if (u.userInfo.isNotEmpty || (u.hasPort && u.port != 443 && u.port != 80)) return null;
  final host = u.host.toLowerCase();
  final segs = u.pathSegments.where((p) => p.isNotEmpty).toList();
  String? id;
  if (host == 'youtu.be') {
    if (segs.length == 1) id = segs.first;
  } else if (const {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'}.contains(host)) {
    if (segs.length == 1 && segs.first == 'watch') {
      id = u.queryParameters['v'];
    } else if (segs.length == 2 && const {'embed', 'shorts', 'live', 'v'}.contains(segs.first)) {
      id = segs[1];
    }
  } else if (host == 'www.youtube-nocookie.com' || host == 'youtube-nocookie.com') {
    if (segs.length == 2 && segs.first == 'embed') id = segs[1];
  }
  return id != null && _idRe.hasMatch(id) ? id : null;
}

/// The stored (canonical) form of a link: `https://www.youtube.com/watch?v=ID`.
/// firestore.rules accepts only this shape (or `https://youtu.be/ID`).
String canonicalYoutubeUrl(String id) => 'https://www.youtube.com/watch?v=$id';

/// One library entry: a name for the admin and a YouTube link.
class HeroVideo {
  /// Slot id `v1`…`v12` (rules validate a fixed set of keys).
  final String id;
  final String name;
  final String url;
  const HeroVideo({required this.id, required this.name, required this.url});

  static const maxName = 80;

  String? get youtubeId => youtubeVideoId(url);

  bool get valid =>
      HeroVideoLibrary.slots.contains(id) &&
      name.trim().isNotEmpty &&
      name.length <= maxName &&
      youtubeId != null;

  Map<String, dynamic> toMap() => {'name': name, 'url': url};

  @override
  bool operator ==(Object other) => other is HeroVideo && other.id == id && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(id, name, url);
}

/// `settings/features.heroVideos`: `items` (slots v1…v12 of name + url), `active`,
/// `byTheme` (preset key to slot). Missing = the bundled clip.
class HeroVideoLibrary {
  final List<HeroVideo> items;

  /// The slot playing by default; '' = the bundled clip.
  final String active;

  /// Optional video per theme preset (wins over [active] while that theme is
  /// in force); '' or a missing / removed slot = [active].
  final Map<String, String> byTheme;

  const HeroVideoLibrary({this.items = const [], this.active = '', this.byTheme = const {}});

  static const defaults = HeroVideoLibrary();
  static const maxItems = 12;
  static final slots = [for (var i = 1; i <= maxItems; i++) 'v$i'];

  bool get isDefault => items.isEmpty && active.isEmpty && byTheme.isEmpty;

  factory HeroVideoLibrary.fromMap(Object? v) {
    if (v is! Map) return defaults;
    final raw = v['items'];
    final items = <HeroVideo>[];
    if (raw is Map) {
      for (final s in slots) {
        final e = raw[s];
        if (e is! Map) continue;
        final item = HeroVideo(
          id: s,
          name: e['name'] is String ? e['name'] as String : '',
          url: e['url'] is String ? e['url'] as String : '',
        );
        if (item.valid) items.add(item);
      }
    }
    final ids = {for (final i in items) i.id};
    final active = v['active'] is String && ids.contains(v['active']) ? v['active'] as String : '';
    final rawBy = v['byTheme'];
    final byTheme = <String, String>{};
    if (rawBy is Map) {
      for (final k in ThemePresets.keys) {
        final s = rawBy[k];
        if (s is String && ids.contains(s)) byTheme[k] = s;
      }
    }
    return HeroVideoLibrary(items: items, active: active, byTheme: byTheme);
  }

  Map<String, dynamic> toMap() => {
        'items': {for (final i in items) i.id: i.toMap()},
        'active': active,
        'byTheme': byTheme,
      };

  HeroVideo? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The first free slot, or null when the library is full.
  String? get freeSlot {
    final used = {for (final i in items) i.id};
    for (final s in slots) {
      if (!used.contains(s)) return s;
    }
    return null;
  }

  /// The video to play while [theme] is in force: the theme's own, else the
  /// active one, else null (the bundled clip).
  HeroVideo? videoFor(String theme) => byId(byTheme[theme] ?? '') ?? byId(active);

  HeroVideoLibrary copyWith({List<HeroVideo>? items, String? active, Map<String, String>? byTheme}) =>
      HeroVideoLibrary(items: items ?? this.items, active: active ?? this.active, byTheme: byTheme ?? this.byTheme);

  /// Without [id]: it stops being active / attached anywhere (the clip and
  /// the other links are kept).
  HeroVideoLibrary remove(String id) => HeroVideoLibrary(
        items: [for (final i in items) if (i.id != id) i],
        active: active == id ? '' : active,
        byTheme: {for (final e in byTheme.entries) if (e.value != id) e.key: e.value},
      );

  @override
  bool operator ==(Object other) {
    if (other is! HeroVideoLibrary || other.active != active || other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    if (other.byTheme.length != byTheme.length) return false;
    return byTheme.entries.every((e) => other.byTheme[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hash(active, Object.hashAll(items), byTheme.length);
}
