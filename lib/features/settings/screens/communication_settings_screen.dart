// lib/features/settings/screens/communication_settings_screen.dart
// Communication → Defaults: reply-to email, default reminder channel.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/communication_settings_repository.dart';
import '../../../models/communication_settings.dart';

class CommunicationSettingsScreen extends StatelessWidget {
  const CommunicationSettingsScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    if (clinicId.trim().isEmpty) {
      return const Center(child: Text('No clinic selected.'));
    }
    final repo = context.read<CommunicationSettingsRepository>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<CommunicationSettings>(
        stream: repo.streamSettings(clinicId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load communication settings.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final settings = snapshot.data!;
          return _CommunicationForm(
            clinicId: clinicId,
            initial: settings,
            onSave: (patch) => repo.updateSettings(clinicId, patch),
          );
        },
      ),
    );
  }
}

class _CommunicationForm extends StatefulWidget {
  const _CommunicationForm({
    required this.clinicId,
    required this.initial,
    required this.onSave,
  });

  final String clinicId;
  final CommunicationSettings initial;
  final void Function(Map<String, dynamic>) onSave;

  @override
  State<_CommunicationForm> createState() => _CommunicationFormState();
}

class _CommunicationFormState extends State<_CommunicationForm> {
  late TextEditingController _replyTo;
  late String _channel;

  @override
  void initState() {
    super.initState();
    _replyTo = TextEditingController(text: widget.initial.defaultReplyToEmail);
    _channel = widget.initial.defaultReminderChannel.value;
  }

  @override
  void dispose() {
    _replyTo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _replyTo,
          decoration: const InputDecoration(
            labelText: 'Default reply-to email',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _channel,
          decoration: const InputDecoration(
            labelText: 'Default reminder channel',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'email', child: Text('Email')),
            DropdownMenuItem(value: 'sms', child: Text('SMS')),
            DropdownMenuItem(value: 'both', child: Text('Both')),
            DropdownMenuItem(value: 'none', child: Text('None')),
          ],
          onChanged: (v) => setState(() => _channel = v ?? 'email'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            widget.onSave({
              'defaultReplyToEmail': _replyTo.text.trim(),
              'defaultReminderChannel': _channel,
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Communication settings saved')),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
