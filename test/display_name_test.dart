import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/core/utils/display_name.dart';

void main() {
  test('absent or unprintable-only names are null', () {
    expect(cleanDisplayName(null), isNull);
    expect(cleanDisplayName(''), isNull);
    expect(cleanDisplayName('   '), isNull);
    expect(cleanDisplayName('\t\n  \u0000'), isNull);
  });

  test('control characters become spaces and whitespace collapses', () {
    expect(cleanDisplayName('Ayan\u0000Khan'), 'Ayan Khan');
    expect(cleanDisplayName('  Ayan\n\tKhan  '), 'Ayan Khan');
    expect(cleanDisplayName('Ayan\u007FKhan'), 'Ayan Khan');
  });

  test('names longer than the limit are cut without a trailing space', () {
    expect(cleanDisplayName('a' * 200)!.length, 40);
    expect(cleanDisplayName('${'x' * 39} y')!.length, 39);
    expect(cleanDisplayName('Ayan Khan', maxLength: 4), 'Ayan');
  });

  test('unicode letters survive untouched', () {
    expect(cleanDisplayName('Aïsha Núñez'), 'Aïsha Núñez');
  });
}
