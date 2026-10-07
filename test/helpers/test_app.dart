import 'package:flutter/material.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/l10n/l10n.dart';

/// Wraps [child] in a [MaterialApp] carrying SUNO's localizations for
/// [language].
///
/// Screens read their text through `context.l10n`, so a bare `MaterialApp`
/// throws before a screen can render at all. Tests that navigate use [routes]
/// exactly as they would with `MaterialApp`.
Widget localizedTestApp(
  Widget child, {
  SunoLanguage language = SunoLanguages.english,
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) => MaterialApp(
  locale: language.locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  routes: routes,
  home: child,
);
