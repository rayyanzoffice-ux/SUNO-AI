import 'package:flutter/material.dart';

import '../../screens/contacts_setup/contacts_setup_screen.dart';
import '../../screens/emergency_alert/emergency_alert_screen.dart';
import '../../screens/history/history_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/monitoring/monitoring_screen.dart';
import '../../screens/safety_check/safety_check_screen.dart';
import '../../screens/trusted_contact/trusted_contact_view_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const monitoring = '/monitoring';
  static const safetyCheck = '/safety-check';
  static const emergencyAlert = '/emergency-alert';
  static const trustedContactView = '/trusted-contact-view';
  static const history = '/history';
  static const contactsSetup = '/contacts-setup';

  static final routes = <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    monitoring: (_) => const MonitoringScreen(),
    safetyCheck: (_) => const SafetyCheckScreen(),
    emergencyAlert: (_) => const EmergencyAlertScreen(),
    trustedContactView: (_) => const TrustedContactViewScreen(),
    history: (_) => const HistoryScreen(),
    contactsSetup: (_) => const ContactsSetupScreen(),
  };
}
