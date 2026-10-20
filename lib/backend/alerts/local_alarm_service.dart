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
  const LocalAlarmService();

  // A fixed id keeps a second failed dispatch from stacking alarms.
  static const _notificationId = 0x50A0;

  Future<void> sound({required String incidentId}) async {
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
    } catch (_) {
      // Last-ditch fallback inside the last resort: if the notification
      // itself is unavailable, at least keep the device buzzing.
      try {
        final bool? hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator ?? false) {
          await Vibration.vibrate(pattern: alarmVibration, repeat: 0);
        }
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    try {
      await sunoNotifications.cancel(_notificationId);
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
