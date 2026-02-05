// general_visit_v1_summary.dart
//
// 1-screen clinician summary builder for generalVisit.v1.
// Outputs patient-reported context only. :contentReference[oaicite:4]{index=4}
//
// This can also drive PDF rendering tokens.

import '../../shared/answers/answer_value_helpers.dart';
import './../../flows/general_visit/general_visit_v1_maps.dart';

class GeneralVisitSummaryV1 {
  final String flowId; // "generalVisit"
  final int flowVersion; // 1
  final String title; // Clinician UI heading
  final String disclaimer; // Non-diagnostic statement

  // Core
  final String reasonForVisit; // text or "—"
  final String concernClarityLabel; // label or "—"
  final List<String> bodyAreaLabels; // chips
  final String primaryImpactLabel;
  final List<String> limitedActivityLabels;
  final String durationLabel;
  final List<String> visitIntentLabels;

  // Safety acknowledgements (bool -> yes/no)
  final String ackNotEmergency;
  final String ackNoDiagnosis;

  // Key answers whitelist for list view / safe Phase 5 reference
  final Map<String, dynamic> keyAnswers;

  const GeneralVisitSummaryV1({
    required this.flowId,
    required this.flowVersion,
    required this.title,
    required this.disclaimer,
    required this.reasonForVisit,
    required this.concernClarityLabel,
    required this.bodyAreaLabels,
    required this.primaryImpactLabel,
    required this.limitedActivityLabels,
    required this.durationLabel,
    required this.visitIntentLabels,
    required this.ackNotEmergency,
    required this.ackNoDiagnosis,
    required this.keyAnswers,
  });
}

GeneralVisitSummaryV1 buildGeneralVisitSummaryV1({
  required AnswerMap answers,
}) {
  // Question IDs
  const qReason = 'generalVisit.goals.reasonForVisit';
  const qClarity = 'generalVisit.meta.concernClarity';
  const qAreas = 'generalVisit.history.bodyAreas';
  const qImpact = 'generalVisit.function.primaryImpact';
  const qLimited = 'generalVisit.function.limitedActivities';
  const qDuration = 'generalVisit.history.duration';
  const qIntent = 'generalVisit.goals.visitIntent';
  const qAckNE = 'consent.notEmergency.ack';
  const qAckND = 'consent.noDiagnosis.ack';

  // Read typed answers
  final reason = readText(answers, qReason) ?? '—';
  final clarityId = readSingle(answers, qClarity);
  final areasIds = readMulti(answers, qAreas);
  final impactId = readSingle(answers, qImpact);
  final limitedIds = readMulti(answers, qLimited);
  final durationId = readSingle(answers, qDuration);
  final intentIds = readMulti(answers, qIntent);

  final ackNE = readBool(answers, qAckNE);
  final ackND = readBool(answers, qAckND);

  // Map to labels
  final clarityLabel = labelSingle(clarityId, gvConcernClarityLabels);
  final bodyAreaLabels = labelsMulti(areasIds, gvBodyAreaLabels);
  final impactLabel = labelSingle(impactId, gvPrimaryImpactLabels);
  final limitedLabels = labelsMulti(limitedIds, gvLimitedActivityLabels);
  final durationLabel = labelSingle(durationId, gvDurationLabels);
  final intentLabels = labelsMulti(intentIds, gvVisitIntentLabels);

  // Yes/No strings for display + PDF tokens
  String yn(bool? v) => v == true ? 'Yes' : (v == false ? 'No' : '—');

  // Key answers whitelist (patient-reported only)
  // This is the safe subset you can show in clinician list cards
  // and reference in Phase 5 under "preAssessment.keyAnswers". :contentReference[oaicite:5]{index=5}
  final keyAnswers = <String, dynamic>{
    qReason: reason == '—' ? null : reason,
    qClarity: clarityId,
    qAreas: areasIds,
    qImpact: impactId,
    qDuration: durationId,
    qIntent: intentIds,
  };

  return GeneralVisitSummaryV1(
    flowId: 'generalVisit',
    flowVersion: 1,
    title: 'Visit context (patient-reported)',
    disclaimer: 'Not a diagnosis. Generated from patient-reported intake to support visit planning.',
    reasonForVisit: reason,
    concernClarityLabel: clarityLabel,
    bodyAreaLabels: bodyAreaLabels,
    primaryImpactLabel: impactLabel,
    limitedActivityLabels: limitedLabels,
    durationLabel: durationLabel,
    visitIntentLabels: intentLabels,
    ackNotEmergency: yn(ackNE),
    ackNoDiagnosis: yn(ackND),
    keyAnswers: keyAnswers,
  );
}
