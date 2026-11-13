/// Whether the hero's haze and rays are a DOM layer (web) or Flutter paint.
///
/// Kept out of [hero_ambient.dart] so the main bundle can branch without
/// downloading that deferred library. The desktop hero loads the library
/// when it actually plays.
library;

export 'hero_motion_flag_io.dart' if (dart.library.js_interop) 'hero_motion_flag_web.dart';
