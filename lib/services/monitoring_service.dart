import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/audio/microphone_capture.dart';
import '../backend/audio/microphone_permission.dart';
import '../backend/detection/live_detection_repository.dart';
import '../backend/detection/suno_audio_classifier.dart';
import '../backend/ml/yamnet_stage.dart';
import '../backend/services/foreground_service_bridge.dart';
import '../models/detection_result.dart';
import '../models/incident.dart';
import 'detection_notification_service.dart';
import 'suno_runtime_service.dart';

class MonitoringService extends ChangeNotifier with WidgetsBindingObserver {
  MonitoringService(this.runtime) {
    WidgetsBinding.instance.addObserver(this);
    runtime.addListener(_runtimeChanged);
    ForegroundServiceBridge.onStopRequested = stop;
    ForegroundServiceBridge.onServiceStopped = _onServiceStopped;
    _runtimeChanged();
  }

  static MonitoringService? _instance;
  static MonitoringService get instance =>
      _instance ??= MonitoringService(SunoRuntimeService.instance);

  static void resetForTesting() {
    _instance?.dispose();
    _instance = null;
  }

  final SunoRuntimeService runtime;
  bool liveMode = false;
  bool starting = false;
  bool active = false;
  String? error;
  final List<double> levels = [];
  bool _ownsService = false;
  bool _nativeInterrupted = false;
  bool _handling = false;
  bool _disposed = false;
  int _generation = 0;
  LiveDetectionRepository? _repo;
  MicrophoneCapture? _microphone;
  YamNetStage? _yamnet;
  SunoAudioClassifier? _classifier;
  StreamSubscription<dynamic>? _levelsSubscription;
  Future<void>? _startingTask;
  Future<void>? _stoppingTask;
  Future<void> _nativeWork = Future.value();
  String? _lastNotifiedStatus;
  AppLifecycleState? _lifecycle = WidgetsBinding.instance.lifecycleState;

  bool get _busy => runtime.hasPendingSafetyCheck || runtime.hasPendingDispatch;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _runtimeChanged();
  }

  Future<void> start() {
    if (starting || active || _busy || _stoppingTask != null) {
      return _startingTask ?? Future.value();
    }
    return _startingTask = _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    liveMode = true;
    starting = true;
    _nativeInterrupted = false;
    error = null;
    _changed();
    MicrophoneCapture? microphone;
    YamNetStage? yamnet;
    SunoAudioClassifier? classifier;
    LiveDetectionRepository? repo;
    var transferred = false;
    try {
      final permission = await MicrophonePermission.ensureGranted();
      if (permission != MicPermissionStatus.granted) {
        throw StateError('Microphone permission denied');
      }
      if (generation != _generation) return;
      await runtime.refreshLocation();
      if (generation != _generation) return;
      await _nativeWork;
      await ForegroundServiceBridge.start(
        microphoneEnabled: true,
        locationEnabled: await runtime.locationService.hasPermission(),
        status: 'Starting monitoring',
      );
      _ownsService = true;
      if (generation != _generation) return;
      microphone = MicrophoneCapture();
      yamnet = await YamNetStage.load();
      if (generation != _generation) return;
      classifier = await SunoAudioClassifier.load();
      if (generation != _generation) return;
      repo = LiveDetectionRepository(
        yamnet: yamnet,
        classifier: classifier,
        microphone: microphone,
        locationService: runtime.locationService,
        initialLocation: runtime.location,
        onDetection: _onDetection,
        onError: _onError,
      );
      await repo.startMonitoring();
      if (generation != _generation) return;
      await ForegroundServiceBridge.updateStatus('SUNO is listening');
      if (generation != _generation) return;
      _repo = repo;
      _microphone = microphone;
      _yamnet = yamnet;
      _classifier = classifier;
      _levelsSubscription = microphone.waveforms.listen((frame) {
        levels.add(frame.rmsAmplitude);
        if (levels.length > 23) levels.removeAt(0);
        _changed();
      }, onError: (Object _) {});
      transferred = true;
      active = true;
    } catch (_) {
      if (generation == _generation) error = 'Live monitoring could not start. Check microphone permission and device support, then retry.';
    } finally {
      if (!transferred) {
        try {
          await repo?.stopMonitoring();
        } catch (_) {
          error = 'Could not finish stopping audio capture.';
        }
        try {
          classifier?.close();
        } catch (_) {
          error = 'Could not release the audio classifier. Restart SUNO.';
        }
        try {
          yamnet?.close();
        } catch (_) {
          error = 'Could not release the audio processor. Restart SUNO.';
        }
        try {
          await microphone?.dispose();
        } catch (_) {
          error = 'Could not release the microphone. Restart SUNO before listening again.';
        }
        try {
          if (_ownsService && !_busy) await _stopNative();
        } catch (_) {
          error = 'Could not stop the Android service. Check the system notification and restart SUNO.';
        }
      }
      starting = false;
      _runtimeChanged();
      _changed();
    }
  }

  void _onError(Object _) {
    error = 'Monitoring stopped because a sensor or audio processor failed. Please restart Live mode.';
    unawaited(stop());
  }

  Future<void> _onServiceStopped() async {
    _ownsService = false;
    _nativeInterrupted = true;
    error = 'Android stopped background monitoring. Keep SUNO open for any pending safety action, then restart Live mode.';
    await stop();
  }

  void _onDetection(DetectionResult result) {
    if (_handling || !active || _busy || result.riskLevel == RiskLevel.low) {
      return;
    }
    _handling = true;
    unawaited(() async {
      try {
        try {
          await _stopCapture();
        } catch (_) {
          error =
              'Audio cleanup failed. Restart SUNO after this safety action.';
        }
        await runtime.recordDetection(result);
      } catch (_) {
        error =
            'Could not save the detection. Please use Silent SOS or seek help.';
      } finally {
        _handling = false;
        _runtimeChanged();
        _changed();
      }
    }());
  }

  void _runtimeChanged() {
    if (_disposed) return;
    final incident = runtime.currentIncident;
    if (incident != null && !active) {
      final status = '${incident.id}:${incident.status.name}';
      final completed = incident.status != IncidentStatus.safetyCheck;
      if (completed && _lastNotifiedStatus?.endsWith(':safetyCheck') == true) {
        unawaited(cancelDetectionNotification().catchError((Object _) {}));
      }
      if ((_busy || _lastNotifiedStatus != null) &&
          _lifecycle != AppLifecycleState.resumed &&
          _lastNotifiedStatus != status) {
        _lastNotifiedStatus = status;
        if (incident.status != IncidentStatus.cancelled &&
            incident.status != IncidentStatus.resolved) {
          unawaited(
            showFullScreenDetectionNotification(
              incidentId: incident.id,
              title: completed ? 'Emergency alert' : 'Are you safe?',
              body: completed
                  ? 'Open SUNO to check contact delivery status.'
                  : 'Respond before the safety check expires.',
              isCritical: completed,
            ).catchError((Object _) {
              error = 'Safety notifications unavailable. Check Android notification settings.';
              _changed();
            }),
          );
        }
      }
      if (incident.status == IncidentStatus.cancelled ||
          incident.status == IncidentStatus.resolved) {
        unawaited(cancelDetectionNotification().catchError((Object _) {}));
      }
    }
    _nativeWork = _nativeWork
        .then((_) async {
          if (_disposed || starting || _handling) return;
          if (!_busy) _nativeInterrupted = false;
          if (_busy && !_nativeInterrupted) {
            final status = runtime.hasPendingSafetyCheck
                ? 'Safety check in progress'
                : 'Sending emergency alerts';
            if (!_ownsService) {
              await ForegroundServiceBridge.start(
                microphoneEnabled: false,
                status: status,
              );
              _ownsService = true;
            } else {
              await ForegroundServiceBridge.updateStatus(status);
            }
          } else if (!active && _ownsService) {
            await _stopNative();
          }
        })
        .catchError((Object _) {
          error = 'Android could not keep the safety action in the background. Keep SUNO open until it finishes.';
          _changed();
        });
    _changed();
  }

  Future<void> _stopCapture() async {
    active = false;
    final repo = _repo;
    final microphone = _microphone;
    final yamnet = _yamnet;
    final classifier = _classifier;
    _repo = null;
    _microphone = null;
    _yamnet = null;
    _classifier = null;
    final levelsSubscription = _levelsSubscription;
    _levelsSubscription = null;
    try {
      try {
        await levelsSubscription?.cancel();
      } finally {
        await repo?.stopMonitoring();
      }
    } finally {
      try {
        try {
          classifier?.close();
        } finally {
          try {
            yamnet?.close();
          } finally {
            await microphone?.dispose();
          }
        }
      } finally {
        levels.clear();
        _changed();
      }
    }
  }

  Future<void> _stopNative() async {
    await ForegroundServiceBridge.stop();
    _ownsService = false;
  }

  Future<void> stop() =>
      _stoppingTask ??= _stop().whenComplete(() => _stoppingTask = null);

  Future<void> _stop() async {
    _generation++;
    try {
      try {
        if (starting) await _startingTask;
        await _stopCapture();
      } finally {
        await _nativeWork;
        if (_ownsService && (!_busy || _disposed)) await _stopNative();
      }
    } catch (_) {
      error = 'Could not complete monitoring cleanup. Check the system notification and restart SUNO.';
    }
    _runtimeChanged();
    _changed();
  }

  Future<void> selectDemo() async {
    await stop();
    liveMode = false;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    runtime.removeListener(_runtimeChanged);
    WidgetsBinding.instance.removeObserver(this);
    ForegroundServiceBridge.onStopRequested = null;
    ForegroundServiceBridge.onServiceStopped = null;
    unawaited(stop());
    super.dispose();
  }
}
