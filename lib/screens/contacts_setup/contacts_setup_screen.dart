import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trusted_contact.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';

class ContactsSetupScreen extends StatefulWidget {
  const ContactsSetupScreen({super.key});
  @override
  State<ContactsSetupScreen> createState() => _ContactsSetupScreenState();
}

class _ContactsSetupScreenState extends State<ContactsSetupScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final relationship = TextEditingController();
  final fcmToken = TextEditingController();
  final contacts = <TrustedContact>[];
  String? myFcmToken;
  bool loadingToken = true;
  String? _loadError;
  final _deletingIds = <String>{};

  String? _editingId;
  bool _saving = false;
  final _testingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadMyToken();
  }

  Future<void> _loadContacts() async {
    try {
      final saved = await SunoRuntimeService.instance.getTrustedContacts();
      if (mounted) {
        setState(() {
          contacts
            ..clear()
            ..addAll(saved);
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Could not load your saved contacts.');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool _busy(String id) =>
      _saving || _testingIds.contains(id) || _deletingIds.contains(id);

  Future<void> _loadMyToken() async {
    setState(() => loadingToken = true);
    try {
      final token = await SunoRuntimeService.instance.refreshDeviceToken();
      if (mounted) setState(() => myFcmToken = token);
    } catch (_) {
      _showError(
        'Token unavailable. Check internet and allow notifications in Android Settings, then retry.',
      );
    } finally {
      if (mounted) setState(() => loadingToken = false);
    }
  }

  Future<void> _copyMyToken() async {
    final token = myFcmToken;
    if (token == null || token.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FCM token copied. Send it to your trusted contact.'),
        ),
      );
    } catch (_) {
      _showError('Could not copy the token. Please retry.');
    }
  }

  Future<void> save() async {
    if (_saving || (_editingId != null && _busy(_editingId!))) return;
    final token = fcmToken.text.trim();
    if (token.isNotEmpty && (token.length < 21 || token.length > 4096)) {
      _showError('Paste the full FCM token copied from the other phone.');
      return;
    }
    if (name.text.trim().isEmpty || relationship.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and relationship are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    final editingId = _editingId;
    try {
      final trimmedToken = fcmToken.text.trim();
      final normalizedToken = trimmedToken.isEmpty ? null : trimmedToken;
      TrustedContact? existing;
      if (editingId != null) {
        final index = contacts.indexWhere((c) => c.id == editingId);
        if (index != -1) existing = contacts[index];
      }

      final contact = TrustedContact(
        id: editingId ?? DateTime.now().toString(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim(),
        fcmToken: normalizedToken,
        verifiedAt: existing?.fcmToken == normalizedToken
            ? existing?.verifiedAt
            : null,
      );

      final saved = editingId == null
          ? await SunoRuntimeService.instance.addTrustedContact(contact)
          : await SunoRuntimeService.instance.updateTrustedContact(contact);

      if (!mounted) return;
      setState(() {
        if (editingId == null) {
          contacts.add(saved);
        } else {
          final index = contacts.indexWhere((c) => c.id == editingId);
          if (index != -1) contacts[index] = saved;
        }
        _clearForm();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editingId == null
                ? 'Trusted contact saved locally.'
                : 'Trusted contact updated.',
          ),
        ),
      );
    } catch (_) {
      _showError(
        'Could not save the contact. Your entries are still here; please retry.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit(TrustedContact contact) {
    if (_busy(contact.id)) return;
    setState(() {
      _editingId = contact.id;
      name.text = contact.name;
      phone.text = contact.phone;
      relationship.text = contact.relationship;
      fcmToken.text = contact.fcmToken ?? '';
    });
  }

  void _clearForm() {
    _editingId = null;
    name.clear();
    phone.clear();
    relationship.clear();
    fcmToken.clear();
  }

  Future<void> _delete(TrustedContact contact) async {
    if (_busy(contact.id)) return;
    setState(() => _deletingIds.add(contact.id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete contact?'),
          content: Text('Remove ${contact.name} from your safety network?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await SunoRuntimeService.instance.removeTrustedContact(contact.id);
      if (!mounted) return;
      setState(() {
        contacts.removeWhere((c) => c.id == contact.id);
        if (_editingId == contact.id) _clearForm();
      });
    } catch (_) {
      _showError('Could not delete the contact. Please retry.');
    } finally {
      if (mounted) setState(() => _deletingIds.remove(contact.id));
    }
  }

  Future<void> _testContact(TrustedContact contact) async {
    if (_busy(contact.id)) return;
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) return;
    setState(() => _testingIds.add(contact.id));
    try {
      final ok = await SunoRuntimeService.instance.testContactNotification(
        contact,
      );
      if (!mounted) return;
      if (ok) {
        final updatedContacts = await SunoRuntimeService.instance
            .getTrustedContacts();
        if (!mounted) return;
        setState(() {
          contacts
            ..clear()
            ..addAll(updatedContacts);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'FCM accepted the silent test for ${contact.name}. Verify visible alerts on both phones separately.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${contact.name} token rejected by FCM. Check the token.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Test failed: $e')));
    } finally {
      if (mounted) setState(() => _testingIds.remove(contact.id));
    }
  }

  String _pushStatus(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return 'Not configured';
    }
    if (contact.isVerified) return 'FCM test accepted';
    return 'Token saved, unverified';
  }

  String _formatVerifiedAt(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Color _pushStatusColor(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return AppColors.textMuted;
    }
    if (contact.isVerified) return AppColors.safe;
    return AppColors.warning;
  }

  IconData _pushStatusIcon(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return Icons.notifications_off_outlined;
    }
    if (contact.isVerified) return Icons.verified_outlined;
    return Icons.notifications_none_outlined;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    relationship.dispose();
    fcmToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trusted contacts')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your safety network',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Contacts are stored locally on this device. Exchange FCM tokens between two phones so SUNO can route emergency push alerts to the trusted contact.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MY FCM TOKEN',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (loadingToken)
                      const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Getting token from Firebase...'),
                          ),
                        ],
                      )
                    else if (myFcmToken == null || myFcmToken!.isEmpty)
                      const Text(
                        'Token unavailable. Check internet, Firebase setup, and notification permission, then refresh below.',
                        style: TextStyle(color: AppColors.textMuted),
                      )
                    else ...[
                      SelectableText(
                        myFcmToken!,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _copyMyToken,
                          icon: const Icon(Icons.copy),
                          label: const Text('COPY MY FCM TOKEN'),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: loadingToken ? null : _loadMyToken,
                      child: const Text('REFRESH MY TOKEN'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_loadError != null) ...[
              Text(
                _loadError!,
                style: const TextStyle(color: AppColors.emergency),
              ),
              TextButton(
                onPressed: _loadContacts,
                child: const Text('RETRY CONTACTS'),
              ),
            ],
            ...contacts.map(
              (contact) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.purple,
                    child: Icon(Icons.person),
                  ),
                  title: Text(
                    contact.name,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.relationship),
                      if (contact.phone.isNotEmpty) Text(contact.phone),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _pushStatusIcon(contact),
                            size: 14,
                            color: _pushStatusColor(contact),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _pushStatus(contact),
                              style: TextStyle(
                                color: _pushStatusColor(contact),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (contact.verifiedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Last accepted test: ${_formatVerifiedAt(contact.verifiedAt!)}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    enabled: !_busy(contact.id),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        _startEdit(contact);
                      } else if (value == 'delete') {
                        await _delete(contact);
                      } else if (value == 'test') {
                        await _testContact(contact);
                      }
                    },
                    itemBuilder: (context) => [
                      if (contact.fcmToken != null &&
                          contact.fcmToken!.trim().isNotEmpty)
                        PopupMenuItem(
                          value: 'test',
                          child: Row(
                            children: [
                              _testingIds.contains(contact.id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined, size: 18),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text('Test FCM acceptance'),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.emergency,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: AppColors.emergency),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _editingId == null ? 'Add a contact' : 'Edit contact',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                helperText: 'Optional — useful for a future call fallback.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationship,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Relationship *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fcmToken,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'FCM token (optional)',
                helperText: 'Needed only for real push alerts to this contact.',
              ),
            ),
            const SizedBox(height: 18),
            PrimaryActionButton(
              label: _editingId == null ? 'SAVE CONTACT' : 'UPDATE CONTACT',
              icon: _editingId == null
                  ? Icons.person_add_alt_1
                  : Icons.check_rounded,
              onPressed: _saving ? null : save,
            ),
            if (_editingId != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: TextButton(
                    onPressed: _saving ? null : () => setState(_clearForm),
                    child: const Text('CANCEL EDIT'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
