import 'package:flutter/widgets.dart';
import 'package:suno_ai/l10n/app_localizations.dart';

import 'locale_controller.dart';

export 'package:suno_ai/l10n/app_localizations.dart';

/// `context.l10n.someKey` — the translated strings for the current language.
extension L10nContext on BuildContext {
  /// The generated localizations for this widget's locale.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Translated strings for code that has **no BuildContext** (services,
/// notification handlers). Reads the language straight from
/// [LocaleController], so it is always in sync with the UI.
///
/// Use ONLY for text a person will actually read (error banners, status text,
/// notification titles). Do not use it for developer exceptions or logs.
AppLocalizations get tr =>
    lookupAppLocalizations(LocaleController.instance.locale);
