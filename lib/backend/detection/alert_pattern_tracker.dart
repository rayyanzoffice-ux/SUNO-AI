import '../ml/continuous_audio_detector.dart';
import 'classifier_labels.dart';

/// Keeps the last [window] of confirmed alert events and answers two
/// questions: has one class repeated enough to count as sustained evidence,
/// and have two different alert classes occurred close together?
class AlertPatternTracker {
  AlertPatternTracker({this.window = const Duration(seconds: 10)});

  final Duration window;
  final List<AudioEvent> _recent = [];

  void record(AudioEvent event) {
    _recent.add(event);
    final cutoff = event.detectedAt.subtract(window);
    _recent.removeWhere((e) => e.detectedAt.isBefore(cutoff));
  }

  /// True once [label] appears at least [minRepeats] times in the window.
  bool hasRepeated(String label, {required int minRepeats}) {
    if (minRepeats <= 0) return false;
    var count = 0;
    for (final event in _recent) {
      if (event.label != label) continue;
      count++;
      if (count >= minRepeats) return true;
    }
    return false;
  }

  /// Every different alert class heard in the window.
  Set<String> coOccurringAlertClasses(Set<String> alertClassNames) => {
    for (final event in _recent)
      if (alertClassNames.contains(event.label)) event.label,
  };

  void reset() => _recent.clear();
}

/// Classes where a second event within [AlertPatternTracker.window] is strong
/// enough to skip the safety-check countdown. A single scream or bang is
/// ambiguous (a shout, a firecracker); repetition is not.
const repeatEscalationClasses = <String, int>{
  'a01_scream_loud': 2,
  'a02_gun_shots': 2,
  'a05_alarm_home': 2,
};

/// True when [latest] completes compound or repeated evidence and the app
/// should escalate straight to trusted contacts instead of showing the
/// countdown.
bool shouldEscalateImmediately(
  AlertPatternTracker tracker,
  ClassifierLabels labels,
  AudioEvent latest,
) {
  // Two different alert classes close together (for example a gunshot and a
  // scream) is much less likely to be one ambiguous sound than either alone.
  final co = tracker.coOccurringAlertClasses(labels.alertClasses);
  if (co.length >= 2) return true;

  final minRepeats = repeatEscalationClasses[latest.label];
  return minRepeats != null &&
      tracker.hasRepeated(latest.label, minRepeats: minRepeats);
}
