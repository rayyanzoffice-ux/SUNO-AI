import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SUNO labels asset matches the classifier contract', () async {
    final raw = await rootBundle.loadString('assets/ml/labels.json');
    final decoded = jsonDecode(raw);

    expect(decoded, isA<Map<String, dynamic>>());

    final contract = decoded as Map<String, dynamic>;

    expect(contract['model_type'], 'YAMNet_Embedding_Classifier');
    expect(contract['embedding_size'], 1024);
    expect(contract['sample_rate_hz'], 16000);
    expect(contract['frame_length_sec'], 0.96);
    expect(contract['frame_hop_sec'], 0.48);
    expect(contract['classes'], [
      'ambient_safe',
      'distress_voice',
      'alarm_siren',
      'breaking_crash',
    ]);
    expect(contract['confidence_threshold'], 0.3);
  });

  test('SUNO TFLite model asset is bundled and non-empty', () async {
    final data = await rootBundle.load(
      'assets/ml/suno_audio_classifier.tflite',
    );

    expect(data.lengthInBytes, greaterThan(0));
  });
}
