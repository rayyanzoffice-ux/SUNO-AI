import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'backend/persistence/app_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive local storage
  await initStorage();

  // Firebase — requires google-services.json (see SETUP_INSTRUCTIONS.md)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured yet — continue in demo mode without push alerts.
  }

  runApp(const SunoApp());
}
