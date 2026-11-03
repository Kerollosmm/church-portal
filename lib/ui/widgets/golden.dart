import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion_env.dart';
import '../../core/theme.dart';
import 'coptic_cross.dart';
import 'hero_feather.dart';
import 'hero_video.dart';

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
  // Muted loops cut from seconds 3-10 of the Gemini clip, cross-faded at the
  // seam (6 s, no audio): 1280x720 for tablets / desktops, a 404x720 centre
  // crop on the church for phones. Posters are their first frames.
  static const heroVideo = 'assets/video/hero_clouds.mp4';
  static const heroVideoTall = 'assets/video/hero_clouds_tall.mp4';
  static const heroPoster = 'assets/art/hero_poster.webp';
  static const heroPosterTall = 'assets/art/hero_poster_tall.webp';

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
        // White seal on maroon: a thin gold ring and a soft shadow lift it.
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [AppColors.goldLight, AppColors.gold, AppColors.goldLight, AppColors.gold, AppColors.goldLight]),
          boxShadow: [BoxShadow(color: Color(0x73200000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: ClipOval(
          child: ColoredBox(
            color: Colors.white,
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
        // Feathered sides: a ray is a soft beam, never a hard-edged wedge.
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(4, size.width * 0.012))
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
  const HeroStage({
    super.key,
    required this.image,
    this.alignment = Alignment.center,
    this.motion = true,
    this.video,
    this.poster,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambient = ambientMotionOn(context, adminOn: widget.motion);
    _videoOn = widget.video != null && heroVideoAllowed(context, adminOn: widget.motion);
    // Decode the still before it is needed (no pop-in, no flash on swaps).
    precacheImage(AssetImage(_still), context).ignore();
    _sync();
  }

  String get _still => _videoOn ? (widget.poster ?? widget.image) : widget.image;

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
    if (_videoOn && mounted) setState(() {}); // pause / resume the video
  }

  void _sync() {
    final run = _ambient && visibleInViewport;
    if (run && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!run && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Widget _feather(Widget child) => widget.fadeBottom ? BottomFeather(child: child) : child;

  @override
  Widget build(BuildContext context) {
    final still = Image.asset(
      _still,
      key: const Key('heroStill'),
      fit: BoxFit.cover,
      alignment: widget.alignment,
      gaplessPlayback: true,
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
    return ExcludeSemantics(
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: _feather(kenBurns
                ? AnimatedBuilder(
                    animation: _clock,
                    child: still,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + 0.06 * (0.5 - 0.5 * math.cos(_clock.value * 2 * math.pi)),
                      child: child,
                    ),
                  )
                : still),
          ),
          if (_videoOn)
            HeroVideo(
              key: ValueKey(widget.video),
              asset: widget.video!,
              alignment: widget.alignment,
              play: visibleInViewport,
            ),
          if (_ambient) RepaintBoundary(child: _feather(_HazeDrift(clock: _clock))),
          if (widget.rays > 0)
            RepaintBoundary(
              child: _feather(AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => CustomPaint(
                  painter: LightRaysPainter(shimmer: _ambient ? _clock.value * 8 % 1 : 0.25, strength: widget.rays),
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

  static Shader _veil(Rect r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x5C000000), Color(0x47000000), Color(0x1F000000), Color(0x00000000)],
        stops: [0, 0.35, 0.62, 0.9],
      ).createShader(r);

  @override
  Widget build(BuildContext context) => ShaderMask(
        key: const Key('heroHaze'),
        blendMode: BlendMode.dstIn,
        shaderCallback: _veil,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          Widget tile(bool mirror) {
            final img = Image.asset(ArtAssets.clouds, fit: BoxFit.cover, gaplessPlayback: true);
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
              child: CustomPaint(key: const Key('textScrimGlow'), painter: _GlowPainter(AppColors.cream, opacity)),
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
