import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/service.dart';

class ServicesRepository {
  final FirebaseFirestore _db;

  ServicesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  Stream<List<Service>> activeServices(String clinicId) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('services')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        return Service.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }
}
