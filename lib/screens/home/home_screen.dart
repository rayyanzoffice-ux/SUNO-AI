import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/suno_logo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.navy,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'AI SAFETY COMPANION',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.7,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SunoLogo(size: 118),
                  const SizedBox(height: 26),
                  const Text(
                    'SUNO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 7,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'It listens for danger,\nnot conversations.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD2D8E5),
                      fontSize: 19,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.safe,
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Private. On-device. Always ready.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  PrimaryActionButton(
                    label: 'START MONITORING',
                    icon: Icons.mic_rounded,
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.monitoring),
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    label: 'Trusted Contacts',
                    outlined: true,
                    color: Colors.white30,
                    foregroundColor: Colors.white70,
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
