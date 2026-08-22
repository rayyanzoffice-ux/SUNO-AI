import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/detection_result.dart';

class RiskBadge extends StatelessWidget {
  const RiskBadge({required this.score, required this.level, super.key});
  final int score;
  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      RiskLevel.low => AppColors.safe,
      RiskLevel.medium => AppColors.warning,
      RiskLevel.high || RiskLevel.critical => AppColors.emergency,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$score% ${level.name[0].toUpperCase()}${level.name.substring(1)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}
