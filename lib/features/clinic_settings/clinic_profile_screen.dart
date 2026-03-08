// lib/features/clinic/settings/ui/clinic_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/clinic_context.dart';

import '../settings/widgets/clinic_general_settings_form.dart';
import 'clinic_closures_screen.dart';
import 'audit/closure_override_audit_screen.dart';
import 'audit/staff_profile_audit_screen.dart';

// ✅ Opening hours UI
import '../clinic/settings/ui/clinic_opening_hours_screen.dart';

// ✅ Staff settings UI
import '../../staff/staff_settings_screen.dart';
import '../notes/ui/notes_settings_screen.dart';
import '../settings/ui/clinical_test_registry_screen.dart';
import '../settings/security_screen.dart';
import '../billing/ui/billing_settings_screen.dart';

/// Settings hub screen (inside Settings tab).
/// - Clinic profile (edit)
/// - Staff
/// - Closures
/// - Closure override audit
/// - Clinic opening hours
class ClinicProfileScreen extends StatelessWidget {
  const ClinicProfileScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute(builder: (_) => const ClinicProfileScreen());
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    if (!clinicCtx.hasClinic) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected.')),
      );
    }

    // ✅ Session may not be bootstrapped yet (avoid throwing)
    if (!clinicCtx.hasSession) {
      return Scaffold(
        appBar: AppBar(title: const SizedBox.shrink()), // Title in shell only
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final clinicId = clinicCtx.clinicId;

    final session = clinicCtx.session;
    final canWriteSettings = session.permissions.has('settings.write');
    final canAudit = session.permissions.has('audit.read');
    final canViewNotes = session.permissions.viewClinical;
    final canManageNotes = session.permissions.settingsWrite;

    final canManageStaff = session.permissions.has('members.manage');
    final canReadMembers =
        session.permissions.has('members.read') || canManageStaff;

    return Scaffold(
      appBar: AppBar(title: const SizedBox.shrink()), // Title in shell only
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // ─────────────────────────────
          // Clinic profile
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Clinic profile'),
            subtitle: Text(
              canWriteSettings
                  ? 'Name, logo, contact, timezone. Or use Settings → Clinic → General.'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _ClinicProfileEditScreen(),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Security (account-level MFA)
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Security'),
            subtitle: const Text('Two-step verification (MFA)'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Staff (legacy entrypoint — migrating to Settings → Team)
          // Remove when: Settings → Team has invite (09), practitioner profile (10),
          // suspend/edit, smoke tests (19), and dogfood pass complete. See docs/STAFF_LEGACY_REMOVAL.md.
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Row(
              children: [
                const Text('Staff'),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    'Legacy',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              canReadMembers
                  ? 'Migrating to Settings → Team. Invite, suspend, permissions.'
                  : 'No permission (members.read required)',
            ),
            enabled: canReadMembers,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StaffSettingsScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Notes templates
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.note_outlined),
            title: const Text('Notes templates'),
            subtitle: Text(
              canViewNotes
                  ? (canManageNotes
                      ? 'View and manage templates'
                      : 'View templates (read-only)')
                  : 'No permission (clinical.read or notes.read required)',
            ),
            enabled: canViewNotes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotesSettingsScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Clinical test registry
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Clinical test registry'),
            subtitle: Text(
              canViewNotes
                  ? (canManageNotes
                      ? 'Manage objective/special tests for this clinic'
                      : 'View registry (read-only)')
                  : 'No permission (clinical.read or notes.read required)',
            ),
            enabled: canViewNotes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ClinicalTestRegistryScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Billing
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: const Text('Billing'),
            subtitle: Text(
              canWriteSettings || session.permissions.has('manageBilling')
                  ? 'Invoice settings, supplier profile, payment methods'
                  : 'No permission (manageBilling or settings.write required)',
            ),
            enabled: canWriteSettings || session.permissions.has('manageBilling'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BillingSettingsScreen(),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Opening hours
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Clinic opening hours'),
            subtitle: Text(
              canWriteSettings
                  ? 'Set opening hours for each day (affects clinician + public booking)'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ClinicOpeningHoursScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Closures
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Closures'),
            subtitle: Text(
              canWriteSettings
                  ? 'Manage closed hours / holidays'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClinicClosuresScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Audit
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Closure override audit'),
            subtitle: Text(
              canAudit
                  ? 'View overrides + export'
                  : 'No permission (audit.read required)',
            ),
            enabled: canAudit,
            onTap: () => Navigator.of(context).push(
              ClosureOverrideAuditScreen.route(),
            ),
          ),

          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Staff profile audit'),
            subtitle: Text(
              canAudit
                  ? 'View profile and availability changes'
                  : 'No permission (audit.read required)',
            ),
            enabled: canAudit,
            onTap: () => Navigator.of(context).push(
              StaffProfileAuditScreen.route(),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Profile editor screen; reuses shared [ClinicGeneralSettingsForm].
class _ClinicProfileEditScreen extends StatelessWidget {
  const _ClinicProfileEditScreen();

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasClinic) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Clinic profile')),
      body: SafeArea(
        child: ClinicGeneralSettingsForm(
          clinicId: clinicCtx.clinicId,
          showSaveButton: true,
        ),
      ),
    );
  }
}
