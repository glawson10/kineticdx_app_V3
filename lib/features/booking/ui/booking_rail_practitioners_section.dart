// lib/features/booking/ui/booking_rail_practitioners_section.dart
//
// F1: Practitioner checklist in the left rail — show/hide columns,
// Select all / Deselect all, drag-to-reorder. Persists via PractitionerVisibilityPrefs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/staff_repository.dart';
import '../../../ui/design_tokens.dart';
import '../data/bookable_clinician_resolver.dart';
import '../data/booking_calendar_prefs.dart';

/// Callback with updated prefs and the effective visible/ordered lists (merged with staff).
typedef PractitionerPrefsCallback = void Function(
  PractitionerVisibilityPrefs prefs,
  List<String> visibleIds,
  List<String> orderIds,
);

class BookingRailPractitionersSection extends StatefulWidget {
  final String clinicId;
  final PractitionerVisibilityPrefs initialPrefs;
  final PractitionerPrefsCallback onPrefsChanged;
  /// When true, list uses shrinkWrap so it can sit inside a scrollable parent.
  final bool shrinkWrap;

  const BookingRailPractitionersSection({
    super.key,
    required this.clinicId,
    required this.initialPrefs,
    required this.onPrefsChanged,
    this.shrinkWrap = false,
  });

  @override
  State<BookingRailPractitionersSection> createState() =>
      _BookingRailPractitionersSectionState();
}

class _BookingRailPractitionersSectionState
    extends State<BookingRailPractitionersSection> {
  late PractitionerVisibilityPrefs _prefs;
  List<String>? _lastEmittedVisible;
  List<String>? _lastEmittedOrder;

  Stream<ResolvedClinicianList>? _cachedResolvedStream;
  String? _cachedResolvedStreamClinicId;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
  }

  @override
  void didUpdateWidget(covariant BookingRailPractitionersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPrefs.visiblePractitionerIds !=
            widget.initialPrefs.visiblePractitionerIds ||
        oldWidget.initialPrefs.orderPractitionerIds !=
            widget.initialPrefs.orderPractitionerIds) {
      _prefs = widget.initialPrefs;
    }
  }

  void _emitEffective(
    List<ResolvedClinician> staff,
    PractitionerVisibilityPrefs prefs,
  ) {
    final orderIds = prefs.orderPractitionerIds;
    final visibleSet = prefs.visiblePractitionerIds.isEmpty
        ? null
        : prefs.visiblePractitionerIds.toSet();
    final idToClinic = {for (final c in staff) c.uid: c};
    final ordered = <String>[];
    for (final id in orderIds) {
      if (idToClinic.containsKey(id)) ordered.add(id);
    }
    for (final c in staff) {
      if (!ordered.contains(c.uid)) ordered.add(c.uid);
    }
    var visible = visibleSet == null
        ? ordered
        : ordered.where((id) => visibleSet.contains(id)).toList();
    if (visible.isEmpty && ordered.isNotEmpty) {
      visible = ordered;
    }
    if (_listEquals(visible, _lastEmittedVisible) &&
        _listEquals(ordered, _lastEmittedOrder)) return;
    _lastEmittedVisible = visible;
    _lastEmittedOrder = ordered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPrefsChanged(prefs, visible, ordered);
    });
  }

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (a == b) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }

  Future<void> _saveAndEmit(PractitionerVisibilityPrefs prefs) async {
    await savePractitionerVisibilityPrefs(prefs);
    if (!mounted) return;
    setState(() => _prefs = prefs);
    final staffRepo = context.read<StaffRepository>();
    final resolved = await watchBookableClinicians(
      staffRepo: staffRepo,
      clinicId: widget.clinicId,
    ).first;
    _emitEffective(resolved.all, prefs);
  }

  void _selectAll(List<String> orderedIds) {
    _saveAndEmit(PractitionerVisibilityPrefs(
      visiblePractitionerIds: List.from(orderedIds),
      orderPractitionerIds: _prefs.orderPractitionerIds.isNotEmpty
          ? _prefs.orderPractitionerIds
          : orderedIds,
    ));
  }

  void _deselectAll() {
    _saveAndEmit(PractitionerVisibilityPrefs(
      visiblePractitionerIds: const [],
      orderPractitionerIds: _prefs.orderPractitionerIds,
    ));
  }

  void _toggleOne(String id, bool currentlyVisible, List<String> orderIds) {
    final cur = _prefs.visiblePractitionerIds.toSet();
    final next = currentlyVisible
        ? cur.where((e) => e != id).toList()
        : [...cur, id];
    _saveAndEmit(PractitionerVisibilityPrefs(
      visiblePractitionerIds: next,
      orderPractitionerIds: orderIds,
    ));
  }

  void _reorder(int oldIndex, int newIndex, List<String> orderIds) {
    if (oldIndex < newIndex) newIndex--;
    final next = List<String>.from(orderIds);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    _saveAndEmit(PractitionerVisibilityPrefs(
      visiblePractitionerIds: _prefs.visiblePractitionerIds,
      orderPractitionerIds: next,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffRepo = context.read<StaffRepository>();

    final Stream<ResolvedClinicianList> resolvedStream;
    if (_cachedResolvedStreamClinicId == widget.clinicId &&
        _cachedResolvedStream != null) {
      resolvedStream = _cachedResolvedStream!;
    } else {
      resolvedStream = watchBookableClinicians(
        staffRepo: staffRepo,
        clinicId: widget.clinicId,
      );
      _cachedResolvedStream = resolvedStream;
      _cachedResolvedStreamClinicId = widget.clinicId;
    }

    return StreamBuilder<ResolvedClinicianList>(
      stream: resolvedStream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[BookingRailPractitionersSection] stream error: ${snap.error}');
        }
        final allClinicians = snap.data?.all ?? const [];
        final orderIds = _prefs.orderPractitionerIds;
        final visibleSet = _prefs.visiblePractitionerIds.isEmpty
            ? null
            : _prefs.visiblePractitionerIds.toSet();
        final idToClinician = {for (final c in allClinicians) c.uid: c};
        final orderedIds = <String>[];
        for (final id in orderIds) {
          if (idToClinician.containsKey(id)) orderedIds.add(id);
        }
        for (final c in allClinicians) {
          if (!orderedIds.contains(c.uid)) orderedIds.add(c.uid);
        }
        final orderedClinicians =
            orderedIds.map((id) => idToClinician[id]!).toList();

        if (orderedClinicians.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No practitioners',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        _emitEffective(allClinicians, _prefs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Practitioners',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => _selectAll(orderedIds),
                    child: const Text('Select all'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => _deselectAll(),
                    child: const Text('Deselect all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            widget.shrinkWrap
                ? ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orderedClinicians.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorder(oldIndex, newIndex, orderedIds),
                    itemBuilder: (context, index) {
                      final c = orderedClinicians[index];
                      final visible = visibleSet == null || visibleSet.contains(c.uid);
                      return Card(
                        key: ValueKey(c.uid),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppSurfaces.cardBorder),
                        ),
                        elevation: 0,
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_handle,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            c.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          trailing: Checkbox(
                            value: visible,
                            onChanged: (v) => _toggleOne(
                              c.uid,
                              visible,
                              orderedIds,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Flexible(
                    child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: orderedClinicians.length,
                onReorder: (oldIndex, newIndex) =>
                    _reorder(oldIndex, newIndex, orderedIds),
                itemBuilder: (context, index) {
                  final c = orderedClinicians[index];
                  final visible = visibleSet == null || visibleSet.contains(c.uid);
                  return Card(
                    key: ValueKey(c.uid),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppSurfaces.cardBorder),
                    ),
                    elevation: 0,
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        c.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: Checkbox(
                        value: visible,
                        onChanged: (v) => _toggleOne(
                          c.uid,
                          visible,
                          orderedIds,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
