import 'package:flutter/material.dart';

import '../../core/l10n/app_locales.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

/// Lets the person pick the app language.
///
/// Used twice: as the very first screen on a fresh install ([isFirstRun] true,
/// no back button, Continue goes to Home) and from Settings ([isFirstRun]
/// false, back arrow, Continue just closes). Tapping a language applies it
/// instantly, so the screen itself is the live preview.
class LanguageSelectionScreen extends StatefulWidget {
  /// Creates the picker. Set [isFirstRun] on the first-launch instance.
  const LanguageSelectionScreen({super.key, this.isFirstRun = false});

  /// Whether this is the first-launch screen (no back navigation).
  final bool isFirstRun;

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final LocaleController _controller = LocaleController.instance;

  /// Applies [language] and warns (without blocking) if it could not be saved.
  Future<void> _select(SunoLanguage language) async {
    final saved = await _controller.setLanguage(language);
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.languageSaveFailed)),
    );
  }

  /// Leaves the picker: to Home on first run, back to Settings otherwise.
  void _continue() {
    if (widget.isFirstRun) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !widget.isFirstRun,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PickerHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: _LanguageList(
                  selectedCode: _controller.language.code,
                  onSelect: _select,
                ),
              ),
              const SizedBox(height: 12),
              PrimaryActionButton(
                label: context.l10n.languageContinue,
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Title + subtitle above the language list.
class _PickerHeader extends StatelessWidget {
  const _PickerHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.languageChooseTitle,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        context.l10n.languageChooseSubtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
      ),
    ],
  );
}

/// Scrollable list of every supported language.
class _LanguageList extends StatelessWidget {
  const _LanguageList({required this.selectedCode, required this.onSelect});

  final String selectedCode;
  final ValueChanged<SunoLanguage> onSelect;

  @override
  Widget build(BuildContext context) => ListView.separated(
    itemCount: SunoLanguages.all.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      final language = SunoLanguages.all[index];
      return _LanguageTile(
        language: language,
        selected: language.code == selectedCode,
        onTap: () => onSelect(language),
      );
    },
  );
}

/// One selectable language row. The native name is rendered with its own
/// locale so the correct font/glyph variant is chosen.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final SunoLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${language.nativeName}, ${language.englishName}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.purple.withValues(alpha: .25)
                : AppColors.navyLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.purple : Colors.white12,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeName,
                      locale: language.locale,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    Text(
                      language.englishName,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? AppColors.purple : Colors.white30,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
