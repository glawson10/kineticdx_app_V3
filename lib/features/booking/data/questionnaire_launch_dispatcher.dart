import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';
import '../../../models/questionnaire_flow.dart';

typedef QuestionnairePatientPrefill = Map<String, dynamic>;

class QuestionnaireLaunchDispatcher {
  /// Launches the questionnaire flow. When [navigator] is provided, uses it for
  /// navigation (e.g. so the questionnaire is pushed on top of a specific stack).
  static Future<void> launch(
    BuildContext context, {
    required String clinicId,
    required String bookingRequestId,
    required QuestionnairePatientPrefill prefillPatient,
    required QuestionnaireTemplateSummary template,
    NavigatorState? navigator,
  }) async {
    final nav = navigator ?? Navigator.of(context);
    switch (template.launchKind) {
      case QuestionnaireLaunchKind.bookingPreassessment:
        await nav.pushNamed(
          AppRoutes.preassessmentConsent,
          arguments: {
            'clinicId': clinicId,
            'bookingRequestId': bookingRequestId,
            'prefillPatient': prefillPatient,
            'templateId': template.templateId,
          },
        );
        return;
      case QuestionnaireLaunchKind.intakeLink:
        final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
        final fn = functions.httpsCallable('createQuestionnaireLaunchLinkFn');
        final resp = await fn.call(<String, dynamic>{
          'clinicId': clinicId.trim(),
          'templateId': template.templateId,
          'bookingRequestId': bookingRequestId,
          'prefillPatient': prefillPatient,
          'email': (prefillPatient['email'] ?? '').toString().trim(),
          'expiresInDays': 7,
        });
        if (resp.data is! Map) {
          throw Exception('Server returned unexpected payload: ${resp.data}');
        }
        final data = Map<String, dynamic>.from(resp.data as Map);
        final token = (data['token'] ?? '').toString().trim();
        if (token.isEmpty) {
          throw Exception('Server did not return a questionnaire token.');
        }
        await nav.pushNamed(
          '${AppRoutes.questionnaireTokenBase}/$token',
        );
        return;
      case QuestionnaireLaunchKind.route:
        final routeName = (template.launchRoute ?? '').trim();
        if (routeName.isEmpty) {
          throw Exception('Questionnaire route is missing for ${template.templateId}.');
        }
        await nav.pushNamed(
          routeName,
          arguments: {
            'clinicId': clinicId,
            'bookingRequestId': bookingRequestId,
            'prefillPatient': prefillPatient,
            'templateId': template.templateId,
          },
        );
        return;
      default:
        throw Exception('Unsupported questionnaire launch kind: ${template.launchKind}');
    }
  }
}

