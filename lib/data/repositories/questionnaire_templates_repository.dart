import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/questionnaire_flow.dart';

class QuestionnaireTemplatesRepository {
  QuestionnaireTemplatesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String preassessmentBookingTemplateId =
      'builtin.preassessment.booking';
  static const String generalVisitTemplateId = 'builtin.generalVisit';

  List<QuestionnaireTemplateSummary> builtInPatientFacingTemplates() {
    return const [
      QuestionnaireTemplateSummary(
        templateId: preassessmentBookingTemplateId,
        source: QuestionnaireTemplateSource.builtIn,
        label: 'Specific issue questionnaire',
        description:
            'Guides the patient into the specific-issue preassessment flow linked to their booking.',
        active: true,
        patientFacing: true,
        launchKind: QuestionnaireLaunchKind.bookingPreassessment,
        launchRoute: '/preassessment/consent',
      ),
      QuestionnaireTemplateSummary(
        templateId: generalVisitTemplateId,
        source: QuestionnaireTemplateSource.builtIn,
        label: 'General questionnaire',
        description:
            'Captures broad visit goals and context before the appointment.',
        active: true,
        patientFacing: true,
        launchKind: QuestionnaireLaunchKind.intakeLink,
        launchRoute: '/q/launch',
      ),
    ];
  }

  Stream<List<QuestionnaireTemplateSummary>> watchClinicCreatedTemplates(
    String clinicId,
  ) {
    final c = clinicId.trim();
    if (c.isEmpty) return Stream.value(const <QuestionnaireTemplateSummary>[]);
    return _firestore
        .collection('clinics')
        .doc(c)
        .collection('questionnaireTemplates')
        .snapshots()
        .map((snap) {
      return snap.docs
          .map(
            (doc) => QuestionnaireTemplateSummary.fromJson(
              doc.data(),
              fallbackTemplateId: doc.id,
            ),
          )
          .toList(growable: false);
    });
  }
}

