import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/clinical_tests.dart';
import 'body_chart.dart';

BodyRegion? bodyRegionFromString(String? raw) {
  if (raw == null) return null;
  final v = raw.trim();
  for (final region in BodyRegion.values) {
    if (region.name == v) return region;
  }
  return null;
}

String? bodyRegionToString(BodyRegion? region) => region?.name;

/// Simple helper for 0–10 pain scores.
int _clampPainScore(dynamic v) {
  if (v == null) return 0;
  final n = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
  if (n < 0) return 0;
  if (n > 10) return 10;
  return n;
}

DateTime? _tsToDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

String _safeString(dynamic v) => (v ?? '').toString();

bool _safeBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1';
}

int _safeInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _safeDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

List<String> _stringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList();
  }
  return const [];
}

List<Map<String, dynamic>> _mapList(dynamic v) {
  if (v is List) {
    return v
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  return const [];
}

/// Red flag checklist item.
class RedFlagItem {
  final String id;
  final String label;
  final bool isPositive;
  final String notes;

  const RedFlagItem({
    required this.id,
    required this.label,
    required this.isPositive,
    required this.notes,
  });

  factory RedFlagItem.fromMap(Map<String, dynamic> map) {
    return RedFlagItem(
      id: _safeString(map['id']),
      label: _safeString(map['label']),
      isPositive: _safeBool(map['isPositive']),
      notes: _safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'isPositive': isPositive,
        'notes': notes,
      };
}

/// Functional test entry in objective section.
class FunctionalTestEntry {
  final String name;
  final String result;
  final String notes;

  const FunctionalTestEntry({
    required this.name,
    required this.result,
    required this.notes,
  });

  factory FunctionalTestEntry.fromMap(Map<String, dynamic> map) {
    return FunctionalTestEntry(
      name: _safeString(map['name']),
      result: _safeString(map['result']),
      notes: _safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'result': result,
        'notes': notes,
      };
}

/// Generic range-of-motion entry with optional normal range metadata.
class RangeOfMotionEntry {
  final String id;
  final String label;
  final String? direction; // e.g. flex, ext, rotL
  final String? side; // L/R/B/NA
  final double value; // degrees
  final bool painful;
  final double? normalMin;
  final double? normalMax;

  const RangeOfMotionEntry({
    required this.id,
    required this.label,
    this.direction,
    this.side,
    required this.value,
    required this.painful,
    this.normalMin,
    this.normalMax,
  });

  factory RangeOfMotionEntry.fromMap(Map<String, dynamic> map) {
    return RangeOfMotionEntry(
      id: _safeString(map['id']),
      label: _safeString(map['label']),
      direction: (map['direction'] ?? '').toString().trim().isEmpty
          ? null
          : map['direction'].toString(),
      side: (map['side'] ?? '').toString().trim().isEmpty
          ? null
          : map['side'].toString(),
      value: _safeDouble(map['value']),
      painful: _safeBool(map['painful']),
      normalMin: map['normalMin'] != null ? _safeDouble(map['normalMin']) : null,
      normalMax: map['normalMax'] != null ? _safeDouble(map['normalMax']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'direction': direction,
        'side': side,
        'value': value,
        'painful': painful,
        'normalMin': normalMin,
        'normalMax': normalMax,
      };
}

/// Generic strength entry.
class StrengthEntry {
  final String id;
  final String label;
  final String? side;
  final int grade; // 0–5
  final String notes;

  const StrengthEntry({
    required this.id,
    required this.label,
    this.side,
    required this.grade,
    required this.notes,
  });

  factory StrengthEntry.fromMap(Map<String, dynamic> map) {
    return StrengthEntry(
      id: _safeString(map['id']),
      label: _safeString(map['label']),
      side: (map['side'] ?? '').toString().trim().isEmpty
          ? null
          : map['side'].toString(),
      grade: _safeInt(map['grade']),
      notes: _safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'side': side,
        'grade': grade,
        'notes': notes,
      };
}

/// Special test selection, keyed by registry testId.
class SpecialTestResult {
  final String testId;
  final String result; // e.g. "pos" | "neg" | "nt" | "na"
  final String side; // "L" | "R" | "B" | "N/A"
  final String notes;
  final int painScore; // 0–10 (optional in UI; stored as 0 if unused)

  const SpecialTestResult({
    required this.testId,
    required this.result,
    required this.side,
    required this.notes,
    required this.painScore,
  });

  factory SpecialTestResult.fromMap(Map<String, dynamic> map) {
    return SpecialTestResult(
      testId: _safeString(map['testId']),
      result: _safeString(map['result']),
      side: _safeString(map['side']),
      notes: _safeString(map['notes']),
      painScore: _clampPainScore(map['painScore']),
    );
  }

  Map<String, dynamic> toMap() => {
        'testId': testId,
        'result': result,
        'side': side,
        'notes': notes,
        'painScore': painScore,
      };
}

/// Outcome measure entry in Assessment section.
class OutcomeMeasureEntry {
  final String name;
  final String score;
  final DateTime? date;

  const OutcomeMeasureEntry({
    required this.name,
    required this.score,
    required this.date,
  });

  factory OutcomeMeasureEntry.fromMap(Map<String, dynamic> map) {
    return OutcomeMeasureEntry(
      name: _safeString(map['name']),
      score: _safeString(map['score']),
      date: _tsToDate(map['date']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'score': score,
        'date': date,
      };
}

/// Exercise entry in Plan section.
class ExerciseEntry {
  final String name;
  final String dosage;
  final String notes;

  const ExerciseEntry({
    required this.name,
    required this.dosage,
    required this.notes,
  });

  factory ExerciseEntry.fromMap(Map<String, dynamic> map) {
    return ExerciseEntry(
      name: _safeString(map['name']),
      dosage: _safeString(map['dosage']),
      notes: _safeString(map['notes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'dosage': dosage,
        'notes': notes,
      };
}

/// Top-level Initial Assessment SOAP note model.
///
/// Stored under:
/// clinics/{clinicId}/patients/{patientId}/soapNotes/{noteId}
class InitialAssessmentNote {
  final String id;
  final String clinicId;
  final String patientId;

  /// "initial" | "followup"
  final String noteType;

  final BodyRegion bodyRegion;

  /// "draft" | "final"
  final String status;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finalizedAt;
  final String createdByUid;
  final String? updatedByUid;

  // ───────────────────────── Subjective ─────────────────────────
  final String presentingComplaint;
  final String historyOfPresentingComplaint;

  final int painIntensityNow;
  final int painIntensityBest;
  final int painIntensityWorst;
  final String painIrritability; // low | mod | high
  final String painNature; // free text, e.g. ache/sharp/burning…

  final List<String> aggravatingFactors;
  final List<String> easingFactors;
  final String pattern24h;
  final List<RedFlagItem> redFlags;
  final String yellowFlags;
  final String pastMedicalHistory;
  final String meds;
  final String imaging;
  final String goals;
  final String functionalLimitations;
  final BodyChartState bodyChart;

  // ───────────────────────── Objective (common) ─────────────────────────
  final String observation;
  final String neuroScreenSummary;
  final List<FunctionalTestEntry> functionalTests;
  final String palpation;
  final List<RangeOfMotionEntry> rangeOfMotion;
  final List<StrengthEntry> strength;

  /// Optional high-level summaries for neuro exam.
  final String neuroMyotomesSummary;
  final String neuroDermatomesSummary;
  final String neuroReflexesSummary;

  /// Region-specific objective data, stored as a structured map using
  /// field keys from initial_assessment_fields.dart.
  final Map<String, dynamic> regionSpecificObjective;

  // ───────────────────────── Special tests ─────────────────────────
  final List<SpecialTestResult> specialTests;

  // ───────────────────────── Assessment ─────────────────────────
  final String primaryDiagnosis;
  final List<String> differentialDiagnoses;
  final String contributingFactors;
  final String clinicalReasoning;
  final String severity;
  final String irritability;
  final String stage;
  final List<OutcomeMeasureEntry> outcomeMeasures;

  // ───────────────────────── Plan ─────────────────────────
  final String planSummary;
  final String educationAdvice;
  final List<ExerciseEntry> exercises;
  final String manualTherapy;
  final String followUp;
  final String referrals;
  final bool consentConfirmed;
  final String homeAdvice;

  const InitialAssessmentNote({
    required this.id,
    required this.clinicId,
    required this.patientId,
    required this.noteType,
    required this.bodyRegion,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.finalizedAt,
    required this.createdByUid,
    required this.updatedByUid,
    required this.presentingComplaint,
    required this.historyOfPresentingComplaint,
    required this.painIntensityNow,
    required this.painIntensityBest,
    required this.painIntensityWorst,
    required this.painIrritability,
    required this.painNature,
    required this.aggravatingFactors,
    required this.easingFactors,
    required this.pattern24h,
    required this.redFlags,
    required this.yellowFlags,
    required this.pastMedicalHistory,
    required this.meds,
    required this.imaging,
    required this.goals,
    required this.functionalLimitations,
    required this.bodyChart,
    required this.observation,
    required this.neuroScreenSummary,
    required this.functionalTests,
    required this.palpation,
    required this.rangeOfMotion,
    required this.strength,
    required this.neuroMyotomesSummary,
    required this.neuroDermatomesSummary,
    required this.neuroReflexesSummary,
    required this.regionSpecificObjective,
    required this.specialTests,
    required this.primaryDiagnosis,
    required this.differentialDiagnoses,
    required this.contributingFactors,
    required this.clinicalReasoning,
    required this.severity,
    required this.irritability,
    required this.stage,
    required this.outcomeMeasures,
    required this.planSummary,
    required this.educationAdvice,
    required this.exercises,
    required this.manualTherapy,
    required this.followUp,
    required this.referrals,
    required this.consentConfirmed,
    required this.homeAdvice,
  });

  factory InitialAssessmentNote.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final region =
        bodyRegionFromString(_safeString(data['bodyRegion'])) ?? BodyRegion.other;

    final subjective = data['subjective'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final objective = data['objective'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final assessment = data['assessment'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final plan =
        data['plan'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    return InitialAssessmentNote(
      id: id,
      clinicId: _safeString(data['clinicId']),
      patientId: _safeString(data['patientId']),
      noteType: _safeString(data['noteType']).isEmpty
          ? 'initial'
          : _safeString(data['noteType']),
      bodyRegion: region,
      status: _safeString(data['status']).isEmpty
          ? 'draft'
          : _safeString(data['status']),
      createdAt: _tsToDate(data['createdAt']),
      updatedAt: _tsToDate(data['updatedAt']),
      finalizedAt: _tsToDate(data['finalizedAt']),
      createdByUid: _safeString(data['createdByUid']),
      updatedByUid: (data['updatedByUid'] ?? '').toString().trim().isEmpty
          ? null
          : data['updatedByUid'].toString(),
      presentingComplaint: _safeString(subjective['presentingComplaint']),
      historyOfPresentingComplaint:
          _safeString(subjective['historyOfPresentingComplaint']),
      painIntensityNow: _clampPainScore(subjective['painIntensityNow']),
      painIntensityBest: _clampPainScore(subjective['painIntensityBest']),
      painIntensityWorst: _clampPainScore(subjective['painIntensityWorst']),
      painIrritability: _safeString(subjective['painIrritability']),
      painNature: _safeString(subjective['painNature']),
      aggravatingFactors: _stringList(subjective['aggravatingFactors']),
      easingFactors: _stringList(subjective['easingFactors']),
      pattern24h: _safeString(subjective['pattern24h']),
      redFlags: _mapList(subjective['redFlags'])
          .map(RedFlagItem.fromMap)
          .toList(),
      yellowFlags: _safeString(subjective['yellowFlags']),
      pastMedicalHistory: _safeString(subjective['pastMedicalHistory']),
      meds: _safeString(subjective['meds']),
      imaging: _safeString(subjective['imaging']),
      goals: _safeString(subjective['goals']),
      functionalLimitations:
          _safeString(subjective['functionalLimitations']),
      bodyChart: BodyChartState.fromMap(
          subjective['bodyChart'] as Map<String, dynamic>?),
      observation: _safeString(objective['observation']),
      neuroScreenSummary: _safeString(objective['neuroScreenSummary']),
      functionalTests: _mapList(objective['functionalTests'])
          .map(FunctionalTestEntry.fromMap)
          .toList(),
      palpation: _safeString(objective['palpation']),
      rangeOfMotion: _mapList(objective['rangeOfMotion'])
          .map(RangeOfMotionEntry.fromMap)
          .toList(),
      strength: _mapList(objective['strength'])
          .map(StrengthEntry.fromMap)
          .toList(),
      neuroMyotomesSummary: _safeString(objective['neuroMyotomesSummary']),
      neuroDermatomesSummary: _safeString(objective['neuroDermatomesSummary']),
      neuroReflexesSummary: _safeString(objective['neuroReflexesSummary']),
      regionSpecificObjective:
          Map<String, dynamic>.from(objective['regionSpecific'] as Map? ??
              const <String, dynamic>{}),
      specialTests: _mapList(data['specialTests'])
          .map(SpecialTestResult.fromMap)
          .toList(),
      primaryDiagnosis: _safeString(assessment['primaryDiagnosis']),
      differentialDiagnoses:
          _stringList(assessment['differentialDiagnoses']),
      contributingFactors: _safeString(assessment['contributingFactors']),
      clinicalReasoning: _safeString(assessment['clinicalReasoning']),
      severity: _safeString(assessment['severity']),
      irritability: _safeString(assessment['irritability']),
      stage: _safeString(assessment['stage']),
      outcomeMeasures: _mapList(assessment['outcomeMeasures'])
          .map(OutcomeMeasureEntry.fromMap)
          .toList(),
      planSummary: _safeString(plan['planSummary']),
      educationAdvice: _safeString(plan['educationAdvice']),
      exercises: _mapList(plan['exercises'])
          .map(ExerciseEntry.fromMap)
          .toList(),
      manualTherapy: _safeString(plan['manualTherapy']),
      followUp: _safeString(plan['followUp']),
      referrals: _safeString(plan['referrals']),
      consentConfirmed: _safeBool(plan['consentConfirmed']),
      homeAdvice: _safeString(plan['homeAdvice']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clinicId': clinicId,
      'patientId': patientId,
      'noteType': noteType,
      'bodyRegion': bodyRegionToString(bodyRegion),
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'finalizedAt': finalizedAt,
      'createdByUid': createdByUid,
      'updatedByUid': updatedByUid,
      'subjective': {
        'presentingComplaint': presentingComplaint,
        'historyOfPresentingComplaint': historyOfPresentingComplaint,
        'painIntensityNow': painIntensityNow,
        'painIntensityBest': painIntensityBest,
        'painIntensityWorst': painIntensityWorst,
        'painIrritability': painIrritability,
        'painNature': painNature,
        'aggravatingFactors': aggravatingFactors,
        'easingFactors': easingFactors,
        'pattern24h': pattern24h,
        'redFlags': redFlags.map((e) => e.toMap()).toList(),
        'yellowFlags': yellowFlags,
        'pastMedicalHistory': pastMedicalHistory,
        'meds': meds,
        'imaging': imaging,
        'goals': goals,
        'functionalLimitations': functionalLimitations,
        'bodyChart': bodyChart.toMap(),
      },
      'objective': {
        'observation': observation,
        'neuroScreenSummary': neuroScreenSummary,
        'functionalTests':
            functionalTests.map((e) => e.toMap()).toList(),
        'palpation': palpation,
        'rangeOfMotion': rangeOfMotion.map((e) => e.toMap()).toList(),
        'strength': strength.map((e) => e.toMap()).toList(),
        'neuroMyotomesSummary': neuroMyotomesSummary,
        'neuroDermatomesSummary': neuroDermatomesSummary,
        'neuroReflexesSummary': neuroReflexesSummary,
        'regionSpecific': regionSpecificObjective,
      },
      'specialTests': specialTests.map((e) => e.toMap()).toList(),
      'assessment': {
        'primaryDiagnosis': primaryDiagnosis,
        'differentialDiagnoses': differentialDiagnoses,
        'contributingFactors': contributingFactors,
        'clinicalReasoning': clinicalReasoning,
        'severity': severity,
        'irritability': irritability,
        'stage': stage,
        'outcomeMeasures':
            outcomeMeasures.map((e) => e.toMap()).toList(),
      },
      'plan': {
        'planSummary': planSummary,
        'educationAdvice': educationAdvice,
        'exercises': exercises.map((e) => e.toMap()).toList(),
        'manualTherapy': manualTherapy,
        'followUp': followUp,
        'referrals': referrals,
        'consentConfirmed': consentConfirmed,
        'homeAdvice': homeAdvice,
      },
    };
  }
}

