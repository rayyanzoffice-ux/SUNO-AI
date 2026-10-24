import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../../core/l10n/l10n.dart';
import '../../services/detection_notification_service.dart'
    show localAlarmChannelId, sunoNotifications;
import 'native_alarm_player.dart';

/// Audible safety alarm. The tune plays natively on Android's alarm stream, so
/// it is heard while SUNO is in the background or its task has been swiped
/// away; the notification supplies the visible card and full-screen intent,
/// and vibration backs up both. Everything runs on the phone, so it still
/// works with no SIM, no signal and no SMS balance.
class LocalAlarmService {
  LocalAlarmService({NativeAlarmPlayer? player})
    : _player = player ?? NativeAlarmPlayer();

  final NativeAlarmPlayer _player;

  // A fixed id keeps a second failed dispatch from stacking alarms.
  static const _notificationId = 0x50A0;

  /// Fallback waveform only; the normal path vibrates natively.
  static const _vibrationPattern = [0, 600, 300, 600];

  /// Bumped by [stop]. A [sound] call that was already in flight when the
  /// countdown ended must not post a notification after the stop, or the
  /// alarm would ring past the 45-second window.
  int _stopEpoch = 0;

  /// Identifies the newest [sound] call so an older, slower one cannot cancel
  /// an alarm that a newer call (for example, the post-escalation last resort)
  /// has just posted.
  int _soundSerial = 0;

  /// Safety net so vibration ends with the countdown even if the runtime
  /// service's stop timer is delayed.
  Timer? _vibrationStopTimer;

  Future<void> sound({required String incidentId, Duration? duration}) async {
    final epoch = _stopEpoch;
    final serial = ++_soundSerial;
    // Native audio ignores notification permission and the activity lifetime,
    // which are exactly the two things that can silence a notification sound.
    // It also starts a native vibration that lasts the whole countdown.
    final audible = await _player.start(duration: duration);
    if (epoch != _stopEpoch) {
      // stop() ran while the bridge was starting; do not leave it ringing.
      await _player.stop();
      return;
    }
    // Only a failed tune needs the Dart fallback: a second waveform here would
    // replace the native one, and an unbounded loop can outlive the process.
    if (!audible) unawaited(_vibrate(epoch, serial, duration));
    // Android 13+ can silently drop a notification when the permission is
    // denied: show() still completes, so the catch below would never run.
    // Probe first and skip the notification; the tune already runs.
    try {
      final android = sunoNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() == false) return;
    } catch (_) {
      // A failed probe must not silence the alarm; try the notification.
    }
    if (epoch != _stopEpoch) return;
    try {
      await sunoNotifications.show(
        _notificationId,
        tr.notifTitleLocalAlarm,
        tr.notifBodyLocalAlarm,
        NotificationDetails(
          android: AndroidNotificationDetails(
            localAlarmChannelId,
            tr.chanLocalAlarmName,
            channelDescription: tr.chanLocalAlarmDesc,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            // Tune and vibration come from NativeAlarmPlayer; the channel must
            // add neither, or its vibration would replace the waveform.
            playSound: false,
            enableVibration: false,
            fullScreenIntent: true,
          ),
        ),
        // Same shape as a detection alert so a tap opens that incident; an
        // unknown type here would be filed as an alert from someone else.
        // `alarm=1` tells the tap handler to stop the native tune.
        payload: Uri(
          queryParameters: {
            'type': 'emergency_alert',
            'incidentId': incidentId,
            'alarm': '1',
          },
        ).query,
      );
      // A stop that arrived while show() was in flight has already run its
      // cancel; undo this late post so the alarm does not outlive the window.
      // Only the newest sound may clean up, or this cancel would silence the
      // alarm that superseded it.
      if (epoch != _stopEpoch && serial == _soundSerial) await _cancel();
    } catch (_) {
      // The visible card is best-effort; the tune and vibration already run.
    }
  }

  Future<void> _vibrate(int epoch, int serial, Duration? duration) async {
    try {
      if (!await Vibration.hasVibrator()) return;
      if (epoch != _stopEpoch) return;
      await Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
      if (epoch != _stopEpoch) {
        // stop() already ran its own Vibration.cancel while the plugin call
        // was starting up, so cancel this late start too.
        await Vibration.cancel();
        return;
      }
      if (duration != null) {
        // Belt-and-suspenders: the runtime service's stop timer normally ends
        // this, but a throttled isolate must not let vibration outlast the
        // countdown.
        _vibrationStopTimer?.cancel();
        _vibrationStopTimer = Timer(duration, () {
          _vibrationStopTimer = null;
          if (epoch == _stopEpoch && serial == _soundSerial) {
            unawaited(Vibration.cancel());
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _cancel() async {
    _vibrationStopTimer?.cancel();
    _vibrationStopTimer = null;
    await _player.stop();
    try {
      await sunoNotifications.cancel(_notificationId);
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopEpoch++;
    await _cancel();
  }
}
