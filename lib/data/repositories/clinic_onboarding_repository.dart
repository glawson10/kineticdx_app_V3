import 'package:cloud_functions/cloud_functions.dart';

class ClinicOnboardingRepository {
  final FirebaseFunctions _functions;

  ClinicOnboardingRepository({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<String> createClinic({
    required String name,
    String timezone = "Europe/Prague",
    String defaultLanguage = "en",
  }) async {
    final res = await _functions.httpsCallable('clinicCreate').call({
      'name': name,
      'timezone': timezone,
      'defaultLanguage': defaultLanguage,
    });

    return (res.data['clinicId'] as String);
  }
}
