// lib/data/repositories/waitlist_repository.dart
// Repository for waitlist entries (clinic-scoped).
// Cached stream per clinicId to avoid Firestore web SDK LateInitializationError
// when StreamBuilder is disposed before snapshot callback runs.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/waitlist_entry.dart';

class WaitlistRepository {
  WaitlistRepository([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String? _cachedClinicId;
  Stream<List<WaitlistEntry>>? _cachedStream;
  StreamSubscription<List<WaitlistEntry>>? _sourceSub;
  StreamController<List<WaitlistEntry>>? _controller;
  List<WaitlistEntry>? _lastList;

  Stream<List<WaitlistEntry>> watchWaitlist(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    if (_cachedClinicId == c && _cachedStream != null) return _cachedStream!;

    _sourceSub?.cancel();
    _controller?.close();
    _cachedClinicId = c;
    _lastList = null;
    _controller = StreamController<List<WaitlistEntry>>.broadcast();

    final source = _firestore
        .collection('clinics')
        .doc(c)
        .collection('waitlist')
        .orderBy('priority', descending: true)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());

    _sourceSub = source.listen(
      (list) {
        _lastList = list;
        _controller!.add(list);
      },
      onError: _controller!.addError,
      onDone: _controller!.close,
      cancelOnError: false,
    );

    _cachedStream = Stream.multi((sink) {
      if (_lastList != null) sink.add(_lastList!);
      final sub = _controller!.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = () => sub.cancel();
    });
    return _cachedStream!;
  }

  /// Alias for [watchWaitlist].
  Stream<List<WaitlistEntry>> watchEntries(String clinicId) =>
      watchWaitlist(clinicId);

  /// Add a new waitlist entry. Use id: '' for new entries; Firestore generates the doc id.
  Future<void> addEntry(WaitlistEntry entry) async {
    if (entry.clinicId.isEmpty) throw ArgumentError('clinicId required');
    final col = _firestore
        .collection('clinics')
        .doc(entry.clinicId)
        .collection('waitlist');
    final data = entry.toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await col.add(data);
  }

  Future<void> removeEntry(String clinicId, String entryId) async {
    await _firestore
        .collection('clinics')
        .doc(clinicId)
        .collection('waitlist')
        .doc(entryId)
        .delete();
  }

  static WaitlistEntry _fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return WaitlistEntry(
      id: doc.id,
      clinicId: (d['clinicId'] as String?) ?? '',
      patientId: d['patientId'] as String?,
      patientDisplayName: d['patientDisplayName'] as String?,
      priority: (d['priority'] as num?)?.toInt() ?? 0,
      notes: d['notes'] as String?,
      preferredPractitionerIds:
          List<String>.from(d['preferredPractitionerIds'] as List? ?? []),
      preferredAppointmentTypeIds:
          List<String>.from(d['preferredAppointmentTypeIds'] as List? ?? []),
      earliestDate: (d['earliestDate'] as Timestamp?)?.toDate(),
      latestDate: (d['latestDate'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
