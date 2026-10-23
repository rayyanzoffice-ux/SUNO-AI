import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/detection/alert_pattern_tracker.dart';
import 'package:suno_ai/backend/detection/classifier_labels.dart';
import 'package:suno_ai/backend/detection/continuous_audio_detector.dart';
import 'package:suno_ai/backend/detection/loudness_gate.dart';
import 'package:suno_ai/backend/detection/v2_audio_classifier.dart';
import 'package:suno_ai/backend/risk/risk_engine.dart';
import 'package:suno_ai/models/detection_result.dart';

void main() {
  final labels = _labels();
  final t0 = DateTime(2026, 10, 23, 12);

  AudioEvent event(
    String label, {
    DateTime? at,
    double confidence = .9,
    double secondConfidence = .1,
    double rmsAmplitude = .05,
    double? ambientRms,
  }) => AudioEvent(
    label: label,
    confidence: confidence,
    detectedAt: at ?? t0,
    secondConfidence: secondConfidence,
    rmsAmplitude: rmsAmplitude,
    ambientRms: ambientRms,
  );

  group('ClassifierLabels', () {
    test('keeps class order and per-class metadata', () {
      expect(labels.classes, [
        'a01_scream_loud',
        'a02_gun_shots',
        'a03_glass_break',
        'n01_quiet_room',
      ]);
      expect(labels.alertClasses, {
        'a01_scream_loud',
        'a02_gun_shots',
        'a03_glass_break',
      });
      expect(labels.isAlert('n01_quiet_room'), isFalse);
      expect(labels.minimumAlertThreshold, .6);
      expect(labels.margin, .25);
    });

    test('rejects a model version that is not v2', () {
      final json = _labelsJson()..['model_version'] = 1;
      expect(
        () => ClassifierLabels.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects metadata that does not cover every class', () {
      final json = _labelsJson();
      (json['class_meta'] as Map<String, dynamic>).remove('a03_glass_break');
      expect(
        () => ClassifierLabels.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate classes', () {
      final json = _labelsJson();
      json['classes'] = ['a01_scream_loud', 'a01_scream_loud'];
      expect(
        () => ClassifierLabels.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('alertWeightFor', () {
    test('high confidence earns the full class weight', () {
      expect(alertWeightFor('a01_scream_loud', .9, labels), 50);
      expect(alertWeightFor('a03_glass_break', .9, labels), 35);
    });

    test('moderate confidence earns 70 percent', () {
      expect(alertWeightFor('a01_scream_loud', .65, labels), 35);
    });

    test('below the class threshold earns nothing', () {
      expect(alertWeightFor('a01_scream_loud', .59, labels), 0);
    });

    test('no-effect classes never earn an audio score', () {
      expect(alertWeightFor('n01_quiet_room', .99, labels), 0);
      expect(alertWeightFor('unknown_class', .99, labels), 0);
    });
  });

  group('AlertPatternTracker', () {
    test('one event is not a repeat', () {
      final tracker = AlertPatternTracker()..record(event('a01_scream_loud'));
      expect(tracker.hasRepeated('a01_scream_loud', minRepeats: 2), isFalse);
    });

    test('two events inside the window repeat', () {
      final tracker = AlertPatternTracker()
        ..record(event('a01_scream_loud'))
        ..record(event('a01_scream_loud', at: t0.add(const Duration(seconds: 4))));
      expect(tracker.hasRepeated('a01_scream_loud', minRepeats: 2), isTrue);
    });

    test('events older than the window are pruned', () {
      final tracker = AlertPatternTracker()
        ..record(event('a01_scream_loud'))
        ..record(
          event('a01_scream_loud', at: t0.add(const Duration(seconds: 11))),
        );
      expect(tracker.hasRepeated('a01_scream_loud', minRepeats: 2), isFalse);
    });

    test('compound classes are reported', () {
      final tracker = AlertPatternTracker()
        ..record(event('a01_scream_loud'))
        ..record(
          event('a02_gun_shots', at: t0.add(const Duration(seconds: 2))),
        );
      expect(
        tracker.coOccurringAlertClasses(labels.alertClasses),
        {'a01_scream_loud', 'a02_gun_shots'},
      );
    });
  });

  group('shouldEscalateImmediately', () {
    test('a single scream stays cautious', () {
      final tracker = AlertPatternTracker();
      final latest = event('a01_scream_loud');
      tracker.record(latest);
      expect(shouldEscalateImmediately(tracker, labels, latest), isFalse);
    });

    test('two screams escalate', () {
      final tracker = AlertPatternTracker()
        ..record(event('a01_scream_loud'));
      final latest = event(
        'a01_scream_loud',
        at: t0.add(const Duration(seconds: 4)),
      );
      tracker.record(latest);
      expect(shouldEscalateImmediately(tracker, labels, latest), isTrue);
    });

    test('gunshot plus scream escalates through the compound rule', () {
      final tracker = AlertPatternTracker()
        ..record(event('a01_scream_loud'));
      final latest = event(
        'a02_gun_shots',
        at: t0.add(const Duration(seconds: 2)),
      );
      tracker.record(latest);
      expect(shouldEscalateImmediately(tracker, labels, latest), isTrue);
    });

    test('repeating a glass break is not repetition evidence', () {
      final tracker = AlertPatternTracker()
        ..record(event('a03_glass_break'));
      final latest = event(
        'a03_glass_break',
        at: t0.add(const Duration(seconds: 2)),
      );
      tracker.record(latest);
      expect(shouldEscalateImmediately(tracker, labels, latest), isFalse);
    });

    test('a sustained home alarm escalates', () {
      final tracker = AlertPatternTracker()
        ..record(event('a05_alarm_home'));
      final latest = event(
        'a05_alarm_home',
        at: t0.add(const Duration(seconds: 3)),
      );
      tracker.record(latest);
      expect(shouldEscalateImmediately(tracker, labels, latest), isTrue);
    });
  });

  group('RiskEngine.evaluateV2Detection', () {
    const engine = RiskEngine();

    test('one confirmed scream is medium, not critical', () {
      final result = engine.evaluateV2Detection(
        detectedClass: 'a01_scream_loud',
        confidence: .9,
        impactDetected: false,
        stillnessDetected: false,
        labels: labels,
      );
      expect(result.riskScore, 50);
      expect(result.riskLevel, RiskLevel.medium);
    });

    test('a moderate confirmed scream still opens the countdown', () {
      final result = engine.evaluateV2Detection(
        detectedClass: 'a01_scream_loud',
        confidence: .65,
        impactDetected: false,
        stillnessDetected: false,
        labels: labels,
      );
      expect(result.riskScore, 40);
      expect(result.riskLevel, RiskLevel.medium);
    });

    test('a glass break below the additive floor still reaches medium', () {
      final result = engine.evaluateV2Detection(
        detectedClass: 'a03_glass_break',
        confidence: .9,
        impactDetected: false,
        stillnessDetected: false,
        labels: labels,
      );
      expect(result.riskScore, 40);
      expect(result.riskLevel, RiskLevel.medium);
    });

    test('pattern evidence forces critical regardless of the additive score', () {
      final result = engine.evaluateV2Detection(
        detectedClass: 'a03_glass_break',
        confidence: .61,
        impactDetected: false,
        stillnessDetected: false,
        labels: labels,
        forceCritical: true,
      );
      expect(result.riskScore, 100);
      expect(result.riskLevel, RiskLevel.critical);
    });

    test('a no-effect class with no motion scores zero', () {
      final result = engine.evaluateV2Detection(
        detectedClass: 'n01_quiet_room',
        confidence: .99,
        impactDetected: false,
        stillnessDetected: false,
        labels: labels,
      );
      expect(result.riskScore, 0);
      expect(result.riskLevel, RiskLevel.low);
    });
  });

  group('LoudnessGate', () {
    const gate = LoudnessGate();

    test('rejects an alert class below the absolute floor', () {
      expect(
        gate.allows(event('a01_scream_loud', rmsAmplitude: .005)),
        isFalse,
      );
    });

    test('accepts an alert class above the floor without an ambient estimate', () {
      expect(gate.allows(event('a01_scream_loud')), isTrue);
    });

    test('requires an alert class to beat the room by the factor', () {
      expect(
        gate.allows(
          event('a01_scream_loud', rmsAmplitude: .05, ambientRms: .02),
        ),
        isTrue,
      );
      expect(
        gate.allows(
          event('a01_scream_loud', rmsAmplitude: .03, ambientRms: .02),
        ),
        isFalse,
      );
    });

    test('a home alarm is exempt from the gate', () {
      expect(
        gate.allows(
          event('a05_alarm_home', rmsAmplitude: .001, ambientRms: .1),
        ),
        isTrue,
      );
    });
  });

  group('eventTypeForV2', () {
    test('maps every alert class and falls back to ambient', () {
      expect(eventTypeForV2('a01_scream_loud'), 'Distress Sound');
      expect(eventTypeForV2('a02_gun_shots'), 'Gunshot Sound');
      expect(eventTypeForV2('a03_glass_break'), 'Impact / Breaking Sound');
      expect(eventTypeForV2('a04_crash_heavy'), 'Impact / Breaking Sound');
      expect(eventTypeForV2('a05_alarm_home'), 'Emergency Alarm');
      expect(eventTypeForV2('n12_door_slam'), 'Ambient Sound');
    });
  });
}

ClassifierLabels _labels() => ClassifierLabels.fromJson(_labelsJson());

Map<String, dynamic> _labelsJson() => <String, dynamic>{
  'model_version': 2,
  'embedding_size': 1024,
  'sample_rate_hz': 16000,
  'frame_length_sec': 0.96,
  'frame_hop_sec': 0.48,
  'classes': [
    'a01_scream_loud',
    'a02_gun_shots',
    'a03_glass_break',
    'n01_quiet_room',
  ],
  'margin': 0.25,
  'class_meta': <String, dynamic>{
    'a01_scream_loud': <String, dynamic>{
      'alert_weight': 50,
      'threshold': 0.60,
      'min_hits_of_3': 2,
    },
    'a02_gun_shots': <String, dynamic>{
      'alert_weight': 50,
      'threshold': 0.60,
      'min_hits_of_3': 1,
    },
    'a03_glass_break': <String, dynamic>{
      'alert_weight': 35,
      'threshold': 0.60,
      'min_hits_of_3': 1,
    },
    'n01_quiet_room': <String, dynamic>{
      'alert_weight': 0,
      'threshold': 1.0,
      'min_hits_of_3': 0,
    },
  },
};
