import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'hero_feather.dart';
import 'hero_youtube_common.dart';

/// Muted looping YouTube background (Android / iOS): `youtube_player_iframe`
/// sized to cover the stage, feathered, faded in once it plays.
class HeroYouTube extends StatefulWidget {
  final String videoId;
  final Alignment alignment;
  final bool play;

  /// Web only (the sombre filter is applied by the caller here).
  final String cssFilter;
  final VoidCallback onFailed;
  const HeroYouTube({
    super.key,
    required this.videoId,
    required this.alignment,
    required this.play,
    required this.onFailed,
    this.cssFilter = 'none',
  });

  @override
  State<HeroYouTube> createState() => _HeroYouTubeState();
}

class _HeroYouTubeState extends State<HeroYouTube> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(
      mute: true,
      loop: true,
      showControls: false,
      showFullscreenButton: false,
      enableCaption: false,
      enableKeyboard: false,
      showVideoAnnotations: false,
      strictRelatedVideos: true,
      playsInline: true,
      pointerEvents: PointerEvents.none,
    ),
  );
  StreamSubscription<YoutubePlayerValue>? _sub;
  Timer? _timeout;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sub = _c.listen((v) {
      if (v.hasError) {
        _fail();
      } else if (v.playerState == PlayerState.playing && !_playing && mounted) {
        _timeout?.cancel();
        setState(() => _playing = true);
      }
    });
    _timeout = Timer(kHeroYouTubeTimeout, () {
      if (!_playing) _fail();
    });
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    _timeout?.cancel();
    if (mounted) widget.onFailed();
  }

  @override
  void didUpdateWidget(covariant HeroYouTube old) {
    super.didUpdateWidget(old);
    if (old.play != widget.play) {
      (widget.play ? _c.playVideo() : _c.pauseVideo()).ignore();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    _c.close().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: _playing ? 1 : 0,
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOut,
          child: BottomFeather(
            child: LayoutBuilder(builder: (context, c) {
              final r = youtubeCover(c.maxWidth, c.maxHeight, widget.alignment);
              return ClipRect(
                child: Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned(
                    left: r.left,
                    top: r.top,
                    width: r.width,
                    height: r.height,
                    child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9, enableFullScreenOnVerticalDrag: false),
                  ),
                ]),
              );
            }),
          ),
        ),
      );
}
