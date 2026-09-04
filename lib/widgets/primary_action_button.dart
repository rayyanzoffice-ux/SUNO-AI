import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.color,
    this.outlined = false,
    this.icon,
    this.foregroundColor,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? foregroundColor;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.purple;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 9)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    );
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: foregroundColor ?? accent,
                side: BorderSide(color: accent, width: 1.5),
                shape: shape,
              ),
              onPressed: onPressed,
              child: child,
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: foregroundColor ?? Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: .45),
                shape: shape,
              ),
              onPressed: onPressed,
              child: child,
            ),
    );
  }
}
