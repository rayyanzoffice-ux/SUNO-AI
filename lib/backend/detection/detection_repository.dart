import '../../models/detection_result.dart';

/// Abstraction over "how a [DetectionResult] is produced". The UI layer
/// never talks to this directly — only [DetectionEngine] does, so swapping
/// [MockDetectionRepository] for a real on-device classifier + sensor
/// pipeline later means changing one binding, not touching any screen.
abstract interface class DetectionRepository {
  /// Produces a single detection event. Implementations decide whether this
  /// is simulated (mock), read from the real audio/motion pipeline, or
  /// replayed from a fixture during testing.
  Future<DetectionResult> detect();
}
