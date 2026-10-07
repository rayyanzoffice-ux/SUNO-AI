import 'dart:ui' show PlatformDispatcher, Locale;

import 'package:flutter/foundation.dart';

import '../../backend/profile/locale_repository.dart';
import 'app_locales.dart';

/// Holds the app's current language and persists the user's choice.
///
/// A `ChangeNotifier` singleton, matching how `SunoRuntimeService` is wired.
/// `main()` replaces [instance] with a Hive-backed controller before
/// `runApp`; tests use the default in-memory one.
class LocaleController extends ChangeNotifier {
  /// Creates a controller that reads/writes through [repository].
  LocaleController({required LocaleRepository repository})
    : _repository = repository;

  /// The app-wide controller. Replaced in `main()` with the Hive-backed one.
  static LocaleController instance = LocaleController(
    repository: InMemoryLocaleRepository(),
  );

  final LocaleRepository _repository;
  Locale _locale = const Locale('en');
  bool _hasChosenLanguage = false;

  /// The language the UI is currently shown in.
  Locale get locale => _locale;

  /// True once the user has picked a language (so first-run can be skipped).
  bool get hasChosenLanguage => _hasChosenLanguage;

  /// The [SunoLanguage] entry for the current locale (English if unknown).
  SunoLanguage get language =>
      SunoLanguages.byCode(_locale.languageCode) ?? SunoLanguages.english;

  /// Whether the current language is written right-to-left.
  bool get isRtl => language.isRtl;

  /// Loads the saved language. If none is saved, pre-selects the phone's
  /// language (when supported, otherwise English) without marking it chosen.
  /// Never throws: a storage failure falls back to the device language.
  Future<void> load() async {
    try {
      final saved = SunoLanguages.byCode(await _repository.getLanguageCode());
      if (saved != null) {
        _locale = saved.locale;
        _hasChosenLanguage = true;
      } else {
        _locale = SunoLanguages.resolveDevice(
          PlatformDispatcher.instance.locale,
        ).locale;
        _hasChosenLanguage = false;
      }
    } catch (error, stack) {
      debugPrint('[SUNO-L10N] load failed: $error\n$stack');
      _locale = SunoLanguages.resolveDevice(
        PlatformDispatcher.instance.locale,
      ).locale;
      _hasChosenLanguage = false;
    }
    notifyListeners();
  }

  /// Switches the UI to [language] immediately, then saves it.
  ///
  /// Returns `true` if the choice was saved, `false` if saving failed. The
  /// switch still applies for this session when saving fails, so a storage
  /// problem can never block the person from reading the app.
  Future<bool> setLanguage(SunoLanguage language) async {
    _locale = language.locale;
    _hasChosenLanguage = true;
    notifyListeners();
    try {
      await _repository.setLanguageCode(language.code);
      return true;
    } catch (error, stack) {
      debugPrint('[SUNO-L10N] save failed: $error\n$stack');
      return false;
    }
  }
}
