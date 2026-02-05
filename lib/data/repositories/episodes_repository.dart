import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/episode.dart';

class EpisodesRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  EpisodesRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  Stream<List<Episode>> episodes({
    required String clinicId,
    required String patientId,
  }) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .collection('patients')
        .doc(patientId)
        .collection('episodes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Episode.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<String> createEpisode({
    required String clinicId,
    required String patientId,
    required String title,
    String? primaryComplaint,
    String? onsetDate,
    String? referralSource,
    String? assignedPractitionerId,
    List<String>? tags,
  }) async {
    final res = await _functions.httpsCallable('createEpisodeFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'title': title,
      'primaryComplaint': primaryComplaint,
      'onsetDate': onsetDate,
      'referralSource': referralSource,
      'assignedPractitionerId': assignedPractitionerId,
      'tags': tags ?? [],
    });

    return (res.data['episodeId'] as String);
  }

  Future<void> updateEpisode({
    required String clinicId,
    required String patientId,
    required String episodeId,
    String? title,
    String? primaryComplaint,
    String? onsetDate,
    String? referralSource,
    String? assignedPractitionerId,
    List<String>? tags,
  }) async {
    await _functions.httpsCallable('updateEpisodeFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'episodeId': episodeId,
      'title': title,
      'primaryComplaint': primaryComplaint,
      'onsetDate': onsetDate,
      'referralSource': referralSource,
      'assignedPractitionerId': assignedPractitionerId,
      'tags': tags,
    });
  }

  Future<void> closeEpisode({
    required String clinicId,
    required String patientId,
    required String episodeId,
    String? closedReason,
  }) async {
    await _functions.httpsCallable('closeEpisodeFn').call({
      'clinicId': clinicId,
      'patientId': patientId,
      'episodeId': episodeId,
      'closedReason': closedReason,
    });
  }
}
