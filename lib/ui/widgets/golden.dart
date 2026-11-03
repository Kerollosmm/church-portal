import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/motion_env.dart';
import '../../core/theme.dart';
import 'coptic_cross.dart';

/// "Golden hour" building blocks (docs/design/direction.md, ADR-022): the
/// warm backdrop, translucent panels, the hanging seal tab, poster headings,
/// pill ribbons, halo portraits, and the animated hero stage (Ken Burns, cloud
/// drift, light-ray shimmer, optional looping video) with scroll reveals.
///
/// Decorative art is AI-painted hero imagery (Gemini, Nov 2026). It never
/// replaces a real photo of a priest or a real icon.
class ArtAssets {
  ArtAssets._();
  static const heroWide = 'assets/art/hero_wide.webp'; // 1920 w, desktop hero / headers
  static const heroWideSmall = 'assets/art/hero_wide_sm.webp'; // 1024 w, tablets / footer
  static const heroTall = 'assets/art/hero_tall.webp'; // 900 w, phone hero
  static const nile = 'assets/art/nile.webp'; // Nile sunset band, saint pages
  static const clouds = 'assets/art/clouds.webp'; // gold haze texture (backdrop, drift)
  static const saintMoses = 'assets/art/saint_moses.webp'; // painted St Moses the Black
  static const saintMaximusDomadius = 'assets/art/saint_md.webp'; // painted Sts Maximus & Domadius
  static const heroVideo = 'assets/video/hero_clouds.mp4'; // 10 s muted 720p loop (219 KB)

  /// Painted art for a patron saint id (decorative fallback when the saint
  /// has no uploaded icon), or null.
  static String? paintingForSaint(String id) => switch (id) {
        'moses-black' => saintMoses,
        'maximus-domadius' => saintMaximusDomadius,
        _ => null,
      };
}

/// Whether ambient (looping) motion may run here: not under `flutter test`,
/// not when the OS asks for reduced motion, and only when the admin switch
/// ([adminOn], `settings/features.heroMotion`) allows it.
bool ambientMotionOn(BuildContext context, {bool adminOn = true}) =>
    adminOn && !MotionEnv.isTest && !MediaQuery.disableAnimationsOf(context);

/// Whether the hero video may load and play: ambient motion is on, the visitor
/// did not ask to save data, and the platform plays it (web, Android, iOS).
bool heroVideoAllowed(BuildContext context, {required bool adminOn}) {
  if (!ambientMotionOn(context, adminOn: adminOn) || MotionEnv.saveData) return false;
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

/// The fixed warm backdrop behind every public page: cream wash over the gold
/// cloud texture. Decorative.
class WarmBackdrop extends StatelessWidget {
  const WarmBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
        child: DecoratedBox(
          key: Key('warmBackdrop'),
          decoration: BoxDecoration(
            color: AppColors.cream,
            image: DecorationImage(
              image: AssetImage(ArtAssets.clouds),
              fit: BoxFit.cover,
              opacity: 0.28,
            ),
          ),
          child: SizedBox.expand(),
        ),
      );
}

/// Translucent warm panel (the posters' content boxes) with soft rounded
/// corners. [sepia] is the deeper story-box tone.
class WarmPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool sepia;
  final double radius;
  const WarmPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.sepia = false,
    this.radius = kPanelRadius,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: sepia ? null : AppColors.panel,
          gradient: sepia
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE6CFA9), Color(0xFFDDC197)],
                )
              : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: sepia ? const Color(0x66A06E3C) : const Color(0x61C9963F)),
          boxShadow: kPanelShadow,
        ),
        child: child,
      );
}

/// The maroon "tab" hanging from the top corner (as on the posters), holding
/// the parish seal. Follows the admin colour preset.
class SealTab extends StatelessWidget {
  final double width;
  final double height;
  const SealTab({super.key, this.width = 88, this.height = 108});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final seal = width * 0.76;
    return Container(
      key: const Key('sealTab'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primary, primaryDarkOf(context)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(width * 0.24)),
        boxShadow: const [BoxShadow(color: Color(0x80300808), blurRadius: 18, offset: Offset(0, 10), spreadRadius: -8)],
      ),
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: (height - seal) * 0.42),
      child: Container(
        width: seal,
        height: seal,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cream,
          border: Border.all(color: AppColors.goldLight.withValues(alpha: 0.7)),
        ),
        child: ClipOval(child: Image.asset('assets/branding/seal.png', fit: BoxFit.cover, semanticLabel: '')),
      ),
    );
  }
}

/// Poster heading: an optional calligraphic accent word (Ruqaa, script red)
/// sitting on top of a heavy display title (Lalezar, primary), then a soft
/// brown rule. Centred, like the posters. The title is the semantic header.
class PosterHeading extends StatelessWidget {
  final String title;
  final String? accent;
  final double size;
  final TextAlign align;
  final bool glow;
  const PosterHeading(
    this.title, {
    super.key,
    this.accent,
    this.size = 40,
    this.align = TextAlign.center,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final shadows = glow
        ? const [Shadow(color: Color(0xF2FFF0D2), blurRadius: 18), Shadow(color: Color(0xE6FFF0D2), blurRadius: 4)]
        : null;
    final cross = align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accent != null && accent!.isNotEmpty)
          ExcludeSemantics(
            child: Text(
              accent!,
              textAlign: align,
              style: AppFonts.script(size: size * 0.74, height: 1.1).copyWith(shadows: shadows),
            ),
          ),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: align,
            style: displayStyle(context, size: size, color: primary, height: 1.25).copyWith(shadows: shadows),
          ),
        ),
      ],
    );
  }
}

/// Pill-shaped title ribbon (sepia brown fading out at both ends, cream
/// text) — the posters' sub-title band.
class TitleRibbon extends StatelessWidget {
  final String text;
  final IconData? icon;
  const TitleRibbon(this.text, {super.key, this.icon});

  /// Solid middle of the ribbon (cream text on it: checked in the contrast test).
  static const fill = Color(0xFF7A4530);
  static const textColor = Color(0xFFFFF3DC);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          gradient: LinearGradient(
            colors: [Color(0x007A4530), fill, fill, Color(0x007A4530)],
            stops: [0, 0.1, 0.9, 1],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: textColor), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.5),
              ),
            ),
          ],
        ),
      );
}

/// Round portrait in a glowing gold halo (the posters' sun disc). [child] is
/// the real icon / photo; without one, pass a painting or a drawn cross.
class HaloPortrait extends StatelessWidget {
  final double size;
  final Widget child;
  const HaloPortrait({super.key, required this.size, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.035),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFFEAB0), AppColors.amber, Color(0xFFC08A35)], stops: [0, 0.62, 1]),
          boxShadow: [
            BoxShadow(color: const Color(0x59FFE2A0), spreadRadius: size * 0.045),
            BoxShadow(color: const Color(0x80C8841E), blurRadius: size * 0.2, offset: Offset(0, size * 0.04)),
          ],
        ),
        child: ClipOval(child: SizedBox.expand(child: child)),
      );
}

/// Halo fill when there is no image: a cream disc with the drawn Coptic cross.
class HaloCrossFill extends StatelessWidget {
  const HaloCrossFill({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.cream,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.46,
            child: AspectRatio(aspectRatio: 1, child: CopticCross(color: Theme.of(context).colorScheme.primary)),
          ),
        ),
      );
}

/// Sun rays fanning down from the top centre, shimmering with [shimmer]
/// (0..1). Decorative.
class LightRaysPainter extends CustomPainter {
  final double shimmer;
  final double strength;
  LightRaysPainter({this.shimmer = 0.5, this.strength = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, -size.height * 0.08);
    final reach = size.height * 1.05;
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final t = i / (rays - 1);
      final angle = math.pi / 2 + (t - 0.5) * 1.5; // fan of ~86 degrees
      final width = 0.035 + 0.02 * math.sin(i * 1.7);
      final phase = math.sin((shimmer * 2 * math.pi) + i * 0.9) * 0.5 + 0.5;
      final alpha = (0.10 + 0.16 * phase) * strength;
      final a1 = angle - width / 2, a2 = angle + width / 2;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + math.cos(a1) * reach, origin.dy + math.sin(a1) * reach)
        ..lineTo(origin.dx + math.cos(a2) * reach, origin.dy + math.sin(a2) * reach)
        ..close();
      final paint = Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.0,
          colors: [Color.fromRGBO(255, 238, 196, alpha), const Color.fromRGBO(255, 238, 196, 0)],
        ).createShader(Rect.fromCircle(center: origin, radius: reach));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(LightRaysPainter old) => old.shimmer != shimmer || old.strength != strength;
}

/// Tracks whether this widget is inside the viewport of the nearest
/// scrollable (used to pause ambient loops off-screen and to reveal/lazy
/// load sections).
mixin ViewportVisibility<T extends StatefulWidget> on State<T> {
  ScrollPosition? _position;
  bool visibleInViewport = false;

  /// Called when visibility changes.
  void onViewportVisibility(bool visible);

  /// Extra distance below the viewport that already counts as visible.
  double get viewportLead => 120;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_check);
      _position = p;
      _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    final v = top < screen + viewportLead && top + box.size.height > -viewportLead;
    if (v != visibleInViewport) {
      visibleInViewport = v;
      onViewportVisibility(v);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }
}

/// Fade-and-rise reveal the first time a section scrolls into view. Always
/// builds its child (finders, semantics and focus are unaffected); under
/// reduced motion / tests it shows the child as is.
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin, ViewportVisibility<Reveal> {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _static = true;

  @override
  void didChangeDependencies() {
    _static = !ambientMotionOn(context);
    if (_static) _c.value = 1;
    super.didChangeDependencies();
  }

  @override
  double get viewportLead => -40;

  @override
  void onViewportVisibility(bool visible) {
    if (visible && !_static && _c.value == 0) {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_static) return widget.child;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, 28 * (1 - curve.value)), child: child),
      ),
    );
  }
}

/// Builds [builder] only once the slot comes near the viewport (lazy-loads
/// below-the-fold art); shows [placeholder] (same size) until then.
class LazyArt extends StatefulWidget {
  final WidgetBuilder builder;
  final Widget placeholder;
  const LazyArt({super.key, required this.builder, this.placeholder = const SizedBox.expand()});

  @override
  State<LazyArt> createState() => _LazyArtState();
}

class _LazyArtState extends State<LazyArt> with ViewportVisibility<LazyArt> {
  bool _load = false;

  @override
  double get viewportLead => 600;

  @override
  void onViewportVisibility(bool visible) {
    if (visible && !_load) setState(() => _load = true);
  }

  @override
  Widget build(BuildContext context) => _load ? widget.builder(context) : widget.placeholder;
}

/// The animated golden-hour stage behind a hero or page header: the painting
/// (slow Ken Burns), a drifting gold-cloud layer, shimmering light rays and,
/// when [video] is allowed, a muted looping video that fades in over the
/// painting (its poster frame). Everything holds still under reduced motion,
/// when [motion] is off (admin switch), off-screen, and in tests.
class HeroStage extends StatefulWidget {
  final String image;
  final Alignment alignment;
  final bool motion;
  final String? video;
  final double rays;

  /// Fade into the page wash at the bottom edge.
  final bool fadeBottom;
  const HeroStage({
    super.key,
    required this.image,
    this.alignment = Alignment.center,
    this.motion = true,
    this.video,
    this.rays = 1,
    this.fadeBottom = true,
  });

  @override
  State<HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<HeroStage> with SingleTickerProviderStateMixin, ViewportVisibility<HeroStage> {
  // One slow master clock (60 s); every layer derives its phase from it.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  bool _ambient = false;
  bool _videoOn = false;
  VideoPlayerController? _video;
  bool _videoReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambient = ambientMotionOn(context, adminOn: widget.motion);
    final wantVideo = widget.video != null && heroVideoAllowed(context, adminOn: widget.motion);
    if (wantVideo != _videoOn) {
      _videoOn = wantVideo;
      wantVideo ? _startVideo() : _stopVideo();
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant HeroStage old) {
    super.didUpdateWidget(old);
    if (old.motion != widget.motion || old.video != widget.video) didChangeDependencies();
  }

  @override
  void onViewportVisibility(bool visible) => _sync();

  void _sync() {
    final run = _ambient && visibleInViewport;
    if (run && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!run && _clock.isAnimating) {
      _clock.stop();
    }
    final v = _video;
    if (v != null && _videoReady) {
      run ? v.play() : v.pause();
    }
  }

  Future<void> _startVideo() async {
    final v = VideoPlayerController.asset(widget.video!, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _video = v;
    try {
      await v.initialize();
      await v.setVolume(0); // muted: required for autoplay on the web
      await v.setLooping(true);
      if (!mounted || _video != v) return;
      setState(() => _videoReady = true);
      _sync();
    } catch (_) {
      // Unsupported codec / blocked autoplay: the painting stays.
      if (_video == v) _stopVideo();
    }
  }

  void _stopVideo() {
    final v = _video;
    _video = null;
    _videoReady = false;
    v?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return ExcludeSemantics(
      child: ClipRect(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final t = _clock.value;
              // Ken Burns: 1.00 -> 1.06 and back over the minute.
              final zoom = 1 + 0.06 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
              return Stack(fit: StackFit.expand, children: [
                Transform.scale(
                  scale: _ambient ? zoom : 1,
                  child: Image.asset(widget.image, fit: BoxFit.cover, alignment: widget.alignment, gaplessPlayback: true),
                ),
                if (v != null)
                  AnimatedOpacity(
                    opacity: _videoReady ? 1 : 0,
                    duration: const Duration(milliseconds: 1400),
                    child: _videoReady
                        ? FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: v.value.size.width,
                              height: v.value.size.height,
                              child: VideoPlayer(v),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                // Drifting gold haze (two tiles side by side, sliding across).
                if (_ambient)
                  Opacity(
                    opacity: 0.32,
                    child: LayoutBuilder(builder: (context, c) {
                      final w = c.maxWidth;
                      final dx = -w * t;
                      return Stack(children: [
                        for (final k in const [0.0, 1.0])
                          Positioned(
                            left: dx + k * w,
                            top: 0,
                            width: w,
                            height: c.maxHeight * 0.7,
                            child: Image.asset(ArtAssets.clouds, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                      ]);
                    }),
                  ),
                if (widget.rays > 0)
                  CustomPaint(painter: LightRaysPainter(shimmer: _ambient ? t * 8 % 1 : 0.25, strength: widget.rays)),
                if (widget.fadeBottom)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00FBF3E4), Color(0x00FBF3E4), Color(0xF2FBF3E4)],
                        stops: [0, 0.68, 1],
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Soft radial cream scrim placed behind hero / header text so it keeps
/// AA contrast over any part of the painting.
class TextScrim extends StatelessWidget {
  final Widget child;
  final double opacity;
  const TextScrim({super.key, required this.child, this.opacity = 0.86});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.75,
            colors: [
              AppColors.cream.withValues(alpha: opacity),
              AppColors.cream.withValues(alpha: opacity * 0.7),
              AppColors.cream.withValues(alpha: 0),
            ],
            stops: const [0, 0.6, 1],
          ),
        ),
        child: child,
      );
}
