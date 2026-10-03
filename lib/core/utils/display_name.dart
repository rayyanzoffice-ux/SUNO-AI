/// Normalises a person's display name coming from the UI or from a push
/// payload so it is safe to store and show.
///
/// Control characters (including newlines) become spaces, runs of whitespace
/// collapse to one space, and the result is trimmed and cut to [maxLength].
/// Returns `null` when nothing printable remains, so callers can treat
/// "no name" uniformly.
String? cleanDisplayName(String? raw, {int maxLength = 40}) {
  if (raw == null) return null;
  final collapsed = raw
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.isEmpty) return null;
  if (collapsed.length <= maxLength) return collapsed;
  return collapsed.substring(0, maxLength).trimRight();
}
