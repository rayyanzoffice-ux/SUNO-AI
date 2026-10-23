import '../audio/audio_waveform.dart';
import '../detection/suno_audio_classifier.dart';
import 'yamnet_stage.dart';

/// Represents a stable, debounced audio event ready for risk evaluation.
class AudioEvent {
  const AudioEvent({
    required this.label,
    required this.confidence,
    required this.detectedAt,
    this.secondConfidence = 0,
    this.rmsAmplitude = 0,
    this.ambientRms,
  });

  final String label;
  final double confidence;
  final DateTime detectedAt;

  /// Runner-up class score, used by the v2 margin rule.
  final double secondConfidence;

  /// RMS level of the frame that produced this event, in [0, 1].
  final double rmsAmplitude;

  /// Median RMS of recent frames, or null until enough frames exist to make
  /// the estimate meaningful.
  final double? ambientRms;

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
    this.averageEmbeddings = false,
    this.isAlertLabel,
    this._onEvent,
  });

  final YamNetStage yamnet;
  final SunoAudioClassifier classifier;
  final int sustainFrames;
  final int cooldownFrames;

  /// Averages every YAMNet frame in a window before classification.
  ///
  /// The v2 training notebook trains on the mean embedding, so the live
  /// pipeline must do the same or the head sees a different distribution.
  /// v1 keeps its original first-frame behavior.
  final bool averageEmbeddings;

  /// Whether a label should trigger the post-event cooldown. Defaults to every
  /// non-ambient label, which is correct for v1. The v2 pipeline supplies a
  /// predicate so the 18 no-effect classes do not delay a real alert.
  final bool Function(String label)? isAlertLabel;
  final void Function(AudioEvent)? _onEvent;

  final List<String> _recentLabels = [];
  final List<double> _recentConfidences = [];
  final List<double> _recentSecondConfidences = [];
  final List<double> _ambientLevels = [];
  int _cooldownRemaining = 0;

  void process(AudioWaveform waveform) {
    _rememberAmbient(waveform.rmsAmplitude);
    final embeddings = yamnet.embed(waveform);
    if (embeddings.isEmpty) return;

    final classification = classifier.classifyEmbedding(
      averageEmbeddings
          ? _averageEmbeddings(embeddings)
          : embeddings.first.embedding,
    );

    _recentLabels.add(classification.label);
    _recentConfidences.add(classification.confidence);
    _recentSecondConfidences.add(classification.secondConfidence);

    if (_recentLabels.length > sustainFrames) {
      _recentLabels.removeAt(0);
      _recentConfidences.removeAt(0);
      _recentSecondConfidences.removeAt(0);
    }

    if (_cooldownRemaining > 0) {
      _cooldownRemaining--;
      return;
    }

    if (_recentLabels.length < sustainFrames) return;

    final dominantLabel = _recentLabels.first;
    if (!_recentLabels.every((l) => l == dominantLabel)) return;

    final avgConf =
        _recentConfidences.reduce((a, b) => a + b) / _recentConfidences.length;
    final avgSecondConf =
        _recentSecondConfidences.reduce((a, b) => a + b) /
        _recentSecondConfidences.length;
    if (avgConf < classifier.confidenceThreshold) return;

    final isAlert = isAlertLabel?.call(dominantLabel) ??
        dominantLabel != 'ambient_safe';
    _cooldownRemaining = isAlert ? cooldownFrames : 0;
    _recentLabels.clear();
    _recentConfidences.clear();
    _recentSecondConfidences.clear();

    _onEvent?.call(
      AudioEvent(
        label: dominantLabel,
        confidence: avgConf,
        detectedAt: waveform.capturedAt,
        secondConfidence: avgSecondConf,
        rmsAmplitude: waveform.rmsAmplitude,
        ambientRms: _medianAmbient(),
      ),
    );
  }

  void reset() {
    _recentLabels.clear();
    _recentConfidences.clear();
    _recentSecondConfidences.clear();
    _ambientLevels.clear();
    _cooldownRemaining = 0;
  }

  void _rememberAmbient(double rms) {
    _ambientLevels.add(rms);
    if (_ambientLevels.length > 31) _ambientLevels.removeAt(0);
  }

  double? _medianAmbient() {
    if (_ambientLevels.length < 5) return null;
    final sorted = List<double>.from(_ambientLevels)..sort();
    return sorted[sorted.length ~/ 2];
  }

  static List<double> _averageEmbeddings(List<YamNetEmbedding> embeddings) {
    final sums = List<double>.filled(embeddings.first.embedding.length, 0);
    for (final frame in embeddings) {
      for (var i = 0; i < sums.length; i++) {
        sums[i] += frame.embedding[i];
      }
    }
    final count = embeddings.length;
    return [for (final sum in sums) sum / count];
  }
}
