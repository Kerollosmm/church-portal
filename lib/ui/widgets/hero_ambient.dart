/// The hero's ambient motion (gold haze drift + light-ray shimmer).
///
/// On the web it is a DOM layer animated with CSS (ADR-037). `golden.dart`
/// imports this library with `deferred as`, and only the desktop hero loads
/// it. [heroAmbientInDom] itself stays in `hero_motion_flag.dart` so the main
/// bundle can branch without this chunk. Elsewhere the layer is an empty box
/// and `HeroStage` paints in Flutter.
library;

export 'hero_motion_flag.dart' show heroAmbientInDom;
export 'hero_ambient_io.dart' if (dart.library.js_interop) 'hero_ambient_web.dart';
