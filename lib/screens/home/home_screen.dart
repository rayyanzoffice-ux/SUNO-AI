import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/l10n/text_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/silent_sos_sheet.dart';
import '../../widgets/suno_logo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_rounded, color: Colors.white70, size: 24),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
          ListenableBuilder(
            listenable: SunoRuntimeService.instance,
            builder: (context, _) {
              final count = SunoRuntimeService.instance.storedIncidentCount;
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : '$count'),
                  backgroundColor: AppColors.emergency,
                  alignment: AlignmentDirectional.topStart,
                  offset: const Offset(-4, -4),
                  child: const Icon(
                    Icons.history_rounded,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
                onPressed: () => Navigator.pushNamed(context, AppRoutes.history),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.homeAiSafetyCompanion,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: scriptSafeLetterSpacing(context, 1.7),
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onLongPress: () => showSilentSosSheet(context),
                      child: const SunoLogo(size: 118),
                    ),
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
                    Text(
                      l10n.homeSlogan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD2D8E5),
                        fontSize: 19,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: AppColors.safe,
                          size: 15,
                        ),
                        Text(
                          l10n.homePrivacyLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.homeSosHint,
                      style: const TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                    const Spacer(),
                    PrimaryActionButton(
                      label: l10n.homeStartMonitoring,
                      icon: Icons.mic_rounded,
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.monitoring),
                    ),
                    const SizedBox(height: 12),
                    PrimaryActionButton(
                      label: l10n.homeTrustedContacts,
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
}
