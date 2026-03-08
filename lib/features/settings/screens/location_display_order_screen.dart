// lib/features/settings/screens/location_display_order_screen.dart
// Locations → Display order: reorder list + default location dropdown.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/location_display_repository.dart';
import '../../../../data/repositories/locations_repository.dart';
import '../../../../models/clinic_location.dart';
import '../../../../models/location_display_settings.dart';
import '../../../../ui/design_tokens.dart';

class LocationDisplayOrderScreen extends StatelessWidget {
  const LocationDisplayOrderScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    final displayRepo = context.read<LocationDisplayRepository>();
    final locationsRepo = context.read<LocationsRepository>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.settingsFormMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Display order & default',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            StreamBuilder<LocationDisplaySettings>(
              stream: displayRepo.streamSettings(clinicId),
              builder: (context, displaySnap) {
                if (!displaySnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final display = displaySnap.data!;
                return StreamBuilder<List<ClinicLocation>>(
                  stream: locationsRepo.watchLocations(clinicId),
                  builder: (context, locSnap) {
                    if (!locSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final locations = locSnap.data!;
                    return _DisplayOrderForm(
                      clinicId: clinicId,
                      locations: locations,
                      display: display,
                      onSave: (next) =>
                          displayRepo.updateSettings(clinicId, next),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayOrderForm extends StatefulWidget {
  const _DisplayOrderForm({
    required this.clinicId,
    required this.locations,
    required this.display,
    required this.onSave,
  });

  final String clinicId;
  final List<ClinicLocation> locations;
  final LocationDisplaySettings display;
  final void Function(LocationDisplaySettings) onSave;

  @override
  State<_DisplayOrderForm> createState() => _DisplayOrderFormState();
}

class _DisplayOrderFormState extends State<_DisplayOrderForm> {
  late List<String> _order;
  String? _defaultId;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.display.locationIds);
    _defaultId = widget.display.defaultLocationId;
    _syncOrderFromLocations();
  }

  @override
  void didUpdateWidget(_DisplayOrderForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOrderFromLocations();
  }

  void _syncOrderFromLocations() {
    final ids = widget.locations.map((e) => e.id).toSet();
    final ordered = _order.where(ids.contains).toList();
    for (final loc in widget.locations) {
      if (!ordered.contains(loc.id)) ordered.add(loc.id);
    }
    if (ordered.length != _order.length ||
        ordered.toSet().length != widget.locations.length) {
      setState(() => _order = ordered);
    }
    if (_defaultId != null && !ids.contains(_defaultId)) {
      setState(() => _defaultId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = widget.locations;
    final byId = {for (final l in locations) l.id: l};
    final ordered = <ClinicLocation>[];
    for (final id in _order) {
      final l = byId[id];
      if (l != null) ordered.add(l);
    }
    for (final l in locations) {
      if (!ordered.any((o) => o.id == l.id)) ordered.add(l);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _defaultId,
          decoration: const InputDecoration(
            labelText: 'Default location',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            ...ordered.map((l) =>
                DropdownMenuItem(value: l.id, child: Text(l.name))),
          ],
          onChanged: (v) => setState(() => _defaultId = v),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        ...ordered.map((l) => ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(l.name),
            )),
        const SizedBox(height: AppSpacing.sectionGap),
        FilledButton(
          onPressed: () {
            widget.onSave(LocationDisplaySettings(
              locationIds: _order,
              defaultLocationId: _defaultId,
            ));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Display order saved')),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
