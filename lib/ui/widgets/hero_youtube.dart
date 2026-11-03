/// The hero's YouTube background (ADR-026): a muted, looping, control-less
/// player behind the hero, faded in over the poster once it actually plays.
///
/// Web: the YouTube IFrame player (an `<iframe>` from youtube-nocookie.com,
/// driven through the IFrame API's postMessage channel) so the bottom can be
/// feathered with a CSS mask and dimmed with a CSS filter on dark themes.
/// Android / iOS: `youtube_player_iframe` (maintained, WebView based).
/// Either one calls `onFailed` when the video errors, autoplay is refused or
/// nothing plays within [kHeroYouTubeTimeout]: the hero then falls back to
/// the bundled clip (or the poster).
library;

export 'hero_youtube_io.dart' if (dart.library.js_interop) 'hero_youtube_web.dart';
