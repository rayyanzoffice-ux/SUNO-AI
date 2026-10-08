import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Translations are added key by key, so a key missing from one language fails
/// at runtime as a missing-string exception on a real phone. This checks the
/// eight ARB files against the English template instead.
Set<String> _keys(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>).keys
        .where((key) => !key.startsWith('@'))
        .toSet();

void main() {
  final english = _keys(File('lib/l10n/app_en.arb'));
  final arbFiles = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.arb'));

  test('the template defines every key', () {
    expect(english, isNotEmpty);
  });

  for (final file in arbFiles) {
    final name = file.uri.pathSegments.last;
    test('$name has exactly the same keys as app_en.arb', () {
      expect(_keys(file), english);
    });
  }
}
