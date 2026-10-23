import 'continuous_audio_detector.dart';

/// Rejects alert sounds that are not clearly louder than the room.
///
/// A classification that is confident on a quiet frame is usually the model
/// reacting to something else in the room. The gate is applied only to the
/// transient classes; a home alarm (a05) is expected to be loud and sustained,
/// and the repeat rule already covers it.
class LoudnessGate {
  const LoudnessGate({this.factor = 2.0, this.absoluteFloor = 0.01});

  final double factor;
  final double absoluteFloor;

  static const gatedClasses = {
    'a01_scream_loud',
    'a02_gun_shots',
    'a03_glass_break',
    'a04_crash_heavy',
  };

  bool allows(AudioEvent event) {
    if (!gatedClasses.contains(event.label)) return true;
    final ambient = event.ambientRms;
    final threshold = ambient == null
        ? absoluteFloor
        : (ambient * factor).clamp(absoluteFloor, 1.0).toDouble();
    return event.rmsAmplitude >= threshold;
  }
}
