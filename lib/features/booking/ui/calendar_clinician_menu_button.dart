// lib/features/booking/ui/calendar_clinician_menu_button.dart
//
// Clinicians dropdown: All clinicians, My calendar only, per-clinician, Clear filters

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/staff_repository.dart';
import '../data/bookable_clinician_resolver.dart';

String _label(String? value, List<ResolvedClinician> practitioners) {
  if (value == null) return 'All clinicians';
  for (final c in practitioners) {
    if (c.uid == value) return c.displayName.isEmpty ? 'Clinician' : c.displayName;
  }
  return 'Clinician';
}

class CalendarClinicianMenuButton extends StatelessWidget {
  const CalendarClinicianMenuButton({
    super.key,
    required this.clinicId,
    required this.value,
    required this.onChanged,
    this.visiblePractitionerIds = const [],
    this.orderPractitionerIds = const [],
  });

  final String clinicId;
  /// Selected practitioner id; null = all
  final String? value;
  final ValueChanged<String?> onChanged;
  final List<String> visiblePractitionerIds;
  final List<String> orderPractitionerIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffRepo = context.read<StaffRepository>();
    final stream = watchBookableClinicians(
      staffRepo: staffRepo,
      clinicId: clinicId,
    );

    return StreamBuilder<ResolvedClinicianList>(
      stream: stream,
      builder: (context, snap) {
        var practitioners = snap.data?.all ?? const [];
        if (visiblePractitionerIds.isNotEmpty) {
          final set = visiblePractitionerIds.toSet();
          final filtered = practitioners.where((c) => set.contains(c.uid)).toList();
          if (filtered.isNotEmpty) practitioners = filtered;
        }
        if (orderPractitionerIds.isNotEmpty) {
          final order = {for (var i = 0; i < orderPractitionerIds.length; i++) orderPractitionerIds[i]: i};
          practitioners = List.of(practitioners)
            ..sort((a, b) => (order[a.uid] ?? 9999).compareTo(order[b.uid] ?? 9999));
        }

        final currentUid = FirebaseAuth.instance.currentUser?.uid;

        return PopupMenuButton<String?>(
          tooltip: 'Clinicians',
          onSelected: onChanged,
          itemBuilder: (context) => [
            const PopupMenuItem<String?>(
              value: null,
              child: ListTile(
                leading: Icon(Icons.people_outline, size: 22),
                title: Text('All clinicians'),
              ),
            ),
            if (currentUid != null)
              PopupMenuItem<String?>(
                value: currentUid,
                child: ListTile(
                  leading: Icon(
                    Icons.person_outline,
                    size: 22,
                    color: value == currentUid ? theme.colorScheme.primary : null,
                  ),
                  title: const Text('My calendar only'),
                ),
              ),
            if (practitioners.isNotEmpty) const PopupMenuDivider(),
            ...practitioners.map((c) => PopupMenuItem<String?>(
              value: c.uid,
              child: ListTile(
                leading: Icon(
                  value == c.uid ? Icons.check_circle : Icons.person_outline,
                  size: 22,
                  color: value == c.uid ? theme.colorScheme.primary : null,
                ),
                title: Text(c.displayName.isEmpty ? '(No name)' : c.displayName),
              ),
            )),
            const PopupMenuDivider(),
            const PopupMenuItem<String?>(
              value: null,
              child: ListTile(
                leading: Icon(Icons.clear_all, size: 22),
                title: Text('Clear filters'),
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  _label(value, practitioners),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}
