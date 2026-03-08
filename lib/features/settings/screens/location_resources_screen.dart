// lib/features/settings/screens/location_resources_screen.dart
// Locations → Resources (rooms). Placeholder for phase 1.

import 'package:flutter/material.dart';

class LocationResourcesScreen extends StatelessWidget {
  const LocationResourcesScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.meeting_room_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Location resources',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Manage rooms and resources per location. Coming soon.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
