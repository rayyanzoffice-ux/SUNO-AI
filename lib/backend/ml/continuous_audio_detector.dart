import '../audio/audio_waveform.dart';
import '../detection/suno_audio_classifier.dart';
import 'yamnet_stage.dart';

/// Represents a stable, debounced audio event ready for risk evaluation.
class AudioEvent {
  const AudioEvent({
    required this.label,
    required this.confidence,
    required this.detectedAt,
  });

  final String label;
  final double confidence;
  final DateTime detectedAt;

  bool get isDistress => label != 'ambient_safe';

  @override
  String toString() =>
      'AudioEvent(label: $label, '
      'confidence: ${confidence.toStringAsFixed(2)})';
}

/// Runs rolling inference over incoming [AudioWaveform] frames and emits
/// stable [AudioEvent] objects, debounced so a single noisy frame does not
/// trigger an incident.
///
/// A stable event requires [sustainFrames] consecutive frames that all
/// agree on the same class, with average confidence above the classifier
/// threshold. After firing, [cooldownFrames] frames are skipped.
class ContinuousAudioDetector {
  ContinuousAudioDetector({
    required this.yamnet,
    required this.classifier,
    this.sustainFrames = 3,
    this.cooldownFrames = 6,
    void Function(AudioEvent)? onEvent,
  }) : _onEvent = onEvent;

  final YamNetStage yamnet;
  final SunoAudioClassifier classifier;
  final int sustainFrames;
  final int cooldownFrames;
  final void Function(AudioEvent)? _onEvent;

  final List<String> _recentLabels = [];
  final List<double> _recentConfidences = [];
  int _cooldownRemaining = 0;

  void process(AudioWaveform waveform) {
    final embeddings = yamnet.embed(waveform);
    if (embeddings.isEmpty) return;

    // Average embeddings across all frames in this window.
    final classification =
        classifier.classifyEmbedding(embeddings.first.embedding);

    _recentLabels.add(classification.label);
    _recentConfidences.add(classification.confidence);

    if (_recentLabels.length > sustainFrames) {
      _recentLabels.removeAt(0);
      _recentConfidences.removeAt(0);
    }

    if (_cooldownRemaining > 0) {
      _cooldownRemaining--;
      return;
    }

    if (_recentLabels.length < sustainFrames) return;

    final dominantLabel = _recentLabels.first;
    if (!_recentLabels.every((l) => l == dominantLabel)) return;

    final avgConf = _recentConfidences.reduce((a, b) => a + b) /
        _recentConfidences.length;
    if (avgConf < classifier.confidenceThreshold) return;

    _cooldownRemaining = cooldownFrames;
    _recentLabels.clear();
    _recentConfidences.clear();

    _onEvent?.call(AudioEvent(
      label: dominantLabel,
      confidence: avgConf,
      detectedAt: waveform.capturedAt,
    ));
  }

  void reset() {
    _recentLabels.clear();
    _recentConfidences.clear();
    _cooldownRemaining = 0;
  }
}
