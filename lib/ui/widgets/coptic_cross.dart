import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';

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
  final Color color;
  const CopticCross({super.key, this.size = 32, this.color = const Color(0xFFC9A227)});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _CrossPainter(color)));
}

class _CrossPainter extends CustomPainter {
  final Color color;
  _CrossPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()..color = color;
    final arm = s * 0.16; // half-width of an arm
    final len = s * 0.34; // centre -> trefoil
    final r = s * 0.075; // trefoil circle radius
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * 3.14159265 / 2);
      // arm (slightly flared)
      final path = Path()
        ..moveTo(-arm * 0.7, 0)
        ..lineTo(-arm, -len)
        ..lineTo(arm, -len)
        ..lineTo(arm * 0.7, 0)
        ..close();
      canvas.drawPath(path, p);
      // three balls
      canvas.drawCircle(Offset(0, -len - r * 0.9), r, p);
      canvas.drawCircle(Offset(-arm, -len), r, p);
      canvas.drawCircle(Offset(arm, -len), r, p);
      canvas.restore();
    }
    canvas.drawCircle(c, arm * 0.9, p);
    canvas.drawCircle(c, arm * 0.45, Paint()..color = Colors.white.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _CrossPainter old) => old.color != color;
}
