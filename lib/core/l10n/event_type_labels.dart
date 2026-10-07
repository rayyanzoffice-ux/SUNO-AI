import 'package:suno_ai/l10n/app_localizations.dart';

/// Translates a stored/received `eventType` for display.
///
/// `eventType` is saved in Hive and sent to contacts as an English string, and
/// that contract must not change (old history and other phones depend on it).
/// So the raw value is mapped to a translated label **only when shown**.
/// Unknown values (for example from a newer app version) are shown as-is
/// rather than hidden.
String localizedEventType(AppLocalizations l10n, String raw) =>
    switch (raw.trim()) {
      'Distress Sound' => l10n.eventDistressSound,
      'Emergency Alarm' => l10n.eventEmergencyAlarm,
      'Impact / Breaking Sound' => l10n.eventImpactBreaking,
      'Ambient Sound' => l10n.eventAmbientSound,
      'Possible Distress Sound' => l10n.eventPossibleDistress,
      'Distress Sound + Impact' => l10n.eventDistressImpact,
      'Manual Silent Alert' => l10n.eventManualSilentAlert,
      'Emergency Alert' || 'Emergency' => l10n.eventEmergencyAlert,
      _ => raw,
    };
