import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class SunoLogo extends StatelessWidget {
  const SunoLogo({this.size = 112, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.purple, AppColors.pink, AppColors.orange],
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.purple.withValues(alpha: .35),
          blurRadius: 30,
          spreadRadius: 2,
        ),
      ],
    ),
    child: CustomPaint(painter: _ListeningMarkPainter()),
  );
}

class _ListeningMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .065
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * .48, size.height * .48);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * .23),
      -1.55,
      4.4,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * .12),
      -1.35,
      3.35,
      false,
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .49, size.height * .58),
      Offset(size.width * .43, size.height * .73),
      paint,
    );
    for (final x in [.68, .78]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: size.width * (x - .45)),
        -1.05,
        2.1,
        false,
        paint..color = Colors.white.withValues(alpha: x == .68 ? .9 : .65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
