import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    super.key,
  });
  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Icon(icon ?? Icons.circle, color: color, size: 22),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
