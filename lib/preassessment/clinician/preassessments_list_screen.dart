// lib/preassessment/clinician/preassessments_list_screen.dart
//
// ✅ Updated in full:
// - 2 tabs:
//    1) Focused (region flows) with Status + Region + Triage filters
//    2) General Visit (generalVisit.v1) with Status filter only + fast preview via summaryPreview/keyAnswers
// - ✅ Uses flowCategory ("region" | "general") for clean server-side queries
//   (requires submitIntakeSessionFn to write flowCategory)
// - Speed-dial FAB expands into two actions
// - Keeps clinician launch pattern: IntakeStartScreen with clinicIdOverride + dev bypass
//
// IMPORTANT:
// - Your submitIntakeSession now writes:
//    flowCategory: "region" | "general"
//    flowId: "..."
// - IntakeStartScreen supports flowIdOverride: 'generalVisit'

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:kineticdx_app_v3/app/clinic_context.dart';
import 'package:kineticdx_app_v3/preassessment/clinician/preassessment_detail_screen.dart';
import 'package:kineticdx_app_v3/preassessment/screens/intake_start_screen.dart';

class PreAssessmentsListScreen extends StatefulWidget {
  const PreAssessmentsListScreen({super.key});

  @override
  State<PreAssessmentsListScreen> createState() => _PreAssessmentsListScreenState();
}

class _PreAssessmentsListScreenState extends State<PreAssessmentsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _fabOpen = false;

  // Focused tab filters
  String _statusFilter = 'submitted'; // submitted|draft|locked|all
  String _regionFilter = 'all'; // ankle/knee/... or all
  String _triageFilter = 'all'; // green/amber/red/all

  // General tab filters
  String _generalStatusFilter = 'submitted'; // submitted|draft|locked|all

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_fabOpen) setState(() => _fabOpen = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _startNewFocusedPreassessment(BuildContext context, String clinicId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IntakeStartScreen(
          clinicIdOverride: clinicId,
          tokenOverride: 'clinician',
          devBypassOverride: true,
          // no flowIdOverride => normal region routing
        ),
      ),
    );
  }

  void _startNewGeneralVisit(BuildContext context, String clinicId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IntakeStartScreen(
          clinicIdOverride: clinicId,
          tokenOverride: 'clinician',
          devBypassOverride: true,
          flowIdOverride: 'generalVisit',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    final clinicId = clinicCtx.clinicId;

    if (clinicId.trim().isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected.')),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_fabOpen) setState(() => _fabOpen = false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pre-Assessments'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Focused'),
              Tab(text: 'General visit'),
            ],
          ),
        ),

        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: _SpeedDialFab(
          isOpen: _fabOpen,
          onToggle: () => setState(() => _fabOpen = !_fabOpen),
          onNewFocused: () {
            setState(() => _fabOpen = false);
            _startNewFocusedPreassessment(context, clinicId);
          },
          onNewGeneral: () {
            setState(() => _fabOpen = false);
            _startNewGeneralVisit(context, clinicId);
          },
        ),

        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 0: Focused
            Column(
              children: [
                _FocusedFiltersRow(
                  status: _statusFilter,
                  region: _regionFilter,
                  triage: _triageFilter,
                  onChanged: (status, region, triage) {
                    setState(() {
                      _statusFilter = status;
                      _regionFilter = region;
                      _triageFilter = triage;
                    });
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: _FocusedIntakeSessionsList(
                    clinicId: clinicId,
                    status: _statusFilter,
                    region: _regionFilter,
                    triage: _triageFilter,
                  ),
                ),
              ],
            ),

            // Tab 1: General visit
            Column(
              children: [
                _GeneralFiltersRow(
                  status: _generalStatusFilter,
                  onChanged: (status) {
                    setState(() => _generalStatusFilter = status);
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: _GeneralVisitIntakeSessionsList(
                    clinicId: clinicId,
                    status: _generalStatusFilter,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------------
/// Speed dial FAB
/// ----------------------------
class _SpeedDialFab extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  final VoidCallback onNewFocused;
  final VoidCallback onNewGeneral;

  const _SpeedDialFab({
    required this.isOpen,
    required this.onToggle,
    required this.onNewFocused,
    required this.onNewGeneral,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          if (isOpen) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 124),
              child: _MiniFab(
                heroTag: 'fab_new_focused',
                icon: Icons.note_add_outlined,
                label: 'New focused',
                onPressed: onNewFocused,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: _MiniFab(
                heroTag: 'fab_new_general',
                icon: Icons.description_outlined,
                label: 'New general visit',
                onPressed: onNewGeneral,
              ),
            ),
          ],
          FloatingActionButton(
            heroTag: 'fab_speed_dial_root',
            onPressed: onToggle,
            child: Icon(isOpen ? Icons.close : Icons.add),
          ),
        ],
      ),
    );
  }
}

class _MiniFab extends StatelessWidget {
  final String heroTag;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MiniFab({
    required this.heroTag,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(label),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.small(
            heroTag: heroTag,
            onPressed: onPressed,
            child: Icon(icon),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------
/// Focused filters
/// ----------------------------
class _FocusedFiltersRow extends StatelessWidget {
  final String status;
  final String region;
  final String triage;
  final void Function(String status, String region, String triage) onChanged;

  const _FocusedFiltersRow({
    required this.status,
    required this.region,
    required this.triage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          _Drop(
            label: 'Status',
            value: status,
            items: const [
              ('submitted', 'Submitted'),
              ('draft', 'Draft'),
              ('locked', 'Locked'),
              ('all', 'All'),
            ],
            onChanged: (v) => onChanged(v, region, triage),
          ),
          _Drop(
            label: 'Region',
            value: region,
            items: const [
              ('all', 'All'),
              ('ankle', 'Ankle'),
              ('knee', 'Knee'),
              ('hip', 'Hip'),
              ('lumbar', 'Lumbar'),
              ('cervical', 'Cervical'),
              ('thoracic', 'Thoracic'),
              ('shoulder', 'Shoulder'),
              ('elbow', 'Elbow'),
              ('wrist', 'Wrist'),
            ],
            onChanged: (v) => onChanged(status, v, triage),
          ),
          _Drop(
            label: 'Triage',
            value: triage,
            items: const [
              ('all', 'All'),
              ('green', 'Green'),
              ('amber', 'Amber'),
              ('red', 'Red'),
            ],
            onChanged: (v) => onChanged(status, region, v),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------
/// General tab filters
/// ----------------------------
class _GeneralFiltersRow extends StatelessWidget {
  final String status;
  final void Function(String status) onChanged;

  const _GeneralFiltersRow({
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          _Drop(
            label: 'Status',
            value: status,
            items: const [
              ('submitted', 'Submitted'),
              ('draft', 'Draft'),
              ('locked', 'Locked'),
              ('all', 'All'),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Drop extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  const _Drop({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            items: items.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

/// ----------------------------
/// Focused list (server-side query using flowCategory=region)
/// ----------------------------
class _FocusedIntakeSessionsList extends StatelessWidget {
  final String clinicId;
  final String status;
  final String region;
  final String triage;

  const _FocusedIntakeSessionsList({
    required this.clinicId,
    required this.status,
    required this.region,
    required this.triage,
  });

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('intakeSessions')
        .where('flowCategory', isEqualTo: 'region');

    // Status + ordering
    if (status != 'all') {
      q = q.where('status', isEqualTo: status);
      if (status == 'submitted' || status == 'locked') {
        q = q.orderBy('submittedAt', descending: true);
      } else {
        q = q.orderBy('createdAt', descending: true);
      }
    } else {
      q = q.orderBy('submittedAt', descending: true);
    }

    // Region filter:
    // Firestore can't OR-match 'ankle' and 'region.ankle' easily, so we:
    // - if region != all: we DON'T add where('regionSelection.bodyArea'==...) because it would miss prefixed variants
    // - instead filter client-side for those variants after fetch.
    //
    // If you want strict server-side, normalize stored values to always be 'region.X' and query that.
    if (triage != 'all') {
      q = q.where('triage.status', isEqualTo: triage);
    }

    return q.limit(200);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          final err = snap.error;
          if (err is FirebaseException && err.code == 'permission-denied') {
            return _PermissionDeniedState(
              clinicId: clinicId,
              raw: err.message ?? err.toString(),
            );
          }
          return _ErrorState(error: err.toString());
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? const [];

        final filtered = docs.where((d) {
          final data = d.data();

          if (status != 'all') {
            final s = _readString(data, ['status']).trim();
            if (s != status) return false;
          }

          if (triage != 'all') {
            final t = _readTriageStatus(data);
            if (t != triage) return false;
          }

          if (region != 'all') {
            final bodyArea = _readString(data, ['regionSelection', 'bodyArea']).trim();
            if (bodyArea != region && bodyArea != 'region.$region') return false;
          }

          return true;
        }).toList();

        if (filtered.isEmpty) return const _EmptyState();

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final doc = filtered[i];
            final data = doc.data();

            final patientName = _patientName(data);

            final bodyAreaRaw = _readString(data, ['regionSelection', 'bodyArea']);
            final bodyArea = bodyAreaRaw.startsWith('region.')
                ? bodyAreaRaw.replaceFirst('region.', '')
                : bodyAreaRaw;

            final triageStatus = _readTriageStatus(data);
            final submittedAt = _readTimestampText(data, ['submittedAt']);
            final flowId = _readFlowId(data);

            return ListTile(
              title: Text(patientName.isEmpty ? '(Unknown patient)' : patientName),
              subtitle: Text(
                [
                  if (bodyArea.isNotEmpty) 'Region: $bodyArea',
                  if (flowId.isNotEmpty) 'Flow: $flowId',
                  if (triageStatus.isNotEmpty) 'Triage: ${triageStatus.toUpperCase()}',
                  if (submittedAt.isNotEmpty) submittedAt,
                ].join(' • '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreassessmentDetailScreen(
                      clinicId: clinicId,
                      intakeSessionId: doc.id,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// ----------------------------
/// General Visit list (server-side query using flowCategory=general)
/// ----------------------------
class _GeneralVisitIntakeSessionsList extends StatelessWidget {
  final String clinicId;
  final String status;

  const _GeneralVisitIntakeSessionsList({
    required this.clinicId,
    required this.status,
  });

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('intakeSessions')
        .where('flowCategory', isEqualTo: 'general')
        .where('flowId', isEqualTo: 'generalVisit');

    if (status != 'all') {
      q = q.where('status', isEqualTo: status);
      if (status == 'submitted' || status == 'locked') {
        q = q.orderBy('submittedAt', descending: true);
      } else {
        q = q.orderBy('createdAt', descending: true);
      }
    } else {
      q = q.orderBy('submittedAt', descending: true);
    }

    return q.limit(200);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          final err = snap.error;
          if (err is FirebaseException && err.code == 'permission-denied') {
            return _PermissionDeniedState(
              clinicId: clinicId,
              raw: err.message ?? err.toString(),
            );
          }
          return _ErrorState(error: err.toString());
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const _EmptyStateGeneral();

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();

            final patientName = _patientName(data);
            final submittedAt = _readTimestampText(data, ['submittedAt']);

            final preview = (data['summaryPreview'] is Map<String, dynamic>)
                ? (data['summaryPreview'] as Map<String, dynamic>)
                : <String, dynamic>{};

            final concernClarity = _readString(preview, ['concernClarityLabel']);
            final areas = _readString(preview, ['areasLabel']);
            final duration = _readString(preview, ['durationLabel']);
            final impact = _readString(preview, ['impactLabel']);

            final keyAnswers = (data['keyAnswers'] is Map<String, dynamic>)
                ? (data['keyAnswers'] as Map<String, dynamic>)
                : <String, dynamic>{};

            final reason =
                (keyAnswers['generalVisit.goals.reasonForVisit'] ?? '').toString().trim();
            final reasonLine = reason.isEmpty ? '' : '“${_truncate(reason, 90)}”';

            // "List card": a richer preview than a basic subtitle line
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreassessmentDetailScreen(
                      clinicId: clinicId,
                      intakeSessionId: doc.id,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                patientName.isEmpty ? '(Unknown patient)' : patientName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (concernClarity.isNotEmpty)
                          Text(concernClarity,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline)),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (areas.isNotEmpty) areas,
                            if (duration.isNotEmpty) duration,
                            if (impact.isNotEmpty) impact,
                          ].where((s) => s.trim().isNotEmpty).join(' • '),
                        ),
                        if (reasonLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(reasonLine),
                        ],
                        if (submittedAt.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            submittedAt,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _truncate(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';
}

/// ----------------------------
/// Shared helpers
/// ----------------------------
String _readTriageStatus(Map<String, dynamic> data) {
  final s1 = _readString(data, ['summary', 'triage', 'status']);
  if (s1.trim().isNotEmpty) return s1.trim().toLowerCase();
  final s2 = _readString(data, ['triage', 'status']);
  return s2.trim().toLowerCase();
}

String _readFlowId(Map<String, dynamic> data) {
  final a = _readString(data, ['flow', 'flowId']);
  if (a.isNotEmpty) return a;
  return _readString(data, ['flowId']);
}

String _patientName(Map<String, dynamic> data) {
  final first = _readString(data, ['patientDetails', 'firstName']);
  final last = _readString(data, ['patientDetails', 'lastName']);
  return ('$first $last').trim();
}

String _readString(Map<String, dynamic> data, List<String> path) {
  dynamic cur = data;
  for (final p in path) {
    if (cur is Map<String, dynamic> && cur.containsKey(p)) {
      cur = cur[p];
    } else {
      return '';
    }
  }
  return cur is String ? cur : (cur?.toString() ?? '');
}

String _readTimestampText(Map<String, dynamic> data, List<String> path) {
  dynamic cur = data;
  for (final p in path) {
    if (cur is Map<String, dynamic> && cur.containsKey(p)) {
      cur = cur[p];
    } else {
      return '';
    }
  }
  if (cur is Timestamp) {
    final dt = cur.toDate();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

/// ----------------------------
/// Empty / error states
/// ----------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No pre-assessments found for these filters.\n\n'
          'If you’ve just submitted one, try setting Status = All.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _EmptyStateGeneral extends StatelessWidget {
  const _EmptyStateGeneral();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No general visit questionnaires found for these filters.\n\n'
          'Tap + to create a new General Visit intake.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PermissionDeniedState extends StatelessWidget {
  final String clinicId;
  final String raw;

  const _PermissionDeniedState({
    required this.clinicId,
    required this.raw,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 44),
            const SizedBox(height: 12),
            const Text(
              'Permission denied',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Firestore rules are blocking reads from:\n'
              'clinics/$clinicId/intakeSessions\n\n'
              'Ensure the logged-in user is an active clinic member and has clinical.read (or your viewClinical equivalent).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              raw,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Query error:\n\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
