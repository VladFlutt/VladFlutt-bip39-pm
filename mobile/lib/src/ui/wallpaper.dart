import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Фон с тонкими контурами символов известных криптовалют поверх градиента.
class CryptoWallpaper extends StatelessWidget {
  final Widget child;

  const CryptoWallpaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              scheme.surface,
            ),
            Color.alphaBlend(
              scheme.tertiary.withValues(alpha: 0.10),
              scheme.surface,
            ),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _LogoPatternPainter(scheme.onSurface.withValues(alpha: 0.07)),
        child: child,
      ),
    );
  }
}

typedef _Glyph = void Function(Canvas canvas, Paint paint);

class _LogoPatternPainter extends CustomPainter {
  final Color color;

  _LogoPatternPainter(this.color);

  static const _cell = 96.0;
  static final List<_Glyph> _glyphs = [
    _bitcoin,
    _ethereum,
    _litecoin,
    _tether,
    _solana,
    _dogecoin,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // Детерминированный «случайный» узор: картинка не прыгает при перерисовке.
    final rnd = math.Random(39);
    final rows = (size.height / _cell).ceil() + 1;
    final cols = (size.width / _cell).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final glyph = _glyphs[(r * 5 + c * 2) % _glyphs.length];
        final dx =
            c * _cell + (r.isOdd ? _cell / 2 : 0) + rnd.nextDouble() * 12;
        final dy = r * _cell + rnd.nextDouble() * 12;
        final scale = 18 + rnd.nextDouble() * 10;
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate((rnd.nextDouble() - 0.5) * 0.6);
        canvas.scale(scale);
        glyph(canvas, paint..strokeWidth = 1.6 / scale);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_LogoPatternPainter old) => old.color != color;

  // Все символы рисуются в квадрате [-1, 1].

  static void _bitcoin(Canvas c, Paint p) {
    c.drawCircle(Offset.zero, 1, p);
    final b = Path()
      ..moveTo(-0.3, -0.5)
      ..lineTo(0.1, -0.5)
      ..arcToPoint(const Offset(0.1, 0), radius: const Radius.circular(0.25))
      ..lineTo(-0.3, 0)
      ..moveTo(0.1, 0)
      ..arcToPoint(const Offset(0.1, 0.5), radius: const Radius.circular(0.25))
      ..lineTo(-0.3, 0.5)
      ..moveTo(-0.2, -0.5)
      ..lineTo(-0.2, 0.5)
      ..moveTo(-0.08, -0.68)
      ..lineTo(-0.08, -0.5)
      ..moveTo(0.1, -0.68)
      ..lineTo(0.1, -0.5)
      ..moveTo(-0.08, 0.5)
      ..lineTo(-0.08, 0.68)
      ..moveTo(0.1, 0.5)
      ..lineTo(0.1, 0.68);
    c.drawPath(b, p);
  }

  static void _ethereum(Canvas c, Paint p) {
    final top = Path()
      ..moveTo(0, -1)
      ..lineTo(0.6, 0.05)
      ..lineTo(0, 0.38)
      ..lineTo(-0.6, 0.05)
      ..close()
      ..moveTo(-0.6, 0.05)
      ..lineTo(0, -0.22)
      ..lineTo(0.6, 0.05)
      ..moveTo(0, -1)
      ..lineTo(0, 0.38);
    final bottom = Path()
      ..moveTo(-0.6, 0.22)
      ..lineTo(0, 0.55)
      ..lineTo(0.6, 0.22)
      ..lineTo(0, 1)
      ..close();
    c.drawPath(top, p);
    c.drawPath(bottom, p);
  }

  static void _litecoin(Canvas c, Paint p) {
    c.drawCircle(Offset.zero, 1, p);
    final l = Path()
      ..moveTo(-0.1, -0.55)
      ..lineTo(-0.25, 0.5)
      ..lineTo(0.45, 0.5)
      ..moveTo(-0.45, 0.1)
      ..lineTo(0.25, -0.15);
    c.drawPath(l, p);
  }

  static void _tether(Canvas c, Paint p) {
    c.drawCircle(Offset.zero, 1, p);
    final t = Path()
      ..moveTo(-0.5, -0.5)
      ..lineTo(0.5, -0.5)
      ..moveTo(0, -0.5)
      ..lineTo(0, 0.6);
    c.drawPath(t, p);
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, -0.12), width: 1.1, height: 0.3),
      p,
    );
  }

  static void _solana(Canvas c, Paint p) {
    for (final (y, flip) in [(-0.55, false), (0.0, true), (0.55, false)]) {
      final s = flip ? -1.0 : 1.0;
      final bar = Path()
        ..moveTo(-0.8 * s + 0.2 * s, y - 0.15)
        ..lineTo(0.8 * s, y - 0.15)
        ..lineTo(0.8 * s - 0.2 * s, y + 0.15)
        ..lineTo(-0.8 * s, y + 0.15)
        ..close();
      c.drawPath(bar, p);
    }
  }

  static void _dogecoin(Canvas c, Paint p) {
    c.drawCircle(Offset.zero, 1, p);
    final d = Path()
      ..moveTo(-0.3, -0.5)
      ..lineTo(0.0, -0.5)
      ..arcToPoint(const Offset(0.0, 0.5), radius: const Radius.circular(0.5))
      ..lineTo(-0.3, 0.5)
      ..close()
      ..moveTo(-0.45, 0)
      ..lineTo(0.1, 0);
    c.drawPath(d, p);
  }
}
