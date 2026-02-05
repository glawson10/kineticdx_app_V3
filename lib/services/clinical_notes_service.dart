import 'package:cloud_functions/cloud_functions.dart';

/// A user-friendly error you can show in the UI.
class AppError implements Exception {
  AppError(this.message, {this.code, this.details});
  final String message;
  final String? code;
  final Object? details;

  @override
  String toString() =>
      'AppError(code: $code, message: $message, details: $details)';
}

class ClinicalNotesService {
  ClinicalNotesService()
      : _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> createClinicalNote({
    required String clinicId,
    required String episodeId,
    required String patientId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final callable = _functions.httpsCallable('createClinicalNoteFn');
      final res = await callable.call({
        'clinicId': clinicId,
        'episodeId': episodeId,
        'patientId': patientId,
        'payload': payload,
      });

      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'result': data};
    } on FirebaseFunctionsException catch (e) {
      // Map backend codes to human-friendly messages
      throw AppError(
        _friendlyCallableMessage(e),
        code: e.code,
        details: e.details,
      );
    } catch (e) {
      // Catch-all (network, unexpected)
      throw AppError('Something went wrong. Please try again.', details: e);
    }
  }

  String _friendlyCallableMessage(FirebaseFunctionsException e) {
    // Common callable codes: unauthenticated, permission-denied, invalid-argument, not-found, internal, unavailable
    switch (e.code) {
      case 'unauthenticated':
        return 'You’re not signed in. Please sign in and try again.';
      case 'permission-denied':
        return 'You don’t have permission to do that for this clinic.';
      case 'invalid-argument':
        return 'Some information is missing or invalid. Please check and try again.';
      case 'not-found':
        return 'This action is not available right now (function not found).';
      case 'unavailable':
        return 'Network issue. Check your connection and try again.';
      case 'deadline-exceeded':
        return 'That took too long. Please try again.';
      default:
        // 'internal' or anything else
        return 'We hit a server problem. Please try again in a moment.';
    }
  }
}
