import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/routes/app_routes.dart';
import '../core/theme/app_theme.dart';
import '../models/trusted_contact.dart';
import '../services/suno_runtime_service.dart';

/// Opens the Silent SOS contact picker as a themed bottom sheet.
///
/// This is the entry point for [SunoRuntimeService.triggerManualAlert] — a
/// deliberate, silent action that skips audio/motion detection entirely
/// and creates a critical incident directly. Intended for emergencies that
/// are silent or purely visual/physical, which no amount of audio or
/// motion detection can ever cover.
Future<void> showSilentSosSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _SilentSosSheet(),
  );
}

class _SilentSosSheet extends StatefulWidget {
  const _SilentSosSheet();

  @override
  State<_SilentSosSheet> createState() => _SilentSosSheetState();
}

class _SilentSosSheetState extends State<_SilentSosSheet> {
  List<TrustedContact>? _contacts;
  bool _sending = false;

  /// Kept as a message selector, not a resolved string, so the sheet always
  /// shows the language in use rather than the one active when it failed.
  String Function(AppLocalizations)? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await SunoRuntimeService.instance.getTrustedContacts();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = (l10n) => l10n.sosContactsLoadFailed);
      }
    }
  }

  Future<void> _send({String? contactId}) async {
    if (_sending) return;
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final incident = await SunoRuntimeService.instance.triggerManualAlert(
        onlyContactId: contactId,
      );
      if (!mounted || incident == null) return;
      navigator.pop();
      navigator.pushNamedAndRemoveUntil(
        AppRoutes.emergencyAlert,
        (route) => route.settings.name == AppRoutes.home || route.isFirst,
        arguments: incident.id,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = (l10n) => l10n.sosSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 60),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 14,
            bottom: 22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.emergency.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_moon_rounded,
                        color: AppColors.emergency,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.sosTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sosIntro,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l10n.sosOsNote,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) ...[
                  Text(
                    _error!(l10n),
                    style: const TextStyle(color: AppColors.emergency),
                  ),
                  if (_contacts == null)
                    TextButton(
                      onPressed: _loadContacts,
                      child: Text(l10n.commonRetry),
                    ),
                ],
                if (_contacts == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_contacts?.isEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l10n.sosNoContacts,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  )
                else
                  ...((_contacts ?? <TrustedContact>[]).map(
                    (contact) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.purple,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          contact.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(contact.relationship),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        onTap: _sending
                            ? null
                            : () => _send(contactId: contact.id),
                      ),
                    ),
                  )),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : () => _send(),
                    icon: const Icon(Icons.campaign_rounded),
                    label: Text(_sending ? l10n.sosSending : l10n.sosAlertAll),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emergency,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.sosCancel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
