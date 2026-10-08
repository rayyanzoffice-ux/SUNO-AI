import 'package:intl/intl.dart';

/// Native digit blocks the supported languages can render: Arabic, extended
/// Arabic-Indic (Urdu), Devanagari (Hindi) and Bengali.
const _nativeDigitBases = <int>[0x0660, 0x06F0, 0x0966, 0x09E6];

/// Locale-aware clock time, e.g. "2:07 PM" or "14:07" depending on the locale.
/// [localeName] comes from `Localizations.localeOf(context).toLanguageTag()`.
String formatClockLocalized(DateTime time, String localeName) =>
    _westernDigits(DateFormat.jm(localeName).format(time));

/// Locale-aware short date (e.g. "Oct 7" in English). Replaces the hard-coded
/// English month list in History.
String formatMonthDayLocalized(DateTime time, String localeName) =>
    _westernDigits(DateFormat.MMMd(localeName).format(time));

/// `2026-10-08 · 2:07 PM` — an ISO-style day followed by a locale-aware clock.
/// The day half is digits and hyphens only, so nothing there needs translating;
/// only the clock does. Used by the received-alert detail line.
String formatIsoDayWithClock(DateTime time, String localeName) =>
    '${_isoDay(time)} · ${formatClockLocalized(time, localeName)}';

/// `2026-10-08 14:07` — a fixed-order, 24-hour stamp. Deliberately not
/// locale-aware: it pins a record to a moment, and re-styling it with the UI
/// language would make it harder to line up against a relay log.
String formatIsoStamp(DateTime time) {
  final local = time.toLocal();
  return '${_isoDay(local)} ${_two(local.hour)}:${_two(local.minute)}';
}

String _isoDay(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// Rewrites native digit shapes as ASCII `0-9`. SUNO shows Western digits in
/// every language because a countdown or a risk percentage has to be readable
/// at a glance during an emergency, and `DateFormat` substitutes a locale's
/// own digit block when its data defines one.
String _westernDigits(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final base = _digitBlockBase(rune);
    buffer.writeCharCode(base == null ? rune : 0x30 + rune - base);
  }
  return buffer.toString();
}

/// The zero of the native digit block containing [rune], or `null`.
int? _digitBlockBase(int rune) {
  for (final base in _nativeDigitBases) {
    if (rune >= base && rune < base + 10) return base;
  }
  return null;
}
