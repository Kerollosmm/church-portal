import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion_env.dart';
import '../../core/theme.dart';
import '../../data/error_reporting.dart';
import 'coptic_cross.dart';
import 'hero_ambient.dart' deferred as hero_dom;
import 'hero_ambient_spec.dart';
import 'hero_feather.dart';
import 'hero_motion_flag.dart';
import 'hero_video.dart' deferred as hero_clip;

export 'hero_feather.dart' show BottomFeather;

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
  // Muted 9 s loops of the owner-approved Gemini clip (hero v2, ADR-042):
  // the last second is cross-faded into the first so the native loop has no
  // seam (no audio): 1280x720 for tablets / desktops, 432x768 on the church
  // for phones. Posters are their first frames.
  static const heroVideo = 'assets/video/hero_clouds.mp4';
  static const heroVideoTall = 'assets/video/hero_clouds_tall.mp4';
  static const heroPoster = 'assets/art/hero_poster.webp';
  static const heroPosterTall = 'assets/art/hero_poster_tall.webp';

  /// Intrinsic pixel width, so a decode size never upscales the bitmap.
  static int? pixelWidth(String asset) => switch (asset) {
        heroWide => 1920,
        heroWideSmall => 1024,
        heroTall => 900,
        heroPoster => 1280,
        heroPosterTall => 432,
        clouds => 960,
        _ => null,
      };

  /// Painted art for a patron saint id (decorative fallback when the saint
  /// has no uploaded icon), or null.
  static String? paintingForSaint(String id) => switch (id) {
        'moses-black' => saintMoses,
        'maximus-domadius' => saintMaximusDomadius,
        _ => null,
      };
}

/// OS reduced-motion or a screen reader. On the web, Flutter sets
/// [MediaQueryData.disableAnimations] from `prefers-reduced-motion`.
bool reducedMotionRequested(MediaQueryData mq) => mq.disableAnimations || mq.accessibleNavigation;

/// Whether ambient (looping) motion may run here: not under `flutter test`,
/// not when the OS asks for reduced motion or a screen reader, and only when
/// the admin switch ([adminOn], `settings/features.heroMotion`) allows it.
bool ambientMotionOn(BuildContext context, {bool adminOn = true}) {
  if (!adminOn || MotionEnv.isTest) return false;
  return !reducedMotionRequested(MediaQuery.of(context));
}

/// Whether HeroStage may run its ambient loops (Ken Burns, haze drift, ray shimmer).
/// Off on Android/iOS and on viewports under 600 px. A null [width] skips the
/// width cut. Desktop web at width >= 600 stays fully animated.
bool heroAmbientLoopAllowed({TargetPlatform? platform, double? width}) {
  final p = platform ?? defaultTargetPlatform;
  return p != TargetPlatform.android && p != TargetPlatform.iOS && (width == null || width >= 600);
}

/// True when reduced motion or a mobile platform/viewport should freeze ambient motion.
bool mobileMotionSuppressed(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final platform = Theme.of(context).platform;
  return !ambientMotionOn(context) || !heroAmbientLoopAllowed(platform: platform, width: width);
}

/// Desktop web at width >= 600 may decode the clip. Phones never do, so the
/// video library stays unloaded and mobile web does not request the mp4.
bool heroVideoPlatformAllowed({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
  double? width,
}) =>
    isWeb && heroAmbientLoopAllowed(platform: platform, width: width);

/// Still image under (or instead of) the clip. Phones use the existing poster
/// so the preloaded first frame stays on screen and the painting is not a
/// second download. Desktop with the video off keeps the painting.
String heroStillAsset({
  required String image,
  String? poster,
  required bool videoPlaying,
  required bool phoneLike,
}) {
  if (videoPlaying) return (poster != null && poster.isNotEmpty) ? poster : image;
  if (phoneLike && poster != null && poster.isNotEmpty) return poster;
  return image;
}

/// Decode width for [asset] at this screen, or null when the screen is already
/// at least the bitmap's width (a larger request would upscale).
int? heroCacheWidth(BuildContext context, String asset) {
  final cap = ArtAssets.pixelWidth(asset);
  if (cap == null) return null;
  final px = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
  if (px <= 0 || px >= cap) return null;
  return px;
}

/// Whether the hero video may load and play: ambient motion is on, the visitor
/// did not ask to save data, and [heroVideoPlatformAllowed] is true.
bool heroVideoAllowed(BuildContext context, {required bool adminOn}) {
  if (!ambientMotionOn(context, adminOn: adminOn) || MotionEnv.saveData) return false;
  return heroVideoPlatformAllowed(
    platform: Theme.of(context).platform,
    width: MediaQuery.sizeOf(context).width,
  );
}

/// The fixed warm backdrop behind every public page: cream wash over the gold
/// cloud texture. Decorative.
class WarmBackdrop extends StatelessWidget {
  const WarmBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final cacheW = heroCacheWidth(context, ArtAssets.clouds);
    final ImageProvider<Object> clouds = cacheW == null
        ? const AssetImage(ArtAssets.clouds)
        : ResizeImage(const AssetImage(ArtAssets.clouds), width: cacheW);
    return RepaintBoundary(
        child: ExcludeSemantics(
          child: DecoratedBox(
            key: const Key('warmBackdrop'),
            decoration: BoxDecoration(
              color: context.pal.background,
              image: DecorationImage(
                image: clouds,
                fit: BoxFit.cover,
                // Fainter (and greyed) on a dark scene (ADR-025).
                opacity: context.pal.textureOpacity,
                colorFilter: context.pal.artFilter,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
  }
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
          color: sepia ? null : context.pal.panel,
          gradient: sepia
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [context.pal.sepiaTop, context.pal.sepiaBottom],
                )
              : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: sepia ? context.pal.sepiaEdge.withValues(alpha: 0.4) : context.pal.ornamentLine),
          boxShadow: context.pal.panelShadow,
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
    final pal = context.pal;
    final seal = width * 0.76;
    return Container(
      key: const Key('sealTab'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        // The theme's band colours (maroon tab; charcoal with a crimson edge
        // on Holy Week — ADR-043).
        gradient: pal.barGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: pal.barEdge == null
            ? null
            : Border(
                left: BorderSide(color: pal.barEdge!, width: 1.5),
                right: BorderSide(color: pal.barEdge!, width: 1.5),
                bottom: BorderSide(color: pal.barEdge!, width: 1.5)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(width * 0.24)),
        boxShadow: [BoxShadow(color: pal.shadow(0.5), blurRadius: 18, offset: const Offset(0, 10), spreadRadius: -8)],
      ),
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: (height - seal) * 0.42),
      child: Container(
        width: seal,
        height: seal,
        // White seal on maroon: a thin gold ring and a soft shadow lift it.
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [
            pal.halo[0], pal.ornament, pal.halo[0], pal.ornament, //
            pal.halo[0],
          ]),
          boxShadow: [BoxShadow(color: pal.shadow(0.45), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: ClipOval(
          child: ColoredBox(
            // The seal artwork is drawn on white (palette-exempt: artwork ground).
            color: Colors.white, // palette-exempt: the seal's own white ground
            child: Image.asset(ChurchSeal.asset, fit: BoxFit.cover, filterQuality: FilterQuality.medium, semanticLabel: ''),
          ),
        ),
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
    final primary = context.pal.primary;
    // The glow is the scene colour (warm cream, or black on a dark theme).
    final halo = context.pal.glow;
    final shadows = glow
        ? [Shadow(color: halo.withValues(alpha: 0.95), blurRadius: 18), Shadow(color: halo.withValues(alpha: 0.9), blurRadius: 4)]
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
              style: AppFonts.script(size: size * 0.74, height: 1.1, color: context.pal.script).copyWith(shadows: shadows),
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

  /// Solid middle of the Golden hour ribbon (cream text on it: checked in
  /// the contrast test). Every theme reads its own from `context.pal`.
  static const fill = Color(0xFF7A4530); // palette-exempt: Golden hour reference value (tests)
  static const textColor = Color(0xFFFFF3DC); // palette-exempt: Golden hour reference value (tests)

  @override
  Widget build(BuildContext context) {
    final fill = context.pal.ribbon, textColor = context.pal.ribbonText;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          gradient: LinearGradient(
            colors: [fill.withValues(alpha: 0), fill, fill, fill.withValues(alpha: 0)],
            stops: const [0, 0.1, 0.9, 1],
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
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.5),
              ),
            ),
          ],
        ),
      );
  }
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
          // Gold halo; greyed on Holy Week (ADR-043).
          gradient: RadialGradient(colors: context.pal.halo, stops: const [0, 0.62, 1]),
          boxShadow: [
            BoxShadow(color: context.pal.halo[0].withValues(alpha: 0.35), spreadRadius: size * 0.045),
            BoxShadow(color: context.pal.halo[2].withValues(alpha: 0.5), blurRadius: size * 0.2, offset: Offset(0, size * 0.04)),
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
        color: context.pal.background,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.46,
            child: AspectRatio(aspectRatio: 1, child: CopticCross(color: context.pal.primary)),
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
    final sigma = HeroAmbientSpec.raySigma(size);
    final (r, g, b) = HeroAmbientSpec.rayColor;
    for (final ray in HeroAmbientSpec.rays(size, shimmer: shimmer, strength: strength)) {
      final path = Path()
        ..moveTo(ray.origin.dx, ray.origin.dy)
        ..lineTo(ray.p1.dx, ray.p1.dy)
        ..lineTo(ray.p2.dx, ray.p2.dy)
        ..close();
      final paint = Paint()
        // Feathered sides: a ray is a soft beam, never a hard-edged wedge.
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.0,
          colors: [Color.fromRGBO(r, g, b, ray.alpha), Color.fromRGBO(r, g, b, 0)],
        ).createShader(Rect.fromCircle(center: ray.origin, radius: ray.reach));
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
    _static = mobileMotionSuppressed(context);
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
/// (slow Ken Burns), a drifting gold-cloud haze, shimmering light rays and,
/// when [video] is allowed, a muted looping video that crossfades in over its
/// own first frame ([poster]). Everything holds still under reduced motion,
/// when [motion] is off (admin switch), off-screen, and in tests.
///
/// Seamless by construction (PR #15): every layer covers the whole stage;
/// the haze is a mirrored strip (no tile seam) feathered top-to-bottom; the
/// rays are blurred; and the stage dissolves to transparent at the bottom
/// ([BottomFeather]) so the page backdrop shows through — no box edges.
class HeroStage extends StatefulWidget {
  final String image;
  final Alignment alignment;
  final bool motion;
  final String? video;

  /// First frame of [video] (shown, precached, until the video plays and
  /// whenever it cannot). Without it the painting [image] is the poster.
  final String? poster;
  final double rays;

  /// Dissolve into the page at the bottom edge.
  final bool fadeBottom;

  /// The season theme's colour wash over the art ([OccasionColors.heroTint],
  /// admin switch `heroSeasonTint`, ADR-050). A separate top layer: the Ken
  /// Burns, the haze and the rays are not touched.
  final bool tint;

  const HeroStage({
    super.key,
    required this.image,
    this.alignment = Alignment.center,
    this.motion = true,
    this.video,
    this.poster,
    this.rays = 1,
    this.fadeBottom = true,
    this.tint = true,
  });

  @override
  State<HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<HeroStage>
    with SingleTickerProviderStateMixin, ViewportVisibility<HeroStage>, WidgetsBindingObserver {
  // One slow master clock (60 s); every layer derives its phase from it.
  late final AnimationController _clock = AnimationController(vsync: this, duration: HeroAmbientSpec.clock);
  bool _ambient = false;
  bool _videoOn = false;
  bool _phoneLike = false;
  bool _foreground = true;
  bool _clipReady = false;
  bool _domReady = false;
  bool _clipLoading = false;
  bool _domLoading = false;
  bool _layersScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
    if ((_videoOn || _domAmbient) && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Narrow layout only. Native Android/iOS already stop the clock via
    // heroAmbientLoopAllowed; a wide test surface (and a tablet) keeps the
    // still rays. The video gate is separate and stays off on every phone OS.
    _phoneLike = MediaQuery.sizeOf(context).width < 600;
    _ambient = widget.motion && !mobileMotionSuppressed(context);
    _videoOn = widget.video != null && heroVideoAllowed(context, adminOn: widget.motion);
    // Decode the still before it is needed (no pop-in, no flash on swaps).
    precacheImage(AssetImage(_still), context).ignore();
    _sync();
    _scheduleDesktopLayers();
  }

  /// Desktop web loads the video and CSS ambient chunks after this frame.
  /// Until they arrive the poster (or the painting) stays. Phones never call
  /// this, so those libraries are not downloaded.
  void _scheduleDesktopLayers() {
    if (_layersScheduled) return;
    if ((!_videoOn || _clipReady) && (!_domAmbient || _domReady)) return;
    _layersScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layersScheduled = false;
      if (!mounted) return;
      _loadDesktopLayers();
    });
  }

  void _loadDesktopLayers() {
    if (_videoOn && !_clipReady && !_clipLoading) {
      _clipLoading = true;
      hero_clip.loadLibrary().then((_) {
        if (!mounted) return;
        setState(() => _clipReady = true);
      }, onError: (Object e, StackTrace st) {
        _clipLoading = false;
        ErrorReporting.capture(e, st, section: 'deferred_chunk', source: 'hero_video');
      });
    }
    if (_domAmbient && !_domReady && !_domLoading) {
      _domLoading = true;
      hero_dom.loadLibrary().then((_) {
        if (!mounted) return;
        setState(() => _domReady = true);
      }, onError: (Object e, StackTrace st) {
        _domLoading = false;
        ErrorReporting.capture(e, st, section: 'deferred_chunk', source: 'hero_ambient');
      });
    }
  }

  String get _still => heroStillAsset(
        image: widget.image,
        poster: widget.poster,
        videoPlaying: _videoOn,
        phoneLike: _phoneLike,
      );

  @override
  void didUpdateWidget(covariant HeroStage old) {
    super.didUpdateWidget(old);
    if (old.motion != widget.motion || old.video != widget.video || old.image != widget.image) {
      didChangeDependencies();
    }
  }

  @override
  void onViewportVisibility(bool visible) {
    _sync();
    if ((_videoOn || _domAmbient) && mounted) setState(() {}); // pause / resume the video / DOM layer
  }

  /// Web: the haze and the ray shimmer are a CSS-animated DOM layer
  /// ([HeroAmbientLayer], ADR-037) instead of a Flutter repaint every frame.
  bool get _domAmbient => _ambient && heroAmbientInDom;

  /// The Flutter clock runs only for what Flutter still animates: everything
  /// off the web, and the Ken Burns of the painting (no video) on the web.
  /// It stops when the app is not in the foreground.
  bool get _needsClock => _foreground && _ambient && (!heroAmbientInDom || !_videoOn);

  void _sync() {
    final run = _needsClock && visibleInViewport;
    if (run && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!run && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  Widget _feather(Widget child) => widget.fadeBottom ? BottomFeather(child: child) : child;

  @override
  Widget build(BuildContext context) {
    final stillName = _still;
    final still = Image.asset(
      stillName,
      key: const Key('heroStill'),
      fit: BoxFit.cover,
      alignment: widget.alignment,
      gaplessPlayback: true,
      cacheWidth: heroCacheWidth(context, stillName),
      // First paint: fade in from the backdrop instead of popping in.
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              child: child,
            ),
    );
    // Ken Burns only on the painting: the video carries its own motion and
    // must stay registered with its poster.
    final kenBurns = _ambient && !_videoOn;
    final art = context.pal;
    final tintColors = widget.tint ? art.heroTint : null;
    return ExcludeSemantics(
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: sceneArt(
                context,
                _feather(kenBurns
                    ? AnimatedBuilder(
                        animation: _clock,
                        child: still,
                        builder: (context, child) => Transform.scale(
                          scale: 1 + 0.06 * (0.5 - 0.5 * math.cos(_clock.value * 2 * math.pi)),
                          child: child,
                        ),
                      )
                    : still)),
          ),
          // The bundled clip only: the YouTube hero video library was removed
          // (owner request, 4 Nov 2026 — ADR-036).
          if (_videoOn && _clipReady && widget.video != null)
            hero_clip.HeroVideo(
              key: ValueKey(widget.video),
              asset: widget.video!,
              alignment: widget.alignment,
              play: visibleInViewport && _foreground,
              cssFilter: art.artCssFilter,
            ),
          if (_domAmbient && _domReady)
            hero_dom.HeroAmbientLayer(
              key: ValueKey('ambient-${widget.rays > 0}'),
              haze: true,
              rays: widget.rays,
              play: visibleInViewport && _foreground,
              cssFilter: art.artCssFilter,
              clouds: ArtAssets.clouds,
            ),
          if (_ambient && !_domAmbient) RepaintBoundary(child: sceneArt(context, _feather(_HazeDrift(clock: _clock)))),
          // Phones skip the 14 blurred rays (a still MaskFilter is a large raster).
          if (widget.rays > 0 && !_domAmbient && !_phoneLike)
            RepaintBoundary(
              child: sceneArt(
                  context,
                  _feather(AnimatedBuilder(
                    animation: _clock,
                    builder: (context, _) => CustomPaint(
                      painter: LightRaysPainter(
                          shimmer: _ambient
                              ? _clock.value * (HeroAmbientSpec.clock.inMilliseconds / HeroAmbientSpec.shimmerCycle.inMilliseconds) % 1
                              : HeroAmbientSpec.stillShimmer,
                          strength: widget.rays),
                    ),
                  ))),
            ),
          // Season wash (ADR-050): a still gradient above every layer.
          if (tintColors != null)
            IgnorePointer(
              child: _feather(DecoratedBox(
                key: const Key('heroSeasonTint'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: tintColors,
                    stops: art.heroTintStops,
                  ),
                ),
              )),
            ),
        ]),
      ),
    );
  }
}

/// Gold haze drifting sideways across the whole stage. The strip is the
/// cloud texture, its mirror image, then the texture again, so neighbours
/// meet edge-to-edge without a seam and the loop restarts on an identical
/// frame; a vertical alpha ramp keeps it a soft veil with no box edge.
class _HazeDrift extends StatelessWidget {
  final Animation<double> clock;
  const _HazeDrift({required this.clock});

  static Shader _veil(Rect r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final (a, _) in HeroAmbientSpec.hazeVeil) Color.fromRGBO(0, 0, 0, a)],
        stops: [for (final (_, s) in HeroAmbientSpec.hazeVeil) s],
      ).createShader(r);

  @override
  Widget build(BuildContext context) => ShaderMask(
        key: const Key('heroHaze'),
        blendMode: BlendMode.dstIn,
        shaderCallback: _veil,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final px = w.isFinite ? (w * dpr).round().clamp(1, ArtAssets.pixelWidth(ArtAssets.clouds)!) : 960;
          Widget tile(bool mirror) {
            final img = Image.asset(ArtAssets.clouds, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: px);
            return SizedBox(width: w, height: h, child: mirror ? Transform.flip(flipX: true, child: img) : img);
          }

          return AnimatedBuilder(
            animation: clock,
            child: OverflowBox(
              // Physical left (not start): in RTL a start-aligned strip would
              // hang off the right edge and leave an empty band (a hard edge).
              alignment: Alignment.topLeft,
              minWidth: w * 3,
              maxWidth: w * 3,
              child: Row(textDirection: TextDirection.ltr, children: [tile(false), tile(true), tile(false)]),
            ),
            builder: (context, child) => Transform.translate(
              offset: Offset(-2 * w * clock.value, 0),
              child: child,
            ),
          );
        }),
      );
}

/// Soft cream glow behind hero / header text so it keeps AA contrast over any
/// part of the painting. An elliptical radial glow that bleeds past the text
/// box and fades to nothing well inside the bleed — never a visible box.
class TextScrim extends StatelessWidget {
  final Widget child;
  final double opacity;

  /// How far the glow spreads beyond the text box on each side.
  final EdgeInsets bleed;
  const TextScrim({
    super.key,
    required this.child,
    this.opacity = 0.86,
    this.bleed = const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
  });

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -bleed.left,
            right: -bleed.right,
            top: -bleed.top,
            bottom: -bleed.bottom,
            child: IgnorePointer(
              child: CustomPaint(key: Key('textScrimGlow'), painter: _GlowPainter(context.pal.background, opacity)),
            ),
          ),
          child,
        ],
      );
}

/// An ellipse-shaped radial glow filling its box and reaching zero alpha
/// exactly at the box's inscribed ellipse (so nothing is left at the edges).
class _GlowPainter extends CustomPainter {
  final Color color;
  final double opacity;
  _GlowPainter(this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rx = size.width / 2, ry = size.height / 2;
    canvas.save();
    canvas.translate(rx, ry);
    canvas.scale(1, ry / rx);
    final r = Rect.fromCircle(center: Offset.zero, radius: rx);
    // Eased falloff: a plateau behind the words, then a long soft tail.
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          for (final a in const [1.0, 0.9, 0.62, 0.3, 0.1, 0.0]) color.withValues(alpha: opacity * a),
        ],
        stops: const [0, 0.38, 0.6, 0.78, 0.9, 1],
      ).createShader(r);
    canvas.drawCircle(Offset.zero, rx, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color || old.opacity != opacity;
}
