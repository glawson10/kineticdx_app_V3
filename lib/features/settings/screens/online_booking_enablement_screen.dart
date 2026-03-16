// Online booking enablement overview: global state + visible entities summary and links.
// Does not duplicate toggles that live on entity forms; provides summary and navigation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/appointment_types_repository.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../data/repositories/public_booking_settings_repository.dart';
import '../../../data/repositories/staff_repository.dart';
import '../../../models/appointment_type.dart';
import '../../../models/clinic_location.dart';
import '../../../models/public_booking_settings.dart';
import '../home/settings_home_screen.dart';

class OnlineBookingEnablementScreen extends StatelessWidget {
  const OnlineBookingEnablementScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    final c = clinicId.trim();
    if (c.isEmpty) {
      return const Center(child: Text('No clinic selected.'));
    }

    return StreamBuilder<PublicBookingSettings>(
      stream: context.read<PublicBookingSettingsRepository>().streamSettings(c),
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data ?? const PublicBookingSettings();
        final enabled = settings.onlineBookingEnabled;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Online booking enablement',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Summary of what is visible on the public booking page. Toggle global enablement and manage visibility per location, practitioner, and appointment type in their respective settings.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              _SummaryCard(
                title: 'Global online booking',
                subtitle: enabled
                    ? 'Public booking is enabled. Visitors can see the booking page.'
                    : 'Public booking is off. Visitors cannot book online.',
                trailing: Chip(
                  label: Text(enabled ? 'On' : 'Off'),
                  backgroundColor: enabled
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                onTap: () => _openSettingsSection(context, c, 'scheduling'),
              ),
              const SizedBox(height: 16),
              _VisibleLocationsSection(clinicId: c),
              const SizedBox(height: 16),
              _VisiblePractitionersSection(clinicId: c),
              const SizedBox(height: 16),
              _VisibleAppointmentTypesSection(clinicId: c),
            ],
          ),
        );
      },
    );
  }

  static void _openSettingsSection(BuildContext context, String clinicId, String sectionSlug) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsHomeScreen(clinicId: clinicId, initialSection: sectionSlug),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibleLocationsSection extends StatelessWidget {
  const _VisibleLocationsSection({required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClinicLocation>>(
      stream: context.read<LocationsRepository>().watchLocations(clinicId),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final visible = all.where((l) => l.active && l.showInOnlineBooking).toList();
        return _EntitySummaryCard(
          title: 'Visible locations',
          count: visible.length,
          total: all.length,
          names: visible.map((l) => l.name).toList(),
          emptyMessage: 'No locations visible. Add and enable locations in Settings → Locations.',
          onTap: () => OnlineBookingEnablementScreen._openSettingsSection(context, clinicId, 'locations'),
        );
      },
    );
  }
}

class _VisiblePractitionersSection extends StatelessWidget {
  const _VisiblePractitionersSection({required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    final staffRepo = context.read<StaffRepository>();
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: staffRepo.watchPractitionerBookingMetas(clinicId).map((docs) => docs.where((d) => d.data()['showInPublicBooking'] == true).toList()),
      builder: (context, snap) {
        final visibleDocs = snap.data ?? [];
        final count = visibleDocs.length;
        return _EntitySummaryCard(
          title: 'Visible practitioners',
          count: count,
          total: null,
          names: const [],
          emptyMessage: 'No practitioners visible for public booking. Edit staff and enable "Show in public booking" in Settings → Scheduling → Practitioners.',
          onTap: () => OnlineBookingEnablementScreen._openSettingsSection(context, clinicId, 'scheduling'),
        );
      },
    );
  }
}

class _VisibleAppointmentTypesSection extends StatelessWidget {
  const _VisibleAppointmentTypesSection({required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppointmentType>>(
      stream: context.read<AppointmentTypesRepository>().watchAllTypes(clinicId),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final visible = all.where((t) => t.active && t.showInOnlineBooking).toList();
        return _EntitySummaryCard(
          title: 'Visible appointment types',
          count: visible.length,
          total: all.length,
          names: visible.map((t) => t.name).toList(),
          emptyMessage: 'No appointment types visible. Add types and enable "Show in online booking" in Settings → Appointment types.',
          onTap: () => OnlineBookingEnablementScreen._openSettingsSection(context, clinicId, 'scheduling'),
        );
      },
    );
  }
}

class _EntitySummaryCard extends StatelessWidget {
  const _EntitySummaryCard({
    required this.title,
    required this.count,
    required this.total,
    required this.names,
    required this.emptyMessage,
    required this.onTap,
  });

  final String title;
  final int count;
  final int? total;
  final List<String> names;
  final String emptyMessage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = total != null
        ? '$count of $total visible'
        : '$count visible';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (names.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  emptyMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ] else if (names.length <= 5) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: names.map((n) => Chip(label: Text(n, style: const TextStyle(fontSize: 12)))).toList(),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: names.take(5).map((n) => Chip(label: Text(n, style: const TextStyle(fontSize: 12)))).toList(),
                ),
                const SizedBox(height: 4),
                Text(
                  '+ ${names.length - 5} more',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
