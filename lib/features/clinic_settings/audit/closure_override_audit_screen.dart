// lib/features/clinic_settings/audit/closure_override_audit_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/clinic_context.dart';
import '../../../app/clinic_session.dart';
import '../../booking/ui/booking_calendar_screen.dart';

class ClosureOverrideAuditScreen extends StatelessWidget {
  const ClosureOverrideAuditScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
        builder: (_) => const ClosureOverrideAuditScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final clinicId = context.watch<ClinicContext>().clinicId.trim();
    final session = context.watch<ClinicSession?>();

    if (clinicId.isEmpty) {
      return const _FatalPanel(
        title: 'No clinic selected',
        message: 'ClinicContext.clinicId is empty.',
      );
    }

    // Permission gate (optional — if you want it)
    final canReadAudit = session?.permissions.has('audit.read') == true ||
        session?.permissions.has('settings.read') == true ||
        session?.permissions.has('settings.write') == true;

    if (!canReadAudit) {
      return const Scaffold(
        appBar: _AppBar(title: 'Closure override audit'),
        body: _EmptyStateCard(
          title: 'Missing permission',
          message:
              'You do not have audit.read permission.\n\n'
              'Ask an admin to grant audit.read (or settings.read) in your member permissions.',
        ),
      );
    }

    final auditStream = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('audit')
        // ✅ Query only by createdAt (no type filter) to avoid composite index issues.
        .orderBy('createdAt', descending: true)
        .limit(250)
        .snapshots();

    return Scaffold(
      appBar: const _AppBar(title: 'Closure override audit'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: auditStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _FatalPanel(
              title: 'Failed to load audit',
              message:
                  '${snap.error}\n\n'
                  'If the error mentions "requires an index", you can also fix it by removing any '
                  'where(type==...) filters (this screen does not use them).\n\n'
                  'Also confirm Firestore rules allow clinics/{clinicId}/audit reads for audit.read.',
            );
          }

          final docs = snap.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          final events = docs
              .map((d) => _AuditEventRow.fromDoc(d.id, d.data()))
              .where((e) => _overrideTypes.contains(e.type))
              .toList();

          if (events.isEmpty) {
            return const Center(
              child: _EmptyStateCard(
                title: 'No override events yet',
                message:
                    'This screen only shows events where a booking was saved into a closed time window.\n\n'
                    'If you only created closures (e.g. type: clinic.closure.created) there will be nothing here.\n\n'
                    'To generate an override event:\n'
                    '• Drag an appointment into a closure\n'
                    '• Confirm "Save anyway"\n'
                    '• The backend must write type: clinic.closure.override.used',
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final e = events[i];
              return _AuditCard(
                event: e,
                onJump: e.hasJumpTarget
                    ? () => _jumpToCalendar(
                          context,
                          focus: e.jumpFocus!,
                          appointmentId: e.appointmentId,
                        )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  static const Set<String> _overrideTypes = {
    // ✅ recommended (matches the TS we want to write)
    'clinic.closure.override.used',
    // legacy variants (keep for compatibility)
    'closure.override.used',
    'appointment.closed_override',
  };

  void _jumpToCalendar(
    BuildContext context, {
    required DateTime focus,
    required String? appointmentId,
  }) {
    Navigator.of(context).push(
      BookingCalendarScreen.route(
        focus: focus,
        appointmentId: appointmentId,
      ),
    );
  }
}

class _AuditEventRow {
  final String id;
  final String type;
  final String actorUid;
  final String actorDisplayName;
  final DateTime? createdAt;

  final String? appointmentId;
  final Map<String, dynamic> metadata;

  const _AuditEventRow({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorDisplayName,
    required this.createdAt,
    required this.appointmentId,
    required this.metadata,
  });

  factory _AuditEventRow.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'];
    DateTime? createdAt;
    if (ts is Timestamp) createdAt = ts.toDate();

    final metaRaw = data['metadata'];

    // ✅ Fix: remove unnecessary cast (metaRaw is already Map here)
    final metadata =
        (metaRaw is Map) ? Map<String, dynamic>.from(metaRaw) : <String, dynamic>{};

    final actorDisplayName =
        (data['actorDisplayName'] ?? '').toString().trim();
    final actorUid = (data['actorUid'] ?? '').toString().trim();

    final apptId =
        (data['appointmentId'] ?? metadata['appointmentId'] ?? '')
            .toString()
            .trim();
    final appointmentId = apptId.isEmpty ? null : apptId;

    return _AuditEventRow(
      id: id,
      type: (data['type'] ?? '').toString().trim(),
      actorUid: actorUid,
      actorDisplayName: actorDisplayName.isEmpty ? actorUid : actorDisplayName,
      createdAt: createdAt,
      appointmentId: appointmentId,
      metadata: metadata,
    );
  }

  bool get hasJumpTarget => jumpFocus != null;

  DateTime? get jumpFocus {
    // Preferred: metadata.startMs
    final startMs = metadata['startMs'];
    if (startMs is int) {
      return DateTime.fromMillisecondsSinceEpoch(startMs);
    }
    if (startMs is num) {
      return DateTime.fromMillisecondsSinceEpoch(startMs.toInt());
    }

    // Fallback: metadata.start ISO
    final startIso = (metadata['start'] ?? '').toString().trim();
    if (startIso.isNotEmpty) {
      final d = DateTime.tryParse(startIso);
      if (d != null) return d;
    }

    // Fallback: createdAt
    return createdAt;
  }

  String get whenLabel {
    final d = createdAt;
    if (d == null) return 'Unknown time';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _AuditCard extends StatelessWidget {
  final _AuditEventRow event;
  final VoidCallback? onJump;

  const _AuditCard({
    required this.event,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final closureId = (event.metadata['closureId'] ?? '').toString().trim();
    final closureIds = event.metadata['closureIds'];
    final closureIdsText = (closureIds is List)
        ? closureIds
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .join(', ')
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Closure override used',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${event.whenLabel} • ${event.actorDisplayName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (event.appointmentId != null)
                  _pill(context, 'Appointment: ${event.appointmentId}'),
                if (closureId.isNotEmpty) _pill(context, 'Closure: $closureId'),
                if (closureIdsText.isNotEmpty)
                  _pill(context, 'Closures: $closureIdsText'),
              ],
            ),
            if (onJump != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onJump,
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Open calendar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _AppBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: false,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _EmptyStateCard extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyStateCard({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FatalPanel extends StatelessWidget {
  final String title;
  final String message;

  const _FatalPanel({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
