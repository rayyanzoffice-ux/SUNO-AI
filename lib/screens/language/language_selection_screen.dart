import 'package:flutter/material.dart';

import '../../core/l10n/app_locales.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/suno_logo.dart';

/// Lets the person pick the app language.
///
/// Used twice: as the very first screen on a fresh install ([isFirstRun] true:
/// dark navy like Home, no back button, Continue goes to Home) and from
/// Settings ([isFirstRun] false: light like History/Contacts, back arrow,
/// Continue just closes). Tapping a language applies it instantly, so the
/// screen itself is the live preview.
class LanguageSelectionScreen extends StatefulWidget {
  /// Creates the picker. Set [isFirstRun] on the first-launch instance.
  const LanguageSelectionScreen({super.key, this.isFirstRun = false});

  /// Whether this is the first-launch screen (dark theme, no back navigation).
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
  Widget build(BuildContext context) {
    final palette = widget.isFirstRun
        ? _PickerPalette.dark
        : _PickerPalette.light;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        backgroundColor: palette.background,
        appBar: widget.isFirstRun
            ? null
            : AppBar(title: Text(context.l10n.settingsChangeLanguage)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                _PickerHeader(palette: palette, isFirstRun: widget.isFirstRun),
                const SizedBox(height: 20),
                Expanded(
                  child: _LanguageList(
                    palette: palette,
                    selectedCode: _controller.language.code,
                    onSelect: _select,
                  ),
                ),
                const SizedBox(height: 14),
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
}

/// Colours for the picker, taken only from the existing app palette.
class _PickerPalette {
  const _PickerPalette({
    required this.background,
    required this.title,
    required this.body,
    required this.tile,
    required this.tileBorder,
    required this.tileSelected,
    required this.ring,
  });

  /// Scaffold background; `null` keeps the app theme's own background.
  final Color? background;
  final Color title;
  final Color body;
  final Color tile;
  final Color tileBorder;
  final Color tileSelected;
  final Color ring;

  /// First-run look, same family as the Home screen.
  static final dark = _PickerPalette(
    background: AppColors.navy,
    title: Colors.white,
    body: Colors.white60,
    tile: AppColors.navyLight,
    tileBorder: Colors.white12,
    tileSelected: AppColors.purple.withValues(alpha: .25),
    ring: Colors.white30,
  );

  /// Settings look, same family as History and Contacts.
  static final light = _PickerPalette(
    background: null,
    title: AppColors.navy,
    body: AppColors.textMuted,
    tile: Colors.white,
    tileBorder: AppColors.border,
    tileSelected: AppColors.purple.withValues(alpha: .08),
    ring: AppColors.border,
  );
}

/// First run: logo + title + subtitle (centred, like Home's hero).
/// From Settings: one muted hint line, like the line under History's title.
class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.palette, required this.isFirstRun});

  final _PickerPalette palette;
  final bool isFirstRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!isFirstRun) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          l10n.languageSettingsHint,
          style: TextStyle(color: palette.body, height: 1.5),
        ),
      );
    }
    return Column(
      children: [
        const SunoLogo(size: 76),
        const SizedBox(height: 18),
        Text(
          l10n.languageChooseTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.title,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.languageChooseSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.body, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }
}

/// Scrollable list of every supported language.
class _LanguageList extends StatelessWidget {
  const _LanguageList({
    required this.palette,
    required this.selectedCode,
    required this.onSelect,
  });

  final _PickerPalette palette;
  final String selectedCode;
  final ValueChanged<SunoLanguage> onSelect;

  @override
  Widget build(BuildContext context) => ListView.separated(
    itemCount: SunoLanguages.all.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      final language = SunoLanguages.all[index];
      return _LanguageTile(
        palette: palette,
        language: language,
        selected: language.code == selectedCode,
        onTap: () => onSelect(language),
      );
    },
  );
}

/// One selectable language row. The native name is rendered with its own
/// locale so the correct font/glyph variant is chosen. The ink splash lives
/// inside the animated container so it stays visible on the coloured tile.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.palette,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final _PickerPalette palette;
  final SunoLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${language.nativeName}, ${language.englishName}',
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? palette.tileSelected : palette.tile,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.purple : palette.tileBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(child: _LanguageNames(palette, language)),
                _SelectionMark(palette: palette, selected: selected),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Native name (large, in its own script) over the English name (small).
class _LanguageNames extends StatelessWidget {
  const _LanguageNames(this.palette, this.language);

  final _PickerPalette palette;
  final SunoLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        language.nativeName,
        locale: language.locale,
        style: TextStyle(
          color: palette.title,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
      Text(
        language.englishName,
        style: TextStyle(color: palette.body, fontSize: 12),
      ),
    ],
  );
}

/// Filled purple check when selected, empty ring otherwise.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.palette, required this.selected});

  final _PickerPalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.purple : Colors.transparent,
      border: Border.all(
        color: selected ? AppColors.purple : palette.ring,
        width: 1.6,
      ),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
        : null,
  );
}
