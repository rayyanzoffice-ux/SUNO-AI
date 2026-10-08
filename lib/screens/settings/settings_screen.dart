import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/l10n/text_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

/// App settings. Currently one section: language, with the
/// "Change language" button that opens the language picker.
class SettingsScreen extends StatelessWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LocaleController.instance,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              context.l10n.settingsSubtitle,
              style: const TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            _SectionLabel(context.l10n.settingsSectionLanguage),
            const SizedBox(height: 10),
            const _LanguageSettingsCard(),
          ],
        ),
      ),
    ),
  );
}

/// Small spaced section label, same style as the incident count in History.
/// Letter-spacing is switched off automatically for connected scripts.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: scriptSafeLetterSpacing(context, 1.2),
    ),
  );
}

/// Card showing the current language and the button to change it.
class _LanguageSettingsCard extends StatelessWidget {
  const _LanguageSettingsCard();

  @override
  Widget build(BuildContext context) {
    final current = LocaleController.instance.language;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _TintedIcon(icon: Icons.language_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.nativeName,
                        locale: current.locale,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                      ),
                      Text(
                        current.englishName,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PrimaryActionButton(
              label: context.l10n.settingsChangeLanguage,
              icon: Icons.translate_rounded,
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.languageSelection),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round purple-tinted icon badge, the same treatment the app uses for its
/// status icons.
class _TintedIcon extends StatelessWidget {
  const _TintedIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.purple.withValues(alpha: .1),
    ),
    child: Icon(icon, color: AppColors.purple, size: 24),
  );
}
