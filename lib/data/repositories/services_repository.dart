// Cached stream per clinicId to avoid Firestore web SDK LateInitializationError
// when StreamBuilder is disposed before snapshot callback runs.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/service.dart';

class ServicesRepository {
  ServicesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String? _cachedClinicId;
  Stream<List<Service>>? _cachedStream;
  StreamSubscription<List<Service>>? _sourceSub;
  StreamController<List<Service>>? _controller;
  List<Service>? _lastList;

  Stream<List<Service>> activeServices(String clinicId) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const []);
    if (_cachedClinicId == c && _cachedStream != null) return _cachedStream!;

    _sourceSub?.cancel();
    _controller?.close();
    _cachedClinicId = c;
    _lastList = null;
    _controller = StreamController<List<Service>>.broadcast();

    final source = _db
        .collection('clinics')
        .doc(c)
        .collection('services')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Service.fromFirestore(doc.id, doc.data()))
            .toList());

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
}
