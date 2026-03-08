// lib/features/settings/screens/locations_list_screen.dart
//
// Settings → Locations → List. Streams clinics/{clinicId}/locations; edit via
// LocationFormScreen; active toggle via settingsSetLocationActive callable.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../data/repositories/locations_repository.dart';
import '../../../models/clinic_location.dart';

class LocationsListScreen extends StatelessWidget {
  const LocationsListScreen({
    super.key,
    required this.clinicId,
    this.onEdit,
    this.onAdd,
    this.onEditLocation,
  });

  final String clinicId;
  final void Function(dynamic location)? onEdit;
  final VoidCallback? onAdd;
  final void Function(dynamic location)? onEditLocation;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<LocationsRepository>();
    return StreamBuilder<List<ClinicLocation>>(
      stream: repo.watchLocations(clinicId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load locations: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final locations = snap.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Locations',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage clinic locations. They can be used in the booking calendar and practitioner availability.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              if (onAdd != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add location'),
                    ),
                  ),
                ),
              if (locations.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No locations yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a location to use in the calendar and practitioner availability.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        if (onAdd != null) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: onAdd,
                            child: const Text('Add location'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...locations.map((loc) => _LocationCard(
                      location: loc,
                      onEdit: onEditLocation ?? onEdit,
                      onToggleActive: () => _setActive(context, repo, clinicId, loc),
                    )),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _setActive(
    BuildContext context,
    LocationsRepository repo,
    String clinicId,
    ClinicLocation loc,
  ) async {
    final next = !loc.active;
    try {
      await repo.setActive(clinicId, loc.id, next);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? '${loc.name} is now active' : '${loc.name} is now inactive'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageForCallableError(e, fallback: 'Failed to update location')),
        ),
      );
    }
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.onEdit,
    required this.onToggleActive,
  });

  final ClinicLocation location;
  final void Function(dynamic location)? onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: location.active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.location_on_outlined,
            color: location.active
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          location.name,
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: location.active ? null : TextDecoration.lineThrough,
              ),
        ),
        subtitle: location.addressText.trim().isEmpty
            ? null
            : Text(
                location.addressText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(
              label: Text(location.active ? 'Active' : 'Inactive'),
              selected: location.active,
              onSelected: (_) => onToggleActive(),
              showCheckmark: false,
            ),
            const SizedBox(width: 8),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit!(location),
                tooltip: 'Edit',
              ),
          ],
        ),
      ),
    );
  }
}
