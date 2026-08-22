import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/detection_result.dart';

class RiskBadge extends StatelessWidget {
  const RiskBadge({required this.score, required this.level, super.key});
  final int score;
  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = score < 40
        ? AppColors.safe
        : score < 70
        ? AppColors.warning
        : AppColors.emergency;
    final label = score < 40
        ? 'Low'
        : score < 70
        ? 'Medium'
        : 'Critical';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$score% $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
