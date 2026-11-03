import 'package:material_ui/material_ui.dart';

/// Feathers a full-bleed hero layer into the page: fully opaque at the top,
/// dissolving to transparent at the bottom edge, so the page backdrop shows
/// through and there is no line where the hero ends. [cssMask] is the same
/// ramp for the web `<video>` (a platform view cannot take a ShaderMask).
class BottomFeather extends StatelessWidget {
  final Widget child;
  const BottomFeather({super.key, required this.child});

  /// Where the dissolve starts (fraction of the height).
  static const start = 0.62;

  /// A smoothstep ramp sampled at 11 stops: no slope break where it starts or
  /// ends, so the eye sees no line there (a linear ramp reads as an edge).
  static final List<double> stops = [
    0.0,
    for (var i = 0; i <= 10; i++) start + (1 - start) * i / 10,
  ];
  static final List<double> alphas = [
    1.0,
    for (var i = 0; i <= 10; i++) _ease(i / 10),
  ];
  static double _ease(double t) => double.parse((1 - t * t * (3 - 2 * t)).toStringAsFixed(3));

  static String get cssMask {
    final parts = [
      for (var i = 0; i < stops.length; i++) 'rgba(0,0,0,${alphas[i]}) ${(stops[i] * 100).toStringAsFixed(1)}%',
    ];
    return 'linear-gradient(to bottom, ${parts.join(', ')})';
  }

  static Shader shader(Rect r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final a in alphas) Color.fromRGBO(0, 0, 0, a)],
        stops: stops,
      ).createShader(r);

  // The mask rect is the layer's (fractional) size; on the web the last,
  // partially covered device row escapes it and shows unmasked as a thin dark
  // line. The feather is ~0 there anyway, so trim the last 2 px.
  @override
  Widget build(BuildContext context) => ClipRect(
        clipper: const _TrimBottom(2),
        child: ShaderMask(key: const Key('heroFeather'), blendMode: BlendMode.dstIn, shaderCallback: shader, child: child),
      );
}

class _TrimBottom extends CustomClipper<Rect> {
  final double px;
  const _TrimBottom(this.px);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height > px ? size.height - px : 0);

  @override
  bool shouldReclip(_TrimBottom old) => old.px != px;
}
