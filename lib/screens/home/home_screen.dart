import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.shield_rounded, size: 42),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'SUNO',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                    ),
                  ),
                  const Text(
                    'AI Safety Companion',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'It listens for danger, not conversations.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 17,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  PrimaryActionButton(
                    label: 'START MONITORING',
                    icon: Icons.graphic_eq_rounded,
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.monitoring),
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    label: 'Trusted Contacts',
                    outlined: true,
                    icon: Icons.people_outline,
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.contactsSetup),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
