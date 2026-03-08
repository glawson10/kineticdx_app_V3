import 'package:cloud_functions/cloud_functions.dart';
import '../../models/communication_settings.dart';

class CommunicationSettingsRepository {
  Future<Map<String, dynamic>> _fetchSettings(String clinicId) async {
    final fn = FirebaseFunctions.instance.httpsCallable('settingsGetCommunicationSettings');
    final result = await fn.call({'clinicId': clinicId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Stream<CommunicationSettings> streamSettings(String clinicId) async* {
    try {
      final data = await _fetchSettings(clinicId);
      yield CommunicationSettings.fromDoc(data);
    } catch (_) {
      yield CommunicationSettings.defaults;
    }
  }

  Future<void> updateSettings(String clinicId, Map<String, dynamic> patch) async {
    final fn = FirebaseFunctions.instance.httpsCallable('settingsUpdateCommunicationSettings');
    await fn.call({'clinicId': clinicId, ...patch});
  }
}
