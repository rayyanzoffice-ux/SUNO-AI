import 'dart:convert';

import 'package:flutter/services.dart';

/// Per-class risk metadata written by the v2 training notebook.
class ClassMeta {
  const ClassMeta({
    required this.alertWeight,
    required this.threshold,
    required this.minHitsOf3,
  });

  final int alertWeight;
  final double threshold;
  final int minHitsOf3;

  factory ClassMeta.fromJson(Map<String, dynamic> json) {
    final alertWeight = json['alert_weight'];
    final threshold = json['threshold'];
    final minHitsOf3 = json['min_hits_of_3'];

    if (alertWeight is! int || alertWeight < 0) {
      throw const FormatException(
        'class_meta.alert_weight must be an integer >= 0.',
      );
    }
    if (threshold is! num || threshold < 0 || threshold > 1) {
      throw const FormatException(
        'class_meta.threshold must be between 0 and 1.',
      );
    }
    if (minHitsOf3 is! int || minHitsOf3 < 0) {
      throw const FormatException(
        'class_meta.min_hits_of_3 must be an integer >= 0.',
      );
    }

    return ClassMeta(
      alertWeight: alertWeight,
      threshold: threshold.toDouble(),
      minHitsOf3: minHitsOf3,
    );
  }
}

/// The model contract behind `suno_audio_classifier_v2.tflite`.
///
/// The class list is read from `labels_v2.json` instead of being hard-coded,
/// because the v2 head has 23 outputs rather than the v1 head's 4. The output
/// tensor width is always checked against [classes] before the model is used:
/// mapping 23 probabilities onto the wrong labels would silently mislabel every
/// detection.
class ClassifierLabels {
  ClassifierLabels._({
    required List<String> classes,
    required this.margin,
    required Map<String, ClassMeta> classMeta,
  }) : classes = List.unmodifiable(classes),
       classMeta = Map.unmodifiable(classMeta);

  final List<String> classes;
  final double margin;
  final Map<String, ClassMeta> classMeta;

  static const expectedEmbeddingSize = 1024;

  Set<String> get alertClasses => {
    for (final entry in classMeta.entries)
      if (entry.value.alertWeight > 0) entry.key,
  };

  ClassMeta? metaFor(String label) => classMeta[label];

  bool isAlert(String label) => (classMeta[label]?.alertWeight ?? 0) > 0;

  double get minimumAlertThreshold {
    var minimum = 1.0;
    for (final meta in classMeta.values) {
      if (meta.alertWeight > 0 && meta.threshold < minimum) {
        minimum = meta.threshold;
      }
    }
    return minimum;
  }

  static Future<ClassifierLabels> loadFromAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Classifier labels file must contain an object.',
      );
    }
    return ClassifierLabels.fromJson(decoded);
  }

  factory ClassifierLabels.fromJson(Map<String, dynamic> json) {
    if (json['model_version'] != 2) {
      throw FormatException(
        'Expected model_version 2, got ${json['model_version']}.',
      );
    }
    if (json['embedding_size'] != expectedEmbeddingSize) {
      throw const FormatException(
        'v2 classifier requires 1024-dimensional YAMNet embeddings.',
      );
    }
    if (json['sample_rate_hz'] != 16000) {
      throw const FormatException(
        'v2 classifier input sample rate must be 16000 Hz.',
      );
    }
    if (json['frame_length_sec'] != 0.96) {
      throw const FormatException(
        'v2 classifier frame length must be 0.96 seconds.',
      );
    }
    if (json['frame_hop_sec'] != 0.48) {
      throw const FormatException(
        'v2 classifier frame hop must be 0.48 seconds.',
      );
    }

    final rawClasses = json['classes'];
    if (rawClasses is! List || rawClasses.isEmpty) {
      throw const FormatException(
        'Classifier classes must be a non-empty list.',
      );
    }

    final classes = <String>[];
    final seen = <String>{};
    for (final value in rawClasses) {
      if (value is! String || value.isEmpty) {
        throw const FormatException(
          'Classifier classes must be non-empty strings.',
        );
      }
      if (!seen.add(value)) {
        throw FormatException('Duplicate classifier class: $value');
      }
      classes.add(value);
    }

    final margin = json['margin'];
    if (margin is! num || margin < 0 || margin > 1) {
      throw const FormatException('margin must be between 0 and 1.');
    }

    final rawMeta = json['class_meta'];
    if (rawMeta is! Map<String, dynamic>) {
      throw const FormatException('class_meta must be an object.');
    }

    final meta = <String, ClassMeta>{};
    for (final entry in rawMeta.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        throw FormatException('class_meta.${entry.key} must be an object.');
      }
      meta[entry.key] = ClassMeta.fromJson(value);
    }

    final missing = classes.where((c) => !meta.containsKey(c)).toList();
    final extra = meta.keys.where((c) => !seen.contains(c)).toList();
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw FormatException(
        'class_meta must describe every class exactly once '
        '(missing: $missing, extra: $extra).',
      );
    }

    final labels = ClassifierLabels._(
      classes: classes,
      margin: margin.toDouble(),
      classMeta: meta,
    );
    if (labels.alertClasses.isEmpty) {
      throw const FormatException(
        'Classifier has no alert classes (every alert_weight is 0).',
      );
    }
    return labels;
  }
}
