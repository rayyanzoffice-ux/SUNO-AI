import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/utils/time_format.dart';

/// Zeroes of the native digit blocks `DateFormat` can substitute for SUNO's
/// languages: Arabic, extended Arabic-Indic (Urdu), Devanagari (Hindi),
/// Bengali.
const _nativeDigitBases = <int>[0x0660, 0x06F0, 0x0966, 0x09E6];

bool _isNativeDigit(int rune) =>
    _nativeDigitBases.any((base) => rune >= base && rune < base + 10);

bool _hasAsciiDigit(String text) =>
    text.runes.any((rune) => rune >= 0x30 && rune <= 0x39);

void main() {
  final moment = DateTime(2026, 10, 8, 14, 7);

  setUpAll(() => initializeDateFormatting());

  for (final language in SunoLanguages.all) {
    test('${language.code} shows numbers as 0-9', () {
      final tag = language.locale.toLanguageTag();
      final shown = <String>[
        formatClockLocalized(moment, tag),
        formatMonthDayLocalized(moment, tag),
        formatIsoDayWithClock(moment, tag),
      ];

      for (final text in shown) {
        expect(text.runes.where(_isNativeDigit), isEmpty, reason: text);
        expect(_hasAsciiDigit(text), isTrue, reason: text);
      }
    });
  }

  test('the verified-at audit stamp keeps its fixed shape', () {
    // Contacts shows this stamp, so it must not drift when the shared helper
    // picks up a locale-aware clock for other screens.
    expect(formatIsoStamp(moment), '2026-10-08 14:07');
  });
}
