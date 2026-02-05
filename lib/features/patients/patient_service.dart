import 'package:cloud_functions/cloud_functions.dart';

class PatientService {
  final FirebaseFunctions _functions;
  PatientService({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  Future<String> createPatient({
    required String clinicId,
    required String firstName,
    required String lastName,
    String? preferredName,
    String? dateOfBirthIso, // YYYY-MM-DD
    String? email,
    String? phone,
  }) async {
    final callable = _functions.httpsCallable("createPatientFn");
    final res = await callable.call({
      "clinicId": clinicId,
      "firstName": firstName,
      "lastName": lastName,
      "preferredName": preferredName,
      "dateOfBirth": dateOfBirthIso,
      "email": email,
      "phone": phone,
    });

    final patientId = (res.data as Map?)?["patientId"]?.toString();
    if (patientId == null || patientId.isEmpty) {
      throw Exception("createPatientFn did not return patientId");
    }
    return patientId;
  }

  Future<void> updatePatient({
    required String clinicId,
    required String patientId,
    Map<String, dynamic>? patch,
  }) async {
    final callable = _functions.httpsCallable("updatePatientFn");
    await callable.call({
      "clinicId": clinicId,
      "patientId": patientId,
      ...?patch,
    });
  }
}
