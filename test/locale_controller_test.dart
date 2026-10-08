import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/profile/locale_repository.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/l10n/l10n.dart';
import 'package:suno_ai/core/l10n/locale_controller.dart';

/// Storage that always fails, to prove a broken Hive box cannot stop the
/// person from switching language.
class _FailingRepository implements LocaleRepository {
  @override
  Future<String?> getLanguageCode() async => null;

  @override
  Future<void> setLanguageCode(String code) async {
    throw StateError('storage unavailable');
  }
}

void main() {
  test('nothing is remembered before the person chooses', () async {
    final controller = LocaleController(repository: InMemoryLocaleRepository());
    expect(controller.hasChosenLanguage, isFalse);
    expect(controller.language, SunoLanguages.english);
  });

  test('setLanguage switches the UI and persists the choice', () async {
    final repository = InMemoryLocaleRepository();
    final controller = LocaleController(repository: repository);

    expect(await controller.setLanguage(SunoLanguages.bengali), isTrue);
    expect(controller.locale, const Locale('bn'));
    expect(controller.hasChosenLanguage, isTrue);
    expect(await repository.getLanguageCode(), 'bn');
  });

  test('load restores a saved language', () async {
    final repository = InMemoryLocaleRepository();
    await repository.setLanguageCode('ur');
    final controller = LocaleController(repository: repository);

    await controller.load();
    expect(controller.language, SunoLanguages.urdu);
    expect(controller.isRtl, isTrue);
    expect(controller.hasChosenLanguage, isTrue);
  });

  test('a save failure still applies the language for this session', () async {
    final controller = LocaleController(repository: _FailingRepository());

    expect(await controller.setLanguage(SunoLanguages.arabic), isFalse);
    expect(controller.locale, const Locale('ar'));
    expect(controller.isRtl, isTrue);
  });

  test('the picker and the generated localizations list one language', () {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      unorderedEquals(SunoLanguages.all.map((language) => language.code)),
    );
  });

  test('unusable codes fall back instead of choosing a blank language', () {
    expect(SunoLanguages.byCode('de'), isNull);
    expect(SunoLanguages.byCode(null), isNull);
    expect(
      SunoLanguages.resolveDevice(const Locale('de')),
      SunoLanguages.english,
    );
  });
}
