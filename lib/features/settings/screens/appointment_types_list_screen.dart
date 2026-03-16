// lib/features/settings/screens/appointment_types_list_screen.dart
//
// Settings → Scheduling → Appointment types. Streams all types; edit via
// AppointmentTypeFormScreen (pushed); active toggle via settingsSetAppointmentTypeActive.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/callable_error_mapping.dart';
import '../../../data/repositories/appointment_types_repository.dart';
import '../../../models/appointment_type.dart';
import 'appointment_type_form_screen.dart';

class AppointmentTypesListScreen extends StatelessWidget {
  const AppointmentTypesListScreen({
    super.key,
    required this.clinicId,
  });

  final String clinicId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppointmentTypesRepository>();
    return StreamBuilder<List<AppointmentType>>(
      stream: repo.watchAllTypes(clinicId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load appointment types: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final types = snap.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Appointment types',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Used in clinic calendar, public booking and price list. Set name, duration, price and visibility.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _openForm(context, clinicId, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add appointment type'),
                ),
              ),
              const SizedBox(height: 16),
              if (types.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No appointment types yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add types (e.g. Initial consultation, Follow-up) to use in the calendar and online booking.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _openForm(context, clinicId, null),
                          child: const Text('Add appointment type'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...types.map((type) => _AppointmentTypeCard(
                      clinicId: clinicId,
                      type: type,
                      onEdit: () => _openForm(context, clinicId, type),
                      onToggleActive: () => _setActive(context, repo, clinicId, type),
                    )),
            ],
          ),
        );
      },
    );
  }

  static void _openForm(BuildContext context, String clinicId, AppointmentType? type) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(type != null ? 'Edit appointment type' : 'Add appointment type'),
            leading: const BackButton(),
          ),
          body: AppointmentTypeFormScreen(
            clinicId: clinicId,
            type: type,
            onSaved: () => Navigator.of(context).pop(),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  static Future<void> _setActive(
    BuildContext context,
    AppointmentTypesRepository repo,
    String clinicId,
    AppointmentType type,
  ) async {
    final next = !type.active;
    try {
      await repo.setActive(clinicId, type.id, next);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? '${type.name} is now active' : '${type.name} is now inactive'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageForCallableError(
            e,
            fallback: 'Failed to update appointment type.',
            logHint: 'settingsSetAppointmentTypeActive',
          )),
        ),
      );
    }
  }
}

class _AppointmentTypeCard extends StatelessWidget {
  const _AppointmentTypeCard({
    required this.clinicId,
    required this.type,
    required this.onEdit,
    required this.onToggleActive,
  });

  final String clinicId;
  final AppointmentType type;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceStr = type.defaultPrice != null
        ? type.defaultPrice! == type.defaultPrice!.roundToDouble()
            ? type.defaultPrice!.round().toString()
            : type.defaultPrice!.toStringAsFixed(2)
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: type.active
              ? (type.colorHex != null
                  ? _parseColor(type.colorHex!) ?? theme.colorScheme.primaryContainer
                  : theme.colorScheme.primaryContainer)
              : theme.colorScheme.surfaceContainerHighest,
          child: Builder(
            builder: (_) {
              final parsed = type.colorHex != null ? _parseColor(type.colorHex!) : null;
              final textColor = type.active
                  ? (parsed != null ? _contrastColor(parsed) : theme.colorScheme.onPrimaryContainer)
                  : theme.colorScheme.onSurfaceVariant;
              return Text(
                type.name.isNotEmpty ? type.name.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
        title: Text(
          type.name,
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: type.active ? null : TextDecoration.lineThrough,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${type.durationMinutes} min'
                  + (priceStr != null ? ' • $priceStr' : '')
                  + (type.showInOnlineBooking ? ' • Online booking' : ''),
              style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ),
            if (type.description != null && type.description!.isNotEmpty)
              Text(
                type.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(
              label: Text(type.active ? 'Active' : 'Inactive'),
              selected: type.active,
              onSelected: (_) => onToggleActive(),
              showCheckmark: false,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
          ],
        ),
      ),
    );
  }

  static Color? _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6 && h.length != 8) return null;
    final r = int.tryParse(h.substring(0, 2), radix: 16);
    final g = int.tryParse(h.substring(2, 4), radix: 16);
    final b = int.tryParse(h.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(255, r, g, b);
  }

  static Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  }
}
