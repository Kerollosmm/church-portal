/// The hero's muted background loop (ADR-022, revised in PR #15).
///
/// On the web it is a plain `<video muted playsinline loop>` (a platform
/// view) so the browser handles autoplay on phones and the bottom of the
/// clip can be feathered with a CSS mask: a platform view cannot be masked
/// by a Flutter `ShaderMask`. Elsewhere (Android / iOS) it is
/// `video_player`, feathered with a `ShaderMask`. Both start invisible over
/// the poster frame and crossfade in once the first frame actually plays,
/// so nothing flashes or jumps.
library;

export 'hero_video_io.dart' if (dart.library.js_interop) 'hero_video_web.dart';
