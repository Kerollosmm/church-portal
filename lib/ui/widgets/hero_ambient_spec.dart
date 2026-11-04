import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Pure geometry and timing shared by the hero's ambient layers: the Flutter
/// painter ([LightRaysPainter], Android / iOS / reduced motion) and the web
/// DOM layer (`hero_ambient_web.dart`, ADR-037), so both draw the same rays
/// and run the same cycles.
class HeroAmbientSpec {
  HeroAmbientSpec._();

  /// The master clock of the hero (Ken Burns, haze drift): one cycle.
  static const clock = Duration(seconds: 60);

  /// The haze strip crosses two stage widths per [clock] cycle.
  static const hazeCycle = clock;

  /// One light-ray shimmer cycle (the clock runs the shimmer 8x per cycle).
  static const shimmerCycle = Duration(milliseconds: 7500);

  /// Shimmer of the still rays (no ambient motion).
  static const stillShimmer = 0.25;

  /// Number of pre-rendered shimmer phases the web layer crossfades between.
  static const shimmerPhases = 3;

  /// Vertical veil of the drifting haze: (alpha, stop) pairs, top to bottom.
  static const hazeVeil = <(double, double)>[(0x5C / 255, 0), (0x47 / 255, 0.35), (0x1F / 255, 0.62), (0, 0.9)];

  /// Weight of pre-rendered phase [k] (of [n], evenly spaced over one
  /// shimmer cycle) at shimmer position [t] (0..1): a cyclic triangle, so
  /// the weights of all phases always sum to 1 (linear interpolation between
  /// the two nearest phases).
  static double phaseWeight(int k, int n, double t) {
    var d = (t - k / n) % 1;
    if (d > 0.5) d = 1 - d;
    return math.max(0, 1 - d * n);
  }

  static const rayCount = 14;
  static const rayColor = (255, 238, 196);

  /// The rays for a stage of [size] at shimmer [shimmer] (0..1) and
  /// [strength]: a fan of 14 soft beams from just above the top centre.
  static List<LightRay> rays(Size size, {required double shimmer, double strength = 1}) {
    final origin = Offset(size.width / 2, -size.height * 0.08);
    final reach = size.height * 1.05;
    return [
      for (var i = 0; i < rayCount; i++)
        () {
          final t = i / (rayCount - 1);
          final angle = math.pi / 2 + (t - 0.5) * 1.5; // fan of ~86 degrees
          final width = 0.035 + 0.02 * math.sin(i * 1.7);
          final phase = math.sin((shimmer * 2 * math.pi) + i * 0.9) * 0.5 + 0.5;
          final alpha = (0.10 + 0.16 * phase) * strength;
          final a1 = angle - width / 2, a2 = angle + width / 2;
          return LightRay(
            origin: origin,
            reach: reach,
            p1: Offset(origin.dx + math.cos(a1) * reach, origin.dy + math.sin(a1) * reach),
            p2: Offset(origin.dx + math.cos(a2) * reach, origin.dy + math.sin(a2) * reach),
            alpha: alpha,
          );
        }(),
    ];
  }

  /// Blur (standard deviation, logical px) that feathers a ray's sides.
  static double raySigma(Size size) => math.max(4, size.width * 0.012);
}

/// One ray: a thin triangle from [origin] to [p1]/[p2], filled with a radial
/// gradient of [HeroAmbientSpec.rayColor] centred [reach] above [origin]
/// (radius 2 x [reach]) from [alpha] to transparent.
class LightRay {
  final Offset origin;
  final double reach;
  final Offset p1;
  final Offset p2;
  final double alpha;
  const LightRay({required this.origin, required this.reach, required this.p1, required this.p2, required this.alpha});

  /// Centre and radius of the gradient (Flutter's `RadialGradient(center:
  /// topCenter, radius: 1)` over the circle of [reach] around [origin]).
  Offset get gradientCenter => Offset(origin.dx, origin.dy - reach);
  double get gradientRadius => 2 * reach;
}
