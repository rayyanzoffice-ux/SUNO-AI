import 'dart:ui' show Locale;

/// One language SUNO can be displayed in.
///
/// [nativeName] is always written in the language's own script so a person who
/// cannot read the current UI language can still find theirs in the picker.
class SunoLanguage {
  /// Creates a language entry. [isRtl] is true for right-to-left scripts.
  const SunoLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
    this.isRtl = false,
  });

  /// ISO 639-1 language code; must match an `app_<code>.arb` file.
  final String code;

  /// Name in the language's own script, shown in the picker.
  final String nativeName;

  /// English name, shown as a small secondary label in the picker.
  final String englishName;

  /// Whether the script is written right-to-left.
  final bool isRtl;

  /// The Flutter [Locale] for this language.
  Locale get locale => Locale(code);
}

/// The fixed list of languages SUNO supports, in picker order.
abstract final class SunoLanguages {
  static const english = SunoLanguage(
    code: 'en',
    nativeName: 'English',
    englishName: 'English',
  );
  static const mandarin = SunoLanguage(
    code: 'zh',
    nativeName: '中文（简体）',
    englishName: 'Mandarin Chinese (Simplified)',
  );
  static const hindi = SunoLanguage(
    code: 'hi',
    nativeName: 'हिन्दी',
    englishName: 'Hindi',
  );
  static const spanish = SunoLanguage(
    code: 'es',
    nativeName: 'Español',
    englishName: 'Spanish',
  );
  static const french = SunoLanguage(
    code: 'fr',
    nativeName: 'Français',
    englishName: 'French',
  );
  static const urdu = SunoLanguage(
    code: 'ur',
    nativeName: 'اردو',
    englishName: 'Urdu',
    isRtl: true,
  );
  static const arabic = SunoLanguage(
    code: 'ar',
    nativeName: 'العربية',
    englishName: 'Arabic',
    isRtl: true,
  );
  static const bengali = SunoLanguage(
    code: 'bn',
    nativeName: 'বাংলা',
    englishName: 'Bengali',
  );

  /// Every supported language, in the order shown in the picker.
  static const all = <SunoLanguage>[
    english,
    mandarin,
    hindi,
    spanish,
    french,
    urdu,
    arabic,
    bengali,
  ];

  /// Finds a language by [code]; returns `null` for null/unknown codes.
  static SunoLanguage? byCode(String? code) {
    if (code == null) return null;
    for (final language in all) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// Picks the language matching the phone's [device] locale, or English if
  /// SUNO does not support it.
  static SunoLanguage resolveDevice(Locale device) =>
      byCode(device.languageCode) ?? english;
}
