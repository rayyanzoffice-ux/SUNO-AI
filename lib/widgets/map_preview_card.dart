import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class MapPreviewCard extends StatelessWidget {
  const MapPreviewCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF3EC),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.border),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _MapPainter())),
        const Center(
          child: Icon(
            Icons.location_on_rounded,
            color: AppColors.emergency,
            size: 42,
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.near_me_rounded, color: AppColors.purple, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Main Boulevard, Gulberg\nLahore, Pakistan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.safe,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    final minor = Paint()
      ..color = const Color(0xFFD4E3D9)
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(0, size.height * .3),
      Offset(size.width, size.height * .72),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .2, 0),
      Offset(size.width * .62, size.height),
      road,
    );
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(size.width * i / 5, 0),
        Offset(size.width * (i - 1) / 5, size.height),
        minor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
