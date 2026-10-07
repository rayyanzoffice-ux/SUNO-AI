import 'package:flutter/widgets.dart';

/// Languages whose letters join together. Spacing between letters breaks the
/// joins (Arabic/Urdu) or detaches vowel signs (Hindi/Bengali).
const _connectedScriptCodes = <String>{'ar', 'ur', 'hi', 'bn'};

/// Returns [spacing] for languages where letter-spacing is safe, and `0` for
/// connected scripts. Use this for every `TextStyle.letterSpacing` that is
/// applied to translated text. Do NOT use it on the Latin brand word "SUNO".
double scriptSafeLetterSpacing(BuildContext context, double spacing) {
  final code = Localizations.localeOf(context).languageCode;
  return _connectedScriptCodes.contains(code) ? 0 : spacing;
}
