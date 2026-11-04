/// The hero's ambient motion (gold haze drift + light-ray shimmer).
///
/// On the web it is a DOM layer animated with CSS (ADR-037): the browser
/// composites it off the main thread, so the page needs no Flutter frames
/// while it plays (a CanvasKit repaint of 14 blurred rays and a masked haze
/// strip every frame kept the main thread busy and PageSpeed's Total
/// Blocking Time in the tens of seconds). Elsewhere [heroAmbientInDom] is
/// false and `HeroStage` animates the layers in Flutter as before.
library;

export 'hero_ambient_io.dart' if (dart.library.js_interop) 'hero_ambient_web.dart';
