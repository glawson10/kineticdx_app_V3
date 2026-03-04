import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import './patient_details_screen.dart';

// IMPORTANT: your functions are deployed in europe-west3 (REGION in index.ts)
final FirebaseFunctions _functions =
    FirebaseFunctions.instanceFor(region: 'europe-west3');

/// Uses one-time get() + refresh instead of snapshots() to avoid Firestore web
/// listener teardown bugs (LateInitializationError: onSnapshotUnsubscribe, INTERNAL ASSERTION FAILED).
class PatientFinderScreen extends StatefulWidget {
  const PatientFinderScreen({super.key});

  @override
  State<PatientFinderScreen> createState() => _PatientFinderScreenState();
}

class _PatientFinderScreenState extends State<PatientFinderScreen> {
  final _searchCtl = TextEditingController();
  DateTime? _dob;

  // ✅ Hide merged/archived by default (so merged "disappears")
  bool _showArchivedMerged = false;

  bool _loading = false;
  Object? _error;
  List<_PatientLite>? _patients;
  String? _loadedClinicId;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients(String clinicId) async {
    if (_loading && _loadedClinicId == clinicId) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadedClinicId = clinicId;
    });

    try {
      final patientsCol = FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('patients');

      final snapshot = await patientsCol
          .get()
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('Patient list took too long to load.');
      });

      if (!mounted) return;
      final patients = <_PatientLite>[];
      for (final d in snapshot.docs) {
        try {
          patients.add(_PatientLite.fromDoc(d));
        } catch (_) {}
      }
      if (!mounted) return;
      // Only apply if we're still loading for this clinic (user may have switched)
      setState(() {
        if (_loadedClinicId != clinicId) return;
        _loading = false;
        _error = null;
        _patients = patients;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_loadedClinicId != clinicId) return;
        _loading = false;
        _error = e;
        _patients = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasClinic) {
      return Scaffold(
        appBar: AppBar(title: const SizedBox.shrink()),
        body: const Center(
          child: Text('No clinic selected. Select a clinic to view patients.'),
        ),
      );
    }
    final clinicId = clinicCtx.clinicId;

    // When clinic changes or we have no data, schedule a load (post-frame to avoid setState during build)
    final needLoad = _patients == null && _error == null && !_loading;
    final clinicChanged = _loadedClinicId != null && _loadedClinicId != clinicId;
    if (clinicChanged && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _patients = null;
          _error = null;
          _loadedClinicId = null;
        });
        _loadPatients(clinicId);
      });
    } else if (needLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPatients(clinicId));
    }

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(), // Title shown in shell (top-left) only
        actions: [
          Row(
            children: [
              const Text('Show archived'),
              Switch(
                value: _showArchivedMerged,
                onChanged: (v) => setState(() => _showArchivedMerged = v),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchCtl,
              decoration: const InputDecoration(
                labelText: 'Search name / email / phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cake_outlined),
                    label: Text(
                      _dob == null
                          ? 'Filter DOB (optional)'
                          : 'DOB: ${_dob!.day}/${_dob!.month}/${_dob!.year}',
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final init = DateTime(now.year - 30, now.month, now.day);
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dob ?? init,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(now.year, now.month, now.day),
                      );
                      if (d != null) setState(() => _dob = d);
                    },
                  ),
                ),
                if (_dob != null)
                  IconButton(
                    tooltip: 'Clear DOB',
                    onPressed: () => setState(() => _dob = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(clinicId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            PatientDetailsScreen.routeCreate(clinicId: clinicId),
          );
        },
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Widget _buildBody(String clinicId) {
    if (_loading && _patients == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _patients == null) {
      final e = _error!;
      final errStr = e.toString();
      final isPermissionDenied = e is FirebaseException &&
          (e.code == 'permission-denied' ||
              (e.message ?? '').toLowerCase().contains('permission'));
      final isTimeout = e is TimeoutException;
      final isFirestoreInternal = errStr.contains('INTERNAL ASSERTION FAILED') ||
          errStr.contains('Unexpected state');

      final String message;
      final String? subMessage;
      if (isPermissionDenied) {
        message = 'You don\'t have permission to view patients. '
            'Ask an admin to grant you "Patients read" (patients.read) for this clinic.';
        subMessage = null;
      } else if (isTimeout) {
        message = 'Patient list took too long to load. Check your connection and try again.';
        subMessage = null;
      } else if (isFirestoreInternal) {
        message = 'Firestore ran into an error (often after another action failed).';
        subMessage = 'Refresh the page (F5 or reload) and try again. Retry below may work.';
      } else {
        message = 'Failed to load patients.';
        subMessage = errStr.length > 200 ? '${errStr.substring(0, 200)}…' : errStr;
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPermissionDenied
                    ? Icons.lock_outline
                    : Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              if (subMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  subMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadPatients(clinicId),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final rawPatients = _patients ?? const [];
    final search = _searchCtl.text.trim().toLowerCase();
    final filteredPatients = rawPatients.where((p) {
      if (!_showArchivedMerged) {
        if (p.isMerged) return false;
        if (p.isArchived) return false;
        if (p.isDeleted) return false;
      }
      final matchesSearch =
          search.isEmpty ? true : p.searchBlob.contains(search);
      final matchesDob = (_dob == null || p.dob == null)
          ? true
          : (p.dob!.year == _dob!.year &&
              p.dob!.month == _dob!.month &&
              p.dob!.day == _dob!.day);
      return matchesSearch && matchesDob;
    }).toList()
      ..sort(
        (a, b) => a.lastName
            .toLowerCase()
            .compareTo(b.lastName.toLowerCase()),
      );

    if (filteredPatients.isEmpty) {
      return const Center(child: Text('No matching patients'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadPatients(clinicId),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filteredPatients.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = filteredPatients[i];
          final statusBits = <String>[
            if (p.isMerged) 'Merged',
            if (p.isArchived) 'Archived',
            if (p.isDeleted) 'Deleted',
          ];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(p.displayName),
            subtitle: Text(
              [
                _subtitle(p),
                if (statusBits.isNotEmpty) statusBits.join(' · '),
              ].where((x) => x.trim().isNotEmpty).join('\n'),
            ),
            isThreeLine: statusBits.isNotEmpty,
            onTap: () {
              Navigator.of(context).push(
                PatientDetailsScreen.routeEdit(
                  clinicId: clinicId,
                  patientId: p.id,
                ),
              );
            },
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) async {
                if (value == 'merge') {
                  await _startMergeFlow(
                    clinicId: clinicId,
                    source: p,
                    allPatients: rawPatients,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'merge',
                  child: Row(
                    children: [
                      Icon(Icons.call_merge, size: 18),
                      SizedBox(width: 10),
                      Text('Merge…'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _subtitle(_PatientLite p) {
    final parts = <String>[];
    if (p.dob != null) {
      parts.add('DOB: ${p.dob!.day}/${p.dob!.month}/${p.dob!.year}');
    }
    if (p.email.isNotEmpty) parts.add(p.email);
    if (p.email.isEmpty && p.phone.isNotEmpty) parts.add(p.phone);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _startMergeFlow({
    required String clinicId,
    required _PatientLite source,
    required List<_PatientLite> allPatients,
  }) async {
    // ✅ Candidates should respect “show archived” toggle
    final candidates = allPatients.where((p) => p.id != source.id).where((p) {
      if (_showArchivedMerged) return true;
      if (p.isMerged) return false;
      if (p.isArchived) return false;
      if (p.isDeleted) return false;
      return true;
    }).toList();

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final target = await showDialog<_PatientLite>(
      context: context,
      builder: (_) => _MergePickTargetDialog(
        source: source,
        candidates: candidates,
      ),
    );

    if (target == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm merge'),
            content: Text(
              'You are about to merge:\n\n'
              'Source (will be archived):\n'
              '• ${source.displayName}\n\n'
              'Into target (kept as original):\n'
              '• ${target.displayName}\n\n'
              'Only EMPTY fields on the target will be filled from the source.\n'
              'Appointments will be re-linked to the target.\n',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Merge'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    // Loading dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Merging…'),
          ],
        ),
      ),
    );

    try {
      final callable = _functions.httpsCallable('mergePatientsFn');
      final res = await callable.call(<String, dynamic>{
        'clinicId': clinicId,
        'sourcePatientId': source.id,
        'targetPatientId': target.id,
      });

      if (!mounted) return;
      navigator.pop(); // close loading

      final data = (res.data as Map?) ?? {};
      final updated = data['updatedRefs']?.toString() ?? '0';

      messenger.showSnackBar(
        SnackBar(content: Text('Merged successfully. Updated refs: $updated')),
      );

      await _loadPatients(clinicId);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message ?? e.details ?? ''}')),
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Merge failed: $e')),
      );
    }
  }
}

class _MergePickTargetDialog extends StatefulWidget {
  const _MergePickTargetDialog({
    required this.source,
    required this.candidates,
  });

  final _PatientLite source;
  final List<_PatientLite> candidates;

  @override
  State<_MergePickTargetDialog> createState() => _MergePickTargetDialogState();
}

class _MergePickTargetDialogState extends State<_MergePickTargetDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _search.text.trim().toLowerCase();

    final likely = widget.candidates.where((p) {
      final emailMatch = widget.source.email.isNotEmpty &&
          p.email.isNotEmpty &&
          p.email.toLowerCase() == widget.source.email.toLowerCase();
      final phoneMatch = widget.source.phone.isNotEmpty &&
          p.phone.isNotEmpty &&
          p.phone == widget.source.phone;

      final dobMatch = (widget.source.dob != null && p.dob != null)
          ? (widget.source.dob!.year == p.dob!.year &&
              widget.source.dob!.month == p.dob!.month &&
              widget.source.dob!.day == p.dob!.day)
          : false;

      return emailMatch || phoneMatch || dobMatch;
    }).toList();

    final others = widget.candidates
        .where((p) => !likely.any((x) => x.id == p.id))
        .toList();

    List<_PatientLite> filtered(List<_PatientLite> list) {
      if (s.isEmpty) return list;
      return list.where((p) => p.searchBlob.contains(s)).toList();
    }

    final likelyFiltered = filtered(likely);
    final othersFiltered = filtered(others);

    return AlertDialog(
      title: const Text('Merge into which patient?'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Source (will be archived): ${widget.source.displayName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search target patient',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (likelyFiltered.isNotEmpty) ...[
                    _sectionHeader(context, 'Likely matches'),
                    ...likelyFiltered.map((p) => _pickTile(context, p)),
                    const Divider(height: 22),
                  ],
                  _sectionHeader(context, 'All patients'),
                  ...othersFiltered.map((p) => _pickTile(context, p)),
                  if (likelyFiltered.isEmpty && othersFiltered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: Text('No matching patients')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _pickTile(BuildContext context, _PatientLite p) {
    final subtitleParts = <String>[];
    if (p.dob != null) {
      subtitleParts.add('DOB ${p.dob!.day}/${p.dob!.month}/${p.dob!.year}');
    }
    if (p.email.isNotEmpty) subtitleParts.add(p.email);
    if (p.email.isEmpty && p.phone.isNotEmpty) subtitleParts.add(p.phone);

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(p.displayName),
      subtitle: Text(subtitleParts.isEmpty ? '—' : subtitleParts.join(' · ')),
      onTap: () => Navigator.pop(context, p),
    );
  }
}

class _PatientLite {
  final String id;
  final String firstName;
  final String lastName;
  final DateTime? dob;
  final String email;
  final String phone;

  // ✅ used to hide merged/archived/deleted
  final bool isArchived;
  final bool isMerged;
  final bool isDeleted;

  _PatientLite({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.email,
    required this.phone,
    required this.isArchived,
    required this.isMerged,
    required this.isDeleted,
  });

  String get displayName {
    final n = ('$firstName $lastName').trim();
    return n.isEmpty ? 'Unnamed patient' : n;
  }

  String get searchBlob =>
      [firstName, lastName, email, phone].join(' ').toLowerCase();

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory _PatientLite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    // Dual-read: new nested shape first, fallback to legacy flat fields
    final identity = (data['identity'] is Map<String, dynamic>)
        ? (data['identity'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final contact = (data['contact'] is Map<String, dynamic>)
        ? (data['contact'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final firstName =
        (identity['firstName'] ?? data['firstName'] ?? '').toString();
    final lastName =
        (identity['lastName'] ?? data['lastName'] ?? '').toString();

    final dobValue = identity.containsKey('dateOfBirth')
        ? identity['dateOfBirth']
        : (data.containsKey('dob') ? data['dob'] : data['dateOfBirth']);

    final email = (contact['email'] ?? data['email'] ?? '').toString();
    final phone = (contact['phone'] ?? data['phone'] ?? '').toString();

    // ✅ status detection
    final status = (data['status'] is Map<String, dynamic>)
        ? (data['status'] as Map<String, dynamic>)
        : const <String, dynamic>{};

    final isArchived = status['archived'] == true || data['archived'] == true;
    final isMerged =
        (data['mergedIntoPatientId'] ?? '').toString().trim().isNotEmpty;
    final isDeleted = data['deletedAt'] != null;

    return _PatientLite(
      id: doc.id,
      firstName: firstName,
      lastName: lastName,
      dob: _toDate(dobValue),
      email: email,
      phone: phone,
      isArchived: isArchived,
      isMerged: isMerged,
      isDeleted: isDeleted,
    );
  }
}
