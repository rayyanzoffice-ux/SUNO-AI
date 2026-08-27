import '../../models/detection_result.dart';
import 'detection_repository.dart';
import 'mock_detection_repository.dart';

/// Thin orchestration layer the UI actually talks to. Screens call
/// [DetectionEngine], never a [DetectionRepository] directly — this is what
/// makes it possible to swap [MockDetectionRepository] for a real
/// implementation later without touching a single screen file.
///
/// Per API_CONTRACT.md's Frontend/Backend Rules, this engine only ever
/// returns a [DetectionResult] — it never decides which screen to show.
/// That decision stays entirely with the UI layer, reading
/// [DetectionResult.riskLevel].
class DetectionEngine {
  DetectionEngine({DetectionRepository? repository})
    : _repository = repository ?? MockDetectionRepository(),
      _demoRepository = MockDetectionRepository();

  final DetectionRepository _repository;
  final MockDetectionRepository _demoRepository;

  /// Convenience singleton for call sites that don't need dependency
  /// injection (e.g. quick wiring from a screen's button handler). Supports
  /// both `DetectionEngine().simulateCriticalDetection()` and
  /// `DetectionEngine.instance.simulateCriticalDetection()` call styles.
  static final DetectionEngine instance = DetectionEngine();

  /// Runs the primary demo path and returns a critical-risk
  /// [DetectionResult]. Kept on the mock fixture repository even when a live
  /// [DetectionRepository] is injected so demo buttons stay deterministic
  /// during the TFLite wiring sprint.
  Future<DetectionResult> simulateCriticalDetection() =>
      _demoRepository.simulateCriticalDetection();

  /// Same as [simulateCriticalDetection] but for the medium-risk demo path.
  Future<DetectionResult> simulateMediumDetection() =>
      _demoRepository.simulateMediumDetection();

  /// Same as above but for the low-risk / ambient demo path.
  Future<DetectionResult> simulateLowRiskDetection() =>
      _demoRepository.simulateLowRiskDetection();

  /// The real entry point once a live detection pipeline exists — runs
  /// whatever [DetectionRepository] is currently wired in, mock or real.
  Future<DetectionResult> detect() => _repository.detect();
}
