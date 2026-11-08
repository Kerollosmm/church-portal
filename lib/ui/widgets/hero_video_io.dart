import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import 'hero_feather.dart';

/// Muted looping background video (Android / iOS): `video_player`, covered
/// to the stage, feathered at the bottom, faded in once it is playing.
class HeroVideo extends StatefulWidget {
  final String asset;
  final Alignment alignment;
  final bool play;

  /// CSS filter of the frame on the web ('none', or a dark theme's sombre
  /// filter); on Android / iOS the caller's [ColorFiltered] applies.
  final String cssFilter;
  const HeroVideo({
    super.key,
    required this.asset,
    required this.alignment,
    required this.play,
    this.cssFilter = 'none',
  });

  @override
  State<HeroVideo> createState() => _HeroVideoState();
}

class _HeroVideoState extends State<HeroVideo> {
  VideoPlayerController? _c;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final c = VideoPlayerController.asset(widget.asset, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      if (!mounted || _c != c) return;
      c.addListener(_onTick);
      _sync();
      setState(() {});
    } catch (_) {
      // Unsupported codec / no decoder: the poster stays.
      if (_c == c) {
        _c = null;
        c.dispose();
      }
    }
  }

  void _onTick() {
    final v = _c?.value;
    if (v != null && !_showing && v.isPlaying && v.position > Duration.zero && mounted) {
      setState(() => _showing = true);
    }
  }

  void _sync() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    widget.play ? c.play() : c.pause();
  }

  @override
  void didUpdateWidget(covariant HeroVideo old) {
    super.didUpdateWidget(old);
    if (old.play != widget.play) _sync();
  }

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return const SizedBox.expand();
    return AnimatedOpacity(
      opacity: _showing ? 1 : 0,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOut,
      child: sceneArt(
        context,
        RepaintBoundary(
          child: BottomFeather(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: widget.alignment,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            ),
          ),
        ),
      ),
    );
  }
}
