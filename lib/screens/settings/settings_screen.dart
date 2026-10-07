import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

/// App settings. Currently holds one section: language, with the
/// "Change language" button that opens the language picker.
class SettingsScreen extends StatelessWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LocaleController.instance,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [_LanguageSettingsCard()],
      ),
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
                const Icon(Icons.language_rounded, color: AppColors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.settingsLanguage,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        current.nativeName,
                        locale: current.locale,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
