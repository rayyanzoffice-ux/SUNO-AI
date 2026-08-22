import 'package:flutter/material.dart';

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.color,
    this.outlined = false,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(onPressed: onPressed, child: child)
          : FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: onPressed,
              child: child,
            ),
    );
  }
}
