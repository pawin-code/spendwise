import 'package:flutter/material.dart';
import 'package:spendwise/app/theme.dart';

/// The SpendWise mark: a wallet with a growth arrow and a coin, drawn in code
/// (an original design; it matches the launcher icon).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SpendWise logo',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.26),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.emeraldBright, Brand.emerald, Brand.navy],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    // Wallet body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.2, s * 0.34, s * 0.6, s * 0.4),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(body, Paint()..color = Colors.white);
    // Wallet flap shadow line.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.2, s * 0.34, s * 0.6, s * 0.09),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = const Color(0x22000000),
    );
    // Clasp.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.58, s * 0.48, s * 0.22, s * 0.13),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = Brand.emerald,
    );
    canvas.drawCircle(
      Offset(s * 0.65, s * 0.545),
      s * 0.025,
      Paint()..color = Colors.white,
    );
    // Growth arrow.
    final arrow = Path()
      ..moveTo(s * 0.27, s * 0.64)
      ..lineTo(s * 0.37, s * 0.54)
      ..lineTo(s * 0.43, s * 0.59)
      ..lineTo(s * 0.5, s * 0.5);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Brand.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Coin.
    final coin = Offset(s * 0.7, s * 0.27);
    canvas.drawCircle(coin, s * 0.12, Paint()..color = const Color(0xFFFBBF24));
    canvas.drawCircle(
      coin,
      s * 0.12,
      Paint()
        ..color = const Color(0xFFB45309)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: const Color(0xFF7C2D12),
          fontSize: s * 0.15,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, coin - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
