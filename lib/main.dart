import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'backend/alerts/fcm_alert_service.dart';
import 'backend/persistence/app_storage.dart';
import 'backend/persistence/hive_incident_repository.dart';
import 'backend/persistence/hive_trusted_contact_repository.dart';
import 'services/suno_runtime_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initStorage();

  FcmAlertService? alertService;
  try {
    await Firebase.initializeApp();
    alertService = FcmAlertService(messaging: FirebaseMessaging.instance);
    await alertService.registerDevice();
  } catch (_) {
    alertService = null;
  }

  SunoRuntimeService.instance = SunoRuntimeService(
    incidentRepository: const HiveIncidentRepository(),
    trustedContactRepository: const HiveTrustedContactRepository(),
    alertService: alertService,
  );

  runApp(const SunoApp());
}
