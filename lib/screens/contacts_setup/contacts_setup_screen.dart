import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
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
  final _myName = TextEditingController();
  final contacts = <TrustedContact>[];
  String? myFcmToken;
  bool loadingToken = true;
  bool _loadFailed = false;
  final _deletingIds = <String>{};

  String? _editingId;
  bool _saving = false;
  final _testingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadMyToken();
    _loadMyName();
  }

  Future<void> _loadContacts() async {
    try {
      final saved = await SunoRuntimeService.instance.getTrustedContacts();
      if (mounted) {
        setState(() {
          contacts
            ..clear()
            ..addAll(saved);
          _loadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// Shows [message] resolved against the language currently in use, so no
  /// untranslated string is ever kept in state.
  void _showError(String Function(AppLocalizations) message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message(context.l10n))),
      );
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
      _showError((l10n) => l10n.contactsTokenUnavailable);
    } finally {
      if (mounted) setState(() => loadingToken = false);
    }
  }

  Future<void> _loadMyName() async {
    try {
      final saved = await SunoRuntimeService.instance.getMyName();
      if (mounted && saved != null && _myName.text.isEmpty) {
        _myName.text = saved;
      }
    } catch (_) {
      _showError((l10n) => l10n.contactsMyNameLoadFailed);
    }
  }

  Future<void> _saveMyName() async {
    try {
      await SunoRuntimeService.instance.saveMyName(_myName.text);
    } catch (_) {
      _showError((l10n) => l10n.contactsMyNameSaveFailed);
    }
  }

  Future<void> _copyMyToken() async {
    final token = myFcmToken;
    if (token == null || token.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.contactsTokenCopied)),
      );
    } catch (_) {
      _showError((l10n) => l10n.contactsTokenCopyFailed);
    }
  }

  Future<void> save() async {
    if (_saving || (_editingId != null && _busy(_editingId!))) return;
    final token = fcmToken.text.trim();
    if (token.isNotEmpty && (token.length < 21 || token.length > 4096)) {
      _showError((l10n) => l10n.contactsTokenTooShort);
      return;
    }
    if (name.text.trim().isEmpty || relationship.text.trim().isEmpty) {
      _showError((l10n) => l10n.contactsNameRelationshipRequired);
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
                ? context.l10n.contactsSaved
                : context.l10n.contactsUpdated,
          ),
        ),
      );
    } catch (_) {
      _showError((l10n) => l10n.contactsSaveFailed);
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
        builder: (context) {
          final l10n = context.l10n;
          return AlertDialog(
            title: Text(l10n.contactsDeleteDialogTitle),
            content: Text(l10n.contactsDeleteDialogBody(contact.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.contactsDeleteDialogConfirm),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
      await SunoRuntimeService.instance.removeTrustedContact(contact.id);
      if (!mounted) return;
      setState(() {
        contacts.removeWhere((c) => c.id == contact.id);
        if (_editingId == contact.id) _clearForm();
      });
    } catch (_) {
      _showError((l10n) => l10n.contactsDeleteFailed);
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
            content: Text(context.l10n.contactsTestAccepted(contact.name)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.contactsTestRejected(contact.name)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.contactsTestFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _testingIds.remove(contact.id));
    }
  }

  String _pushStatus(TrustedContact contact, AppLocalizations l10n) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return l10n.contactsStatusNotConfigured;
    }
    if (contact.isVerified) return l10n.contactsStatusVerified;
    return l10n.contactsStatusUnverified;
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
    _myName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.contactsTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.contactsHeading,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.contactsIntro,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.contactsMyFcmToken,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loadingToken)
                        Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(l10n.contactsTokenLoading),
                            ),
                          ],
                        )
                      else if (myFcmToken == null || myFcmToken!.isEmpty)
                        Text(
                          l10n.contactsTokenUnavailableBody,
                          style: const TextStyle(color: AppColors.textMuted),
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
                            label: Text(l10n.contactsCopyToken),
                          ),
                        ),
                      ],
                      TextButton(
                        onPressed: loadingToken ? null : _loadMyToken,
                        child: Text(l10n.contactsRefreshToken),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _myName,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [LengthLimitingTextInputFormatter(40)],
                    onChanged: (_) => unawaited(_saveMyName()),
                    decoration: InputDecoration(
                      labelText: l10n.contactsYourName,
                      helperText: l10n.contactsYourNameHelper,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_loadFailed) ...[
                Text(
                  l10n.contactsLoadFailed,
                  style: const TextStyle(color: AppColors.emergency),
                ),
                TextButton(
                  onPressed: _loadContacts,
                  child: Text(l10n.contactsRetry),
                ),
              ],
              ...contacts.map(
                (contact) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsetsDirectional.fromSTEB(
                      14,
                      14,
                      6,
                      14,
                    ),
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
                                _pushStatus(contact, l10n),
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
                              l10n.contactsLastAcceptedTest(
                                formatIsoStamp(contact.verifiedAt!),
                              ),
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
                                    : Transform.flip(
                                        flipX: Directionality.of(context) ==
                                            TextDirection.rtl,
                                        child: const Icon(
                                          Icons.send_outlined,
                                          size: 18,
                                        ),
                                      ),
                                const SizedBox(width: 10),
                                Flexible(child: Text(l10n.contactsMenuTest)),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(Icons.edit_outlined, size: 18),
                              const SizedBox(width: 10),
                              Text(l10n.commonEdit),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppColors.emergency,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l10n.commonDelete,
                                style: const TextStyle(
                                  color: AppColors.emergency,
                                ),
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
                _editingId == null
                    ? l10n.contactsAddHeading
                    : l10n.contactsEditHeading,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.contactsFieldName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.contactsFieldPhone,
                  helperText: l10n.contactsFieldPhoneHelper,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: relationship,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.contactsFieldRelationship,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fcmToken,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.contactsFieldToken,
                  helperText: l10n.contactsFieldTokenHelper,
                ),
              ),
              const SizedBox(height: 18),
              PrimaryActionButton(
                label: _editingId == null
                    ? l10n.contactsSaveButton
                    : l10n.contactsUpdateButton,
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
                      child: Text(l10n.contactsCancelEdit),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
