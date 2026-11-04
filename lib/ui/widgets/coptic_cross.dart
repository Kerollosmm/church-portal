import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// A Coptic cross (equal arms ending in three-point trefoils), drawn so the
/// app needs no image assets for its logo / hero ornament.
/// The parish's official round seal (`assets/branding/seal.png`, regenerated
/// by `tool/gen_branding.sh`). Falls back to the drawn [CopticCross] if the
/// asset cannot be loaded.
class ChurchSeal extends StatelessWidget {
  final double size;
  const ChurchSeal({super.key, this.size = 40});

  static const asset = 'assets/branding/seal.png';

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: context.tr('logoLabel'),
        child: SizedBox.square(
          dimension: size,
          child: Image.asset(
            asset,
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => CopticCross(size: size),
          ),
        ),
      );
}

class CopticCross extends StatelessWidget {
  final double size;
  /// null = the theme's cross colour (gold; ash on Holy Week — ADR-043).
  final Color? color;
  const CopticCross({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _CrossPainter(color ?? context.pal.cross)));
}

class _CrossPainter extends CustomPainter {
  final Color color;
  _CrossPainter(this.color);

  // Geometry on a 100-unit grid (same drawing as the design board): four
  // straight arms, each ending in a trefoil of three balls, and a centre ring.
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()..color = color;
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 2);
      canvas.scale(k);
      canvas.drawRect(const Rect.fromLTRB(-7, -30, 7, -8), p);
      canvas.drawCircle(const Offset(0, -40), 6.5, p);
      canvas.drawCircle(const Offset(-11, -31), 5.5, p);
      canvas.drawCircle(const Offset(11, -31), 5.5, p);
      canvas.restore();
    }
    // Centre ring (hollow, so it reads on any ground).
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: c, radius: 15 * k))
      ..addOval(Rect.fromCircle(center: c, radius: 7.5 * k));
    canvas.drawPath(ring, p);
  }

  @override
  bool shouldRepaint(covariant _CrossPainter old) => old.color != color;
}
