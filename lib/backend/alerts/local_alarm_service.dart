import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../../core/l10n/l10n.dart';
import '../../services/detection_notification_service.dart'
    show
        alarmVibration,
        localAlarmChannelId,
        localAlarmSound,
        sunoNotifications;

/// Last-resort alert for a device that reached nobody: a loud notification
/// that repeats until it is tapped, plus vibration. Both run entirely on the
/// phone, so they still work with no SIM, no signal and no SMS balance.
class LocalAlarmService {
  LocalAlarmService();

  // A fixed id keeps a second failed dispatch from stacking alarms.
  static const _notificationId = 0x50A0;

  /// Bumped by [stop]. A [sound] call that was already in flight when the
  /// countdown ended must not post a notification after the stop, or the
  /// alarm would ring past the 45-second window.
  int _stopEpoch = 0;

  /// Identifies the newest [sound] call so an older, slower one cannot cancel
  /// an alarm that a newer call (for example, the post-escalation last resort)
  /// has just posted.
  int _soundSerial = 0;

  Future<void> sound({required String incidentId}) async {
    final epoch = _stopEpoch;
    final serial = ++_soundSerial;
    // Android 13+ can silently drop a notification (and its sound) when the
    // permission is denied: show() still completes, so the catch below would
    // never run. Probe first and vibrate instead, otherwise the alarm is mute.
    try {
      final android = sunoNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() == false) {
        await _vibrate(epoch);
        return;
      }
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
            audioAttributesUsage: AudioAttributesUsage.alarm,
            sound: localAlarmSound,
            playSound: true,
            enableVibration: true,
            vibrationPattern: alarmVibration,
            fullScreenIntent: true,
            // NotificationCompat.FLAG_INSISTENT: repeat the sound and
            // vibration until this notification is tapped or cancelled.
            additionalFlags: Int32List.fromList(<int>[4]),
          ),
        ),
        // Same shape as a detection alert so a tap opens that incident; an
        // unknown type here would be filed as an alert from someone else.
        payload: Uri(
          queryParameters: {
            'type': 'emergency_alert',
            'incidentId': incidentId,
          },
        ).query,
      );
      // A stop that arrived while show() was in flight has already run its
      // cancel; undo this late post so the alarm does not outlive the window.
      // Only the newest sound may clean up, or this cancel would silence the
      // alarm that superseded it.
      if (epoch != _stopEpoch && serial == _soundSerial) await _cancel();
    } catch (_) {
      // Last-ditch fallback inside the last resort: if the notification
      // itself is unavailable, at least keep the device buzzing.
      await _vibrate(epoch);
    }
  }

  Future<void> _vibrate(int epoch) async {
    try {
      if (!await Vibration.hasVibrator()) return;
      if (epoch != _stopEpoch) return;
      await Vibration.vibrate(pattern: alarmVibration, repeat: 0);
      // stop() already ran its own Vibration.cancel while the plugin call was
      // starting up, so cancel this late start too.
      if (epoch != _stopEpoch) await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> _cancel() async {
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
