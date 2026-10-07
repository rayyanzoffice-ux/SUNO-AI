import 'package:intl/intl.dart';

/// Locale-aware clock time, e.g. "2:07 PM" or "14:07" depending on the locale.
/// [localeName] comes from `Localizations.localeOf(context).toLanguageTag()`.
String formatClockLocalized(DateTime time, String localeName) =>
    DateFormat.jm(localeName).format(time);

/// Locale-aware short date (e.g. "Oct 7" in English). Replaces the hard-coded
/// English month list in History.
String formatMonthDayLocalized(DateTime time, String localeName) =>
    DateFormat.MMMd(localeName).format(time);

/// `2026-10-07 · 2:07 PM` — an ISO-style day followed by a locale-aware clock.
/// The day half is digits and hyphens only, so nothing there needs translating;
/// only the clock does. Used by the received-alert detail line.
String formatIsoDayWithClock(DateTime time, String localeName) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} · '
      '${formatClockLocalized(time, localeName)}';
}
