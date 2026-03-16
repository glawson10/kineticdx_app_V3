// lib/staff/screens/practitioner_availability_screen.dart
//
// Single Availability hub: Recurring availability + Overrides (sub-tabs).
// PractitionerAvailabilityContent can be embedded (e.g. in team member profile).
// PractitionerAvailabilityScreen is the standalone full-screen route.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/locations_repository.dart';
import '../../data/repositories/practitioner_availability_repository.dart';
import '../../data/repositories/practitioner_overrides_repository.dart';
import '../../models/clinic_location.dart';
import '../../models/practitioner_availability.dart';
import '../../models/availability_override.dart';
import 'practitioner_availability_rule_form_screen.dart';
import 'practitioner_override_form_screen.dart';

/// Standalone screen (e.g. from deep link or legacy entry).
class PractitionerAvailabilityScreen extends StatelessWidget {
  const PractitionerAvailabilityScreen({
    super.key,
    required this.clinicId,
    required this.practitionerId,
    this.practitionerName,
  });

  final String clinicId;
  final String practitionerId;
  final String? practitionerName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Availability – ${practitionerName ?? practitionerId}',
        ),
      ),
      body: PractitionerAvailabilityContent(
        clinicId: clinicId,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
      ),
    );
  }
}

/// Embeddable availability UI: Recurring + Overrides tabs. Use in team member profile or standalone screen.
class PractitionerAvailabilityContent extends StatefulWidget {
  const PractitionerAvailabilityContent({
    super.key,
    required this.clinicId,
    required this.practitionerId,
    this.practitionerName,
  });

  final String clinicId;
  final String practitionerId;
  final String? practitionerName;

  @override
  State<PractitionerAvailabilityContent> createState() =>
      _PractitionerAvailabilityContentState();
}

class _PractitionerAvailabilityContentState
    extends State<PractitionerAvailabilityContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// null = all locations; otherwise single location id for scope.
  String? _locationScopeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationsRepo = context.read<LocationsRepository>();
    final availabilityRepo = context.read<PractitionerAvailabilityRepository>();
    final overridesRepo = context.read<PractitionerOverridesRepository>();

    return StreamBuilder<List<ClinicLocation>>(
      stream: locationsRepo.watchLocations(widget.clinicId),
      builder: (context, locSnap) {
        final locations = locSnap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScopeBar(
              locations: locations,
              scopeId: _locationScopeId,
              onScopeChanged: (id) =>
                  setState(() => _locationScopeId = id),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Recurring availability'),
                Tab(text: 'Overrides'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RecurringTab(
                    clinicId: widget.clinicId,
                    practitionerId: widget.practitionerId,
                    locationScopeId: _locationScopeId,
                    locations: locations,
                    availabilityStream: availabilityRepo.watchAvailabilities(
                      clinicId: widget.clinicId,
                      practitionerId: widget.practitionerId,
                    ),
                    onAddRule: () => _openRuleForm(context, null),
                    onEditRule: (rule) => _openRuleForm(context, rule),
                    onDeleteRule: (rule) => _deleteRule(context, rule),
                    onCopyFromLocation: (list) => _copyFromLocation(context, list),
                  ),
                  _OverridesTab(
                    clinicId: widget.clinicId,
                    practitionerId: widget.practitionerId,
                    locationScopeId: _locationScopeId,
                    locations: locations,
                    overridesStream: overridesRepo.watchOverrides(
                      clinicId: widget.clinicId,
                      practitionerId: widget.practitionerId,
                    ),
                    onAddOverride: ({OverrideReason? preset}) =>
                        _openOverrideForm(context, null, preset: preset),
                    onEditOverride: (o) =>
                        _openOverrideForm(context, o),
                    onDeleteOverride: (o) => _deleteOverride(context, o),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRuleForm(
    BuildContext context,
    PractitionerAvailability? rule,
  ) async {
    final locationsRepo = context.read<LocationsRepository>();
    final locations = await locationsRepo.watchLocations(widget.clinicId).first;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PractitionerAvailabilityRuleFormScreen(
          clinicId: widget.clinicId,
          practitionerId: widget.practitionerId,
          locations: locations,
          existing: rule,
        ),
      ),
    );
  }

  static String _locationNameForId(String id, List<ClinicLocation> locations) {
    for (final l in locations) {
      if (l.id == id) return l.name.isNotEmpty ? l.name : id;
    }
    return id;
  }

  Future<void> _copyFromLocation(
    BuildContext context,
    List<PractitionerAvailability> list,
  ) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rules to copy. Add a rule first.')),
      );
      return;
    }
    final locationsRepo = context.read<LocationsRepository>();
    final locations = await locationsRepo.watchLocations(widget.clinicId).first;
    if (!context.mounted) return;
    final locationIds = list.map((r) => r.locationId).toSet().toList();
    if (locationIds.isEmpty) return;
    String? sourceLocationId = locationIds.length == 1 ? locationIds.first : null;
    PractitionerAvailability? selectedRule;
    String? targetLocationId;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final rulesFromSource = sourceLocationId != null
                ? list.where((r) => r.locationId == sourceLocationId).toList()
                : <PractitionerAvailability>[];
            return AlertDialog(
              title: const Text('Copy from location'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: sourceLocationId,
                      decoration: const InputDecoration(labelText: 'Copy from location'),
                      items: locationIds
                          .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  _locationNameForId(id, locations),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() {
                        sourceLocationId = v;
                        selectedRule = null;
                      }),
                    ),
                    if (rulesFromSource.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PractitionerAvailability>(
                        value: selectedRule != null && rulesFromSource.contains(selectedRule)
                            ? selectedRule
                            : null,
                        decoration: const InputDecoration(labelText: 'Which rule'),
                        items: rulesFromSource
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(
                                    '${r.startDate} ${r.recurrenceRule.frequency}',
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedRule = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: targetLocationId,
                      decoration: const InputDecoration(labelText: 'Duplicate to location'),
                      items: locations
                          .map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text(l.name.isNotEmpty ? l.name : l.id),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => targetLocationId = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: (selectedRule != null && targetLocationId != null &&
                          targetLocationId!.isNotEmpty)
                      ? () async {
                          final patch = selectedRule!.toUpsertPatch();
                          patch['locationId'] = targetLocationId;
                          try {
                            await context
                                .read<PractitionerAvailabilityRepository>()
                                .upsertAvailability(
                                  clinicId: widget.clinicId,
                                  practitionerId: widget.practitionerId,
                                  patch: patch,
                                );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Rule duplicated.')),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          }
                        }
                      : null,
                  child: const Text('Duplicate'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openOverrideForm(
    BuildContext context,
    PractitionerOverride? override, {
    OverrideReason? preset,
  }) async {
    final locationsRepo = context.read<LocationsRepository>();
    final locations = await locationsRepo.watchLocations(widget.clinicId).first;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PractitionerOverrideFormScreen(
          clinicId: widget.clinicId,
          practitionerId: widget.practitionerId,
          locations: locations,
          existing: override,
          presetReason: preset,
        ),
      ),
    );
  }

  Future<void> _deleteRule(BuildContext context, PractitionerAvailability rule) async {
    final locations = await context.read<LocationsRepository>().watchLocations(widget.clinicId).first;
    if (!context.mounted) return;
    final locationName = _locationNameForId(rule.locationId, locations);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete availability rule?'),
        content: Text(
          'Delete this rule at $locationName (${rule.startDate} ${rule.recurrenceRule.frequency})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<PractitionerAvailabilityRepository>().deleteAvailability(
            clinicId: widget.clinicId,
            practitionerId: widget.practitionerId,
            availabilityId: rule.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Availability rule deleted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _deleteOverride(BuildContext context, PractitionerOverride o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete override?'),
        content: Text(
          'Delete override ${_formatDateRange(o.fromAt, o.toAt)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<PractitionerOverridesRepository>().deleteOverride(
            clinicId: widget.clinicId,
            practitionerId: widget.practitionerId,
            overrideId: o.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Override deleted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  static String _formatDateRange(DateTime from, DateTime to) {
    final a = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final b = '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    return '$a to $b';
  }
}

class _ScopeBar extends StatelessWidget {
  const _ScopeBar({
    required this.locations,
    required this.scopeId,
    required this.onScopeChanged,
  });

  final List<ClinicLocation> locations;
  final String? scopeId;
  final void Function(String?) onScopeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              'Location:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 12),
            DropdownButton<String?>(
              value: scopeId,
              hint: const Text('All locations'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All locations'),
                ),
                ...locations.map(
                  (l) => DropdownMenuItem<String?>(
                    value: l.id,
                    child: Text(l.name.isNotEmpty ? l.name : l.id),
                  ),
                ),
              ],
              onChanged: onScopeChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringTab extends StatelessWidget {
  const _RecurringTab({
    required this.clinicId,
    required this.practitionerId,
    required this.locationScopeId,
    required this.locations,
    required this.availabilityStream,
    required this.onAddRule,
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onCopyFromLocation,
  });

  final String clinicId;
  final String practitionerId;
  final String? locationScopeId;
  final List<ClinicLocation> locations;
  final Stream<List<PractitionerAvailability>> availabilityStream;
  final VoidCallback onAddRule;
  final void Function(PractitionerAvailability) onEditRule;
  final void Function(PractitionerAvailability) onDeleteRule;
  final void Function(List<PractitionerAvailability> list) onCopyFromLocation;

  String _locationName(String locationId) {
    for (final l in locations) {
      if (l.id == locationId) return l.name.isNotEmpty ? l.name : l.id;
    }
    return locationId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PractitionerAvailability>>(
      stream: availabilityStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load availability.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var list = snap.data ?? [];
        if (locationScopeId != null) {
          list = list.where((r) => r.locationId == locationScopeId).toList();
        }
        final ruleCount = list.length;
        final locationCount =
            list.map((r) => r.locationId).toSet().length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (ruleCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'You have $ruleCount recurring rule(s) across $locationCount location(s). '
                  'Exceptions (sickness, holidays) are managed in Overrides.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No recurring availability yet. Add a rule for a location and set your usual days and times.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...list.map((rule) => _AvailabilityRuleCard(
                    rule: rule,
                    locationName: _locationName(rule.locationId),
                    onEdit: () => onEditRule(rule),
                    onDelete: () => onDeleteRule(rule),
                  )),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: onAddRule,
                  icon: const Icon(Icons.add),
                  label: const Text('Add rule'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: (locations.isEmpty || list.isEmpty)
                      ? null
                      : () => onCopyFromLocation(list),
                  child: const Text('Copy from location…'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AvailabilityRuleCard extends StatelessWidget {
  const _AvailabilityRuleCard({
    required this.rule,
    required this.locationName,
    required this.onEdit,
    required this.onDelete,
  });

  final PractitionerAvailability rule;
  final String locationName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final byDay = rule.blocksByDay;
    final dayLines = <String>[];
    for (var d = 1; d <= 7; d++) {
      final blocks = byDay[d];
      if (blocks == null || blocks.isEmpty) continue;
      final times = blocks
          .map((b) => '${b.startTime}–${b.endTime}')
          .join(', ');
      dayLines.add('${_days[d]} $times');
    }
    final recurrence = rule.recurrenceRule.interval == 1
        ? (rule.recurrenceRule.frequency == 'weekly'
            ? 'Weekly'
            : rule.recurrenceRule.frequency == 'biweekly'
                ? 'Every 2 weeks'
                : 'Monthly')
        : 'Every ${rule.recurrenceRule.interval} (${rule.recurrenceRule.frequency})';
    final dateRange = rule.endDate != null && rule.endDate!.isNotEmpty
        ? '${rule.startDate} to ${rule.endDate}'
        : 'From ${rule.startDate}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(locationName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$dateRange • $recurrence'),
            if (dayLines.isNotEmpty) Text(dayLines.join('; ')),
            Text(
              rule.hasAnyBookableOnline ? 'Bookable online' : 'Not bookable online',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (rule.description != null && rule.description!.isNotEmpty)
              Text(rule.description!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverridesTab extends StatelessWidget {
  const _OverridesTab({
    required this.clinicId,
    required this.practitionerId,
    required this.locationScopeId,
    required this.locations,
    required this.overridesStream,
    required this.onAddOverride,
    required this.onEditOverride,
    required this.onDeleteOverride,
  });

  final String clinicId;
  final String practitionerId;
  final String? locationScopeId;
  final List<ClinicLocation> locations;
  final Stream<List<PractitionerOverride>> overridesStream;
  final void Function({OverrideReason? preset}) onAddOverride;
  final void Function(PractitionerOverride) onEditOverride;
  final void Function(PractitionerOverride) onDeleteOverride;

  String _locationName(String? locationId) {
    if (locationId == null || locationId.isEmpty) return 'All locations';
    for (final l in locations) {
      if (l.id == locationId) return l.name.isNotEmpty ? l.name : l.id;
    }
    return locationId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PractitionerOverride>>(
      stream: overridesStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load overrides.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var list = snap.data ?? [];
        if (locationScopeId != null) {
          list = list
              .where((o) =>
                  o.locationId == null ||
                  o.locationId!.isEmpty ||
                  o.locationId == locationScopeId)
              .toList();
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Sickness, holidays, training and other one-off changes. '
                'These override your recurring availability.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No overrides. Add sickness, holiday or training when you need to change your usual availability.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...list.map((o) => _OverrideCard(
                    override: o,
                    locationName: _locationName(o.locationId),
                    onEdit: () => onEditOverride(o),
                    onDelete: () => onDeleteOverride(o),
                  )),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => onAddOverride(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add override'),
                ),
                OutlinedButton(
                  onPressed: () => onAddOverride(preset: OverrideReason.sickness),
                  child: const Text('Add sick day'),
                ),
                OutlinedButton(
                  onPressed: () => onAddOverride(preset: OverrideReason.holiday),
                  child: const Text('Add holiday'),
                ),
                OutlinedButton(
                  onPressed: () => onAddOverride(preset: OverrideReason.training),
                  child: const Text('Add training day'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _OverrideCard extends StatelessWidget {
  const _OverrideCard({
    required this.override,
    required this.locationName,
    required this.onEdit,
    required this.onDelete,
  });

  final PractitionerOverride override;
  final String locationName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String _formatDateRange(DateTime from, DateTime to) {
    final a = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final b = '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    return '$a to $b';
  }

  static String _reasonLabel(String? reason) {
    switch (reason?.toLowerCase()) {
      case 'sickness':
        return 'Sickness';
      case 'holiday':
        return 'Holiday';
      case 'training':
        return 'Training';
      default:
        return 'Other';
    }
  }

  Widget build(BuildContext context) {
    final effect = override.isAvailable ? 'Available' : 'Unavailable';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(_formatDateRange(override.fromAt, override.toAt)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$locationName • ${_reasonLabel(override.reason)} • $effect'),
            if (override.description != null && override.description!.isNotEmpty)
              Text(
                override.description!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
