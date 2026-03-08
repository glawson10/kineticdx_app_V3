// lib/features/clinic_settings/clinic_policies_screen.dart
// Clinic → Policies: cancellation, late/no-show, consent (practice policies).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/clinic_policies_settings_repository.dart';
import '../../../models/clinic_policies_settings.dart';
import '../../../ui/design_tokens.dart';

class ClinicPoliciesScreen extends StatelessWidget {
  const ClinicPoliciesScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ClinicPoliciesSettingsRepository>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.settingsFormMaxWidth),
        child: StreamBuilder<ClinicPoliciesSettings>(
          stream: repo.streamSettings(clinicId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _PoliciesForm(
              clinicId: clinicId,
              initial: snapshot.data!,
              onSave: (s) => repo.updateSettings(clinicId, s),
            );
          },
        ),
      ),
    );
  }
}

class _PoliciesForm extends StatefulWidget {
  const _PoliciesForm({
    required this.clinicId,
    required this.initial,
    required this.onSave,
  });

  final String clinicId;
  final ClinicPoliciesSettings initial;
  final void Function(ClinicPoliciesSettings) onSave;

  @override
  State<_PoliciesForm> createState() => _PoliciesFormState();
}

class _PoliciesFormState extends State<_PoliciesForm> {
  late TextEditingController _cancellation;
  late TextEditingController _lateArrival;
  late TextEditingController _noShow;

  @override
  void initState() {
    super.initState();
    _cancellation = TextEditingController(text: widget.initial.cancellationPolicyText);
    _lateArrival = TextEditingController(text: widget.initial.lateArrivalPolicyText);
    _noShow = TextEditingController(text: widget.initial.noShowPolicyText);
  }

  @override
  void dispose() {
    _cancellation.dispose();
    _lateArrival.dispose();
    _noShow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: const BorderSide(color: AppColors.settingsCardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cancellation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _cancellation,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Cancellation policy text (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: const BorderSide(color: AppColors.settingsCardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Late arrival & no-show', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _lateArrival,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Late arrival policy (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noShow,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'No-show policy (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        FilledButton(
          onPressed: () {
            widget.onSave(ClinicPoliciesSettings(
              cancellationPolicyText: _cancellation.text,
              lateArrivalPolicyText: _lateArrival.text,
              noShowPolicyText: _noShow.text,
              policyBundleId: widget.initial.policyBundleId,
              policyBundleVersion: widget.initial.policyBundleVersion,
            ));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Policies saved')),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
