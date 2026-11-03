import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import 'coptic_cross.dart';

/// Running two-strand interlace (guilloche) in gold leaf: the band that binds
/// the header, page headers and footer (docs/design/direction.md §5). Static,
/// decorative and hidden from screen readers.
class InterlaceBand extends StatelessWidget {
  final double height;
  final Color background;
  final Color color;
  final Color edge;
  const InterlaceBand({
    super.key,
    this.height = 12,
    this.background = AppColors.parchment,
    this.color = AppColors.gold,
    this.edge = AppColors.hairline,
  });

  /// The dark variant used on the footer's top edge.
  const InterlaceBand.dark({super.key, this.height = 12})
      : background = AppColors.night,
        color = AppColors.gold,
        edge = const Color(0xFF3A2A1C);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _InterlacePainter(background, color, edge)),
        ),
      );
}

class _InterlacePainter extends CustomPainter {
  final Color bg, color, edge;
  _InterlacePainter(this.bg, this.color, this.edge);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final line = Paint()
      ..color = edge
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 0.5), Offset(size.width, 0.5), line);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), line);
    final h = size.height, mid = h / 2, amp = (h / 2) - 1.5;
    const period = 24.0;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final up = Path(), down = Path();
    up.moveTo(0, mid);
    down.moveTo(0, mid);
    for (double x = 0; x <= size.width + 1; x += 1) {
      final y = math.sin(x / period * 2 * math.pi) * amp;
      up.lineTo(x, mid - y);
      down.lineTo(x, mid + y);
    }
    canvas.drawPath(up, p);
    canvas.drawPath(down, p);
    final dot = Paint()..color = color;
    for (double x = period / 2; x <= size.width; x += period / 2) {
      canvas.drawCircle(Offset(x, mid), 1.3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _InterlacePainter old) => old.bg != bg || old.color != color || old.edge != edge;
}

/// Round-topped (semicircular) path: the iconostasis arch.
Path archPath(Size s, {double bottomRadius = 3}) {
  final r = s.width / 2;
  final top = math.min(r, s.height);
  return Path()
    ..moveTo(0, top)
    ..arcToPoint(Offset(s.width, top), radius: Radius.circular(r))
    ..lineTo(s.width, s.height - bottomRadius)
    ..quadraticBezierTo(s.width, s.height, s.width - bottomRadius, s.height)
    ..lineTo(bottomRadius, s.height)
    ..quadraticBezierTo(0, s.height, 0, s.height - bottomRadius)
    ..close();
}

class _ArchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => archPath(size);
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Gold-leaf arch frame (2 px gold + inner hairline) holding an icon or a
/// portrait. [child] is clipped to the arch.
class ArchFrame extends StatelessWidget {
  final double width, height;
  final Widget child;
  final double inset;
  const ArchFrame({super.key, required this.width, required this.height, required this.child, this.inset = 5});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _ArchBorderPainter(inset),
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: ClipPath(clipper: _ArchClipper(), child: SizedBox.expand(child: child)),
          ),
        ),
      );
}

class _ArchBorderPainter extends CustomPainter {
  final double inset;
  _ArchBorderPainter(this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(archPath(size), Paint()..color = AppColors.vellum);
    canvas.drawPath(
        archPath(size).shift(Offset.zero),
        Paint()
          ..color = AppColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    if (inset >= 4) {
      final i = inset / 2 + 0.5;
      canvas.save();
      canvas.translate(i, i);
      canvas.drawPath(
          archPath(Size(size.width - 2 * i, size.height - 2 * i)),
          Paint()
            ..color = AppColors.hairline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ArchBorderPainter old) => old.inset != inset;
}

/// Outline-only arch used as a faint watermark at the end edge of page headers.
class ArchWatermark extends StatelessWidget {
  final double width, height;
  final Color color;
  const ArchWatermark({super.key, required this.width, required this.height, this.color = AppColors.gold});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(width: width, height: height, child: CustomPaint(painter: _WatermarkPainter(color))),
      );
}

class _WatermarkPainter extends CustomPainter {
  final Color color;
  _WatermarkPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    canvas.drawPath(archPath(size, bottomRadius: 0), p);
    canvas.save();
    canvas.translate(10, 10);
    canvas.drawPath(archPath(Size(size.width - 20, size.height - 10), bottomRadius: 0),
        p..color = color.withValues(alpha: 0.22)..strokeWidth = 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter old) => old.color != color;
}

/// Empty-arch fallback: plaster ground with a Coptic cross (no image needed).
class ArchCrossFill extends StatelessWidget {
  const ArchCrossFill({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.parchment,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(
              builder: (_, c) => CopticCross(size: c.maxWidth, color: AppColors.gold),
            )),
          ),
        ),
      );
}
