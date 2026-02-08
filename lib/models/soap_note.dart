// lib/models/soap_note.dart
//
// SOAP / IFOMPT-style encounter model for mobile.
// Designed to be:
//  - Simple to use in UI (tabs + expansion tiles)
//  - Region-based Objective, linking to clinical test registry via testId
//  - Firestore-friendly (toJson / fromJson)
//  - Clinic-scoped under clinics/{clinicId}/patients/{patientId}/soapNotes/{noteId}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';
import 'clinical_tests.dart'; // for BodyRegion enum

// -----------------------------------------------------------------------------
// Enums
// -----------------------------------------------------------------------------

/// Tabs for UI navigation (optional helper).
enum SoapNoteTab { screening, subjective, objective, analysis, plan }

/// Side of body (where applicable).
enum BodySide { left, right, bilateral, midline, central }

/// Generic 3-level rating (e.g. risk, irritability, prognosis).
enum TernaryLevel { low, moderate, high }

/// Simple yes/no/unknown, useful in structured decisions.
enum YesNoUnknown { yes, no, unknown }

/// Outcome of a clinical test within a note.
enum ClinicalTestResult { positive, negative, notTested }

/// Pain mechanism classification.
enum PainMechanism { nociceptive, neuropathic, central, mixed, uncertain }

// -----------------------------------------------------------------------------
// Root encounter model
// -----------------------------------------------------------------------------

@immutable
class SoapNote {
  final String id; // firestore document id
  final String clinicId;
  final String patientId;
  final String? assessmentId; // link to preassessment / encounter
  final String clinicianId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final ScreeningSection screening;
  final SubjectiveSection subjective;
  final ObjectiveSection objective;
  final AnalysisSection analysis;
  final PlanSection plan;

  /// List of clinical test entries (structured)
  final List<ClinicalTestEntry> clinicalTests;

  /// Primary body region for this note
  final BodyRegion bodyRegion;

  /// Status: "draft" | "final"
  final String status;

  const SoapNote({
    required this.id,
    required this.clinicId,
    required this.patientId,
    this.assessmentId,
    required this.clinicianId,
    this.createdAt,
    this.updatedAt,
    required this.screening,
    required this.subjective,
    required this.objective,
    required this.analysis,
    required this.plan,
    this.clinicalTests = const [],
    required this.bodyRegion,
    this.status = 'draft',
  });

  SoapNote copyWith({
    String? id,
    String? clinicId,
    String? patientId,
    String? assessmentId,
    String? clinicianId,
    DateTime? createdAt,
    DateTime? updatedAt,
    ScreeningSection? screening,
    SubjectiveSection? subjective,
    ObjectiveSection? objective,
    AnalysisSection? analysis,
    PlanSection? plan,
    List<ClinicalTestEntry>? clinicalTests,
    BodyRegion? bodyRegion,
    String? status,
  }) {
    return SoapNote(
      id: id ?? this.id,
      clinicId: clinicId ?? this.clinicId,
      patientId: patientId ?? this.patientId,
      assessmentId: assessmentId ?? this.assessmentId,
      clinicianId: clinicianId ?? this.clinicianId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      screening: screening ?? this.screening,
      subjective: subjective ?? this.subjective,
      objective: objective ?? this.objective,
      analysis: analysis ?? this.analysis,
      plan: plan ?? this.plan,
      clinicalTests: clinicalTests ?? this.clinicalTests,
      bodyRegion: bodyRegion ?? this.bodyRegion,
      status: status ?? this.status,
    );
  }

  // ---------------- Firestore mapping ----------------

  Map<String, dynamic> toFirestore() {
    return {
      'clinicId': clinicId,
      'patientId': patientId,
      'assessmentId': assessmentId,
      'clinicianId': clinicianId,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'screening': screening.toJson(),
      'subjective': subjective.toJson(),
      'objective': objective.toJson(),
      'analysis': analysis.toJson(),
      'plan': plan.toJson(),
      'clinicalTests': clinicalTests.map((e) => e.toJson()).toList(),
      'bodyRegion': bodyRegion.name,
      'status': status,
    };
  }

  factory SoapNote.fromFirestore(String id, Map<String, dynamic> json) {
    DateTime? _toDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return SoapNote(
      id: id,
      clinicId: json['clinicId'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      assessmentId: json['assessmentId'] as String?,
      clinicianId: json['clinicianId'] as String? ?? '',
      createdAt: _toDate(json['createdAt']),
      updatedAt: _toDate(json['updatedAt']),
      screening: ScreeningSection.fromJson(json['screening'] as Map<String, dynamic>? ?? {}),
      subjective: SubjectiveSection.fromJson(json['subjective'] as Map<String, dynamic>? ?? {}),
      objective: ObjectiveSection.fromJson(json['objective'] as Map<String, dynamic>? ?? {}),
      analysis: AnalysisSection.fromJson(json['analysis'] as Map<String, dynamic>? ?? {}),
      plan: PlanSection.fromJson(json['plan'] as Map<String, dynamic>? ?? {}),
      clinicalTests: (json['clinicalTests'] as List<dynamic>? ?? [])
          .map((e) => ClinicalTestEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      bodyRegion: BodyRegion.values.firstWhere(
        (v) => v.name == (json['bodyRegion'] ?? 'lumbar'),
        orElse: () => BodyRegion.lumbar,
      ),
      status: json['status'] as String? ?? 'draft',
    );
  }
}

// -----------------------------------------------------------------------------
// Clinical Test Entry (for storing test results in notes)
// -----------------------------------------------------------------------------

@immutable
class ClinicalTestEntry {
  final String testId;
  final String displayName; // snapshot of name at time of note
  final BodyRegion region;
  final ClinicalTestResult result;
  final String? comments;

  const ClinicalTestEntry({
    required this.testId,
    required this.displayName,
    required this.region,
    this.result = ClinicalTestResult.notTested,
    this.comments,
  });

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'displayName': displayName,
        'region': region.name,
        'result': result.name,
        'comments': comments,
      };

  factory ClinicalTestEntry.fromJson(Map<String, dynamic> json) =>
      ClinicalTestEntry(
        testId: json['testId'] as String,
        displayName: json['displayName'] as String? ?? '',
        region: BodyRegion.values.firstWhere(
          (v) => v.name == (json['region'] ?? 'lumbar'),
          orElse: () => BodyRegion.lumbar,
        ),
        result: ClinicalTestResult.values.firstWhere(
          (v) => v.name == (json['result'] ?? 'notTested'),
          orElse: () => ClinicalTestResult.notTested,
        ),
        comments: json['comments'] as String?,
      );
}

// -----------------------------------------------------------------------------
// Shared small value objects
// -----------------------------------------------------------------------------

@immutable
class FlagItem {
  final String id;
  final String label;
  final bool present;
  final String? notes;

  const FlagItem({
    required this.id,
    required this.label,
    this.present = false,
    this.notes,
  });

  FlagItem copyWith({
    String? id,
    String? label,
    bool? present,
    String? notes,
  }) {
    return FlagItem(
      id: id ?? this.id,
      label: label ?? this.label,
      present: present ?? this.present,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'present': present,
        'notes': notes,
      };

  factory FlagItem.fromJson(Map<String, dynamic> json) => FlagItem(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        present: (json['present'] ?? false) as bool,
        notes: json['notes'] as String?,
      );
}

@immutable
class FactorItem {
  final String label;
  final String? notes;

  const FactorItem({required this.label, this.notes});

  Map<String, dynamic> toJson() => {
        'label': label,
        'notes': notes,
      };

  factory FactorItem.fromJson(Map<String, dynamic> json) => FactorItem(
        label: json['label'] as String? ?? '',
        notes: json['notes'] as String?,
      );
}

@immutable
class GoalItem {
  final String description;
  final DateTime? targetDate;
  final bool achieved;

  const GoalItem({
    required this.description,
    this.targetDate,
    this.achieved = false,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'targetDate': targetDate?.toIso8601String(),
        'achieved': achieved,
      };

  factory GoalItem.fromJson(Map<String, dynamic> json) => GoalItem(
        description: json['description'] as String? ?? '',
        targetDate: json['targetDate'] != null
            ? DateTime.parse(json['targetDate'] as String)
            : null,
        achieved: (json['achieved'] ?? false) as bool,
      );
}

@immutable
class InterventionItem {
  final String type; // e.g. "Education", "Exercise", "Manual therapy"
  final String description;

  const InterventionItem({
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
      };

  factory InterventionItem.fromJson(Map<String, dynamic> json) =>
      InterventionItem(
        type: json['type'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

// -----------------------------------------------------------------------------
// Screening (IFOMPT safety / red flags / triage)
// -----------------------------------------------------------------------------

@immutable
class ScreeningSection {
  final List<FlagItem> redFlags;
  final List<FlagItem> vascularFlags; // e.g. 5 Ds, 3 Ns, ataxia
  final List<FlagItem> yellowFlags;

  final TernaryLevel overallRiskLevel; // clinical judgement
  final YesNoUnknown suitableForInput; // triage outcome
  final String? manualTherapyDecision; // e.g. "HVLA avoided due to ..."

  final String? referralPlan; // e.g. urgent ED / GP review
  final String? notes;

  const ScreeningSection({
    this.redFlags = const [],
    this.vascularFlags = const [],
    this.yellowFlags = const [],
    this.overallRiskLevel = TernaryLevel.low,
    this.suitableForInput = YesNoUnknown.yes,
    this.manualTherapyDecision,
    this.referralPlan,
    this.notes,
  });

  ScreeningSection copyWith({
    List<FlagItem>? redFlags,
    List<FlagItem>? vascularFlags,
    List<FlagItem>? yellowFlags,
    TernaryLevel? overallRiskLevel,
    YesNoUnknown? suitableForInput,
    String? manualTherapyDecision,
    String? referralPlan,
    String? notes,
  }) {
    return ScreeningSection(
      redFlags: redFlags ?? this.redFlags,
      vascularFlags: vascularFlags ?? this.vascularFlags,
      yellowFlags: yellowFlags ?? this.yellowFlags,
      overallRiskLevel: overallRiskLevel ?? this.overallRiskLevel,
      suitableForInput: suitableForInput ?? this.suitableForInput,
      manualTherapyDecision:
          manualTherapyDecision ?? this.manualTherapyDecision,
      referralPlan: referralPlan ?? this.referralPlan,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'redFlags': redFlags.map((e) => e.toJson()).toList(),
        'vascularFlags': vascularFlags.map((e) => e.toJson()).toList(),
        'yellowFlags': yellowFlags.map((e) => e.toJson()).toList(),
        'overallRiskLevel': overallRiskLevel.name,
        'suitableForInput': suitableForInput.name,
        'manualTherapyDecision': manualTherapyDecision,
        'referralPlan': referralPlan,
        'notes': notes,
      };

  factory ScreeningSection.fromJson(Map<String, dynamic> json) =>
      ScreeningSection(
        redFlags: (json['redFlags'] as List<dynamic>? ?? [])
            .map((e) => FlagItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        vascularFlags: (json['vascularFlags'] as List<dynamic>? ?? [])
            .map((e) => FlagItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        yellowFlags: (json['yellowFlags'] as List<dynamic>? ?? [])
            .map((e) => FlagItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        overallRiskLevel: TernaryLevel.values.firstWhere(
          (v) => v.name == (json['overallRiskLevel'] ?? 'low'),
          orElse: () => TernaryLevel.low,
        ),
        suitableForInput: YesNoUnknown.values.firstWhere(
          (v) => v.name == (json['suitableForInput'] ?? 'yes'),
          orElse: () => YesNoUnknown.yes,
        ),
        manualTherapyDecision: json['manualTherapyDecision'] as String?,
        referralPlan: json['referralPlan'] as String?,
        notes: json['notes'] as String?,
      );
}

// -----------------------------------------------------------------------------
// Subjective (model used by SoapNote)
// -----------------------------------------------------------------------------

@immutable
class SubjectiveSection {
  final String presentingComplaint;
  final String? onset;
  final String? mechanismOfInjury;

  final int? painCurrent;
  final int? painBest;
  final int? painWorst;

  final TernaryLevel irritability;
  final String? stage; // acute / sub / chronic etc

  final List<FactorItem> aggravatingFactors;
  final List<FactorItem> easingFactors;

  final String? pattern24h; // or split fields if you prefer later
  final String? bodyChartSummary; // descriptive summary; image stored elsewhere

  final String? pastHistory;
  final String? medicalHistory;
  final String? medications;
  final String? socialHistory;

  final List<GoalItem> patientGoals;

  /// Extra fields to match the current mobile UI more closely.
  /// Simple red-flag checklist gathered in the subjective tab.
  final Map<String, bool>? subjectiveRedFlags;

  /// Free-text "other notes" at the end of subjective.
  final String? otherNotes;

  /// Serialized body-chart drawing data (if you decide to store it later).
  final Map<String, dynamic>? bodyChartData;

  const SubjectiveSection({
    this.presentingComplaint = '',
    this.onset,
    this.mechanismOfInjury,
    this.painCurrent,
    this.painBest,
    this.painWorst,
    this.irritability = TernaryLevel.low,
    this.stage,
    this.aggravatingFactors = const [],
    this.easingFactors = const [],
    this.pattern24h,
    this.bodyChartSummary,
    this.pastHistory,
    this.medicalHistory,
    this.medications,
    this.socialHistory,
    this.patientGoals = const [],
    this.subjectiveRedFlags,
    this.otherNotes,
    this.bodyChartData,
  });

  SubjectiveSection copyWith({
    String? presentingComplaint,
    String? onset,
    String? mechanismOfInjury,
    int? painCurrent,
    int? painBest,
    int? painWorst,
    TernaryLevel? irritability,
    String? stage,
    List<FactorItem>? aggravatingFactors,
    List<FactorItem>? easingFactors,
    String? pattern24h,
    String? bodyChartSummary,
    String? pastHistory,
    String? medicalHistory,
    String? medications,
    String? socialHistory,
    List<GoalItem>? patientGoals,
    Map<String, bool>? subjectiveRedFlags,
    String? otherNotes,
    Map<String, dynamic>? bodyChartData,
  }) {
    return SubjectiveSection(
      presentingComplaint: presentingComplaint ?? this.presentingComplaint,
      onset: onset ?? this.onset,
      mechanismOfInjury: mechanismOfInjury ?? this.mechanismOfInjury,
      painCurrent: painCurrent ?? this.painCurrent,
      painBest: painBest ?? this.painBest,
      painWorst: painWorst ?? this.painWorst,
      irritability: irritability ?? this.irritability,
      stage: stage ?? this.stage,
      aggravatingFactors: aggravatingFactors ?? this.aggravatingFactors,
      easingFactors: easingFactors ?? this.easingFactors,
      pattern24h: pattern24h ?? this.pattern24h,
      bodyChartSummary: bodyChartSummary ?? this.bodyChartSummary,
      pastHistory: pastHistory ?? this.pastHistory,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      medications: medications ?? this.medications,
      socialHistory: socialHistory ?? this.socialHistory,
      patientGoals: patientGoals ?? this.patientGoals,
      subjectiveRedFlags: subjectiveRedFlags ?? this.subjectiveRedFlags,
      otherNotes: otherNotes ?? this.otherNotes,
      bodyChartData: bodyChartData ?? this.bodyChartData,
    );
  }

  Map<String, dynamic> toJson() => {
        'presentingComplaint': presentingComplaint,
        'onset': onset,
        'mechanismOfInjury': mechanismOfInjury,
        'painCurrent': painCurrent,
        'painBest': painBest,
        'painWorst': painWorst,
        'irritability': irritability.name,
        'stage': stage,
        'aggravatingFactors':
            aggravatingFactors.map((e) => e.toJson()).toList(),
        'easingFactors': easingFactors.map((e) => e.toJson()).toList(),
        'pattern24h': pattern24h,
        'bodyChartSummary': bodyChartSummary,
        'pastHistory': pastHistory,
        'medicalHistory': medicalHistory,
        'medications': medications,
        'socialHistory': socialHistory,
        'patientGoals': patientGoals.map((e) => e.toJson()).toList(),
        'subjectiveRedFlags': subjectiveRedFlags,
        'otherNotes': otherNotes,
        'bodyChartData': bodyChartData,
      };

  factory SubjectiveSection.fromJson(Map<String, dynamic> json) =>
      SubjectiveSection(
        presentingComplaint: (json['presentingComplaint'] ?? '') as String,
        onset: json['onset'] as String?,
        mechanismOfInjury: json['mechanismOfInjury'] as String?,
        painCurrent: json['painCurrent'] as int?,
        painBest: json['painBest'] as int?,
        painWorst: json['painWorst'] as int?,
        irritability: TernaryLevel.values.firstWhere(
          (v) => v.name == (json['irritability'] ?? 'low'),
          orElse: () => TernaryLevel.low,
        ),
        stage: json['stage'] as String?,
        aggravatingFactors: (json['aggravatingFactors'] as List<dynamic>? ?? [])
            .map((e) => FactorItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        easingFactors: (json['easingFactors'] as List<dynamic>? ?? [])
            .map((e) => FactorItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        pattern24h: json['pattern24h'] as String?,
        bodyChartSummary: json['bodyChartSummary'] as String?,
        pastHistory: json['pastHistory'] as String?,
        medicalHistory: json['medicalHistory'] as String?,
        medications: json['medications'] as String?,
        socialHistory: json['socialHistory'] as String?,
        patientGoals: (json['patientGoals'] as List<dynamic>? ?? [])
            .map((e) => GoalItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        subjectiveRedFlags:
            (json['subjectiveRedFlags'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as bool)),
        otherNotes: json['otherNotes'] as String?,
        bodyChartData: json['bodyChartData'] != null
            ? Map<String, dynamic>.from(
                json['bodyChartData'] as Map<String, dynamic>)
            : null,
      );
}

// -----------------------------------------------------------------------------
// Objective
// -----------------------------------------------------------------------------

@immutable
class ObjectiveSection {
  /// Global objective notes (posture, gait, general movement tests).
  /// This replaces the older "generalObservation" name.
  final String? globalNotes;

  final List<InterventionItem> functionalTests; // e.g. sit-to-stand description
  final List<OutcomeMeasureResult> outcomeMeasures;
  final List<RegionObjective> regions;

  const ObjectiveSection({
    this.globalNotes,
    this.functionalTests = const [],
    this.outcomeMeasures = const [],
    this.regions = const [],
  });

  ObjectiveSection copyWith({
    String? globalNotes,
    List<InterventionItem>? functionalTests,
    List<OutcomeMeasureResult>? outcomeMeasures,
    List<RegionObjective>? regions,
  }) {
    return ObjectiveSection(
      globalNotes: globalNotes ?? this.globalNotes,
      functionalTests: functionalTests ?? this.functionalTests,
      outcomeMeasures: outcomeMeasures ?? this.outcomeMeasures,
      regions: regions ?? this.regions,
    );
  }

  Map<String, dynamic> toJson() => {
        'globalNotes': globalNotes,
        'functionalTests': functionalTests.map((e) => e.toJson()).toList(),
        'outcomeMeasures':
            outcomeMeasures.map((e) => e.toJson()).toList(),
        'regions': regions.map((e) => e.toJson()).toList(),
      };

  factory ObjectiveSection.fromJson(Map<String, dynamic> json) =>
      ObjectiveSection(
        // Backwards-compatible: read either globalNotes or the older generalObservation.
        globalNotes: (json['globalNotes'] ??
            json['generalObservation']) as String?,
        functionalTests: (json['functionalTests'] as List<dynamic>? ?? [])
            .map((e) => InterventionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        outcomeMeasures: (json['outcomeMeasures'] as List<dynamic>? ?? [])
            .map(
                (e) => OutcomeMeasureResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        regions: (json['regions'] as List<dynamic>? ?? [])
            .map((e) => RegionObjective.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class OutcomeMeasureResult {
  final String name; // e.g. "NDI"
  final String score; // e.g. "26/50 (52%)"

  const OutcomeMeasureResult({required this.name, required this.score});

  Map<String, dynamic> toJson() => {
        'name': name,
        'score': score,
      };

  factory OutcomeMeasureResult.fromJson(Map<String, dynamic> json) =>
      OutcomeMeasureResult(
        name: json['name'] as String? ?? '',
        score: json['score'] as String? ?? '',
      );
}

@immutable
class RegionObjective {
  final BodyRegion region;
  final BodySide side;
  final String? segment; // e.g. "C5-6" if needed
  final String? summary; // optional free-text summary

  final List<RomFinding> activeRom;
  final List<RomFinding> passiveRom;
  final List<StrengthFinding> strength;
  final List<NeuroFinding> neuro;
  final List<JointMobilityFinding> jointMobility;
  final List<PalpationFinding> palpation;
  final List<ClinicalTestFinding> clinicalTests;

  const RegionObjective({
    required this.region,
    this.side = BodySide.central,
    this.segment,
    this.summary,
    this.activeRom = const [],
    this.passiveRom = const [],
    this.strength = const [],
    this.neuro = const [],
    this.jointMobility = const [],
    this.palpation = const [],
    this.clinicalTests = const [],
  });

  RegionObjective copyWith({
    BodyRegion? region,
    BodySide? side,
    String? segment,
    String? summary,
    List<RomFinding>? activeRom,
    List<RomFinding>? passiveRom,
    List<StrengthFinding>? strength,
    List<NeuroFinding>? neuro,
    List<JointMobilityFinding>? jointMobility,
    List<PalpationFinding>? palpation,
    List<ClinicalTestFinding>? clinicalTests,
  }) {
    return RegionObjective(
      region: region ?? this.region,
      side: side ?? this.side,
      segment: segment ?? this.segment,
      summary: summary ?? this.summary,
      activeRom: activeRom ?? this.activeRom,
      passiveRom: passiveRom ?? this.passiveRom,
      strength: strength ?? this.strength,
      neuro: neuro ?? this.neuro,
      jointMobility: jointMobility ?? this.jointMobility,
      palpation: palpation ?? this.palpation,
      clinicalTests: clinicalTests ?? this.clinicalTests,
    );
  }

  Map<String, dynamic> toJson() => {
        'region': region.name,
        'side': side.name,
        'segment': segment,
        'summary': summary,
        'activeRom': activeRom.map((e) => e.toJson()).toList(),
        'passiveRom': passiveRom.map((e) => e.toJson()).toList(),
        'strength': strength.map((e) => e.toJson()).toList(),
        'neuro': neuro.map((e) => e.toJson()).toList(),
        'jointMobility': jointMobility.map((e) => e.toJson()).toList(),
        'palpation': palpation.map((e) => e.toJson()).toList(),
        'clinicalTests': clinicalTests.map((e) => e.toJson()).toList(),
      };

  factory RegionObjective.fromJson(Map<String, dynamic> json) =>
      RegionObjective(
        region: BodyRegion.values.firstWhere(
          (v) => v.name == json['region'],
          orElse: () => BodyRegion.cervical,
        ),
        side: BodySide.values.firstWhere(
          (v) => v.name == (json['side'] ?? 'central'),
          orElse: () => BodySide.central,
        ),
        segment: json['segment'] as String?,
        summary: json['summary'] as String?,
        activeRom: (json['activeRom'] as List<dynamic>? ?? [])
            .map((e) => RomFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        passiveRom: (json['passiveRom'] as List<dynamic>? ?? [])
            .map((e) => RomFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        strength: (json['strength'] as List<dynamic>? ?? [])
            .map((e) => StrengthFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        neuro: (json['neuro'] as List<dynamic>? ?? [])
            .map((e) => NeuroFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        jointMobility: (json['jointMobility'] as List<dynamic>? ?? [])
            .map((e) =>
                JointMobilityFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        palpation: (json['palpation'] as List<dynamic>? ?? [])
            .map((e) => PalpationFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        clinicalTests: (json['clinicalTests'] as List<dynamic>? ?? [])
            .map(
                (e) => ClinicalTestFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// --- Objective sub-findings ---------------------------------------------------

/// Unit for ROM value: degrees or percentage.
enum RomValueUnit { deg, pct }

@immutable
class RomFinding {
  final String movement; // e.g. "Flexion"
  final double? value; // degrees or percentage (see valueUnit) – list input only
  final RomValueUnit valueUnit; // deg or pct – list input only
  /// Diagram-only ROM (0..max scale); independent of value/valueUnit. List ignores this.
  final double? diagramValue;
  final bool painful;
  /// ROM value (degrees) at which pain is felt; legacy single point.
  final double? painAt;
  /// Pain segment along movement: from (0..max) to (0..max). Diagram draws red between these.
  final double? painFrom;
  final double? painTo;
  final bool reproducesMainSymptoms;
  final String? notes;

  const RomFinding({
    required this.movement,
    this.value,
    this.valueUnit = RomValueUnit.deg,
    this.diagramValue,
    this.painful = false,
    this.painAt,
    this.painFrom,
    this.painTo,
    this.reproducesMainSymptoms = false,
    this.notes,
  });

  RomFinding copyWith({
    String? movement,
    double? value,
    RomValueUnit? valueUnit,
    double? diagramValue,
    bool? painful,
    double? painAt,
    double? painFrom,
    double? painTo,
    bool? reproducesMainSymptoms,
    String? notes,
  }) {
    return RomFinding(
      movement: movement ?? this.movement,
      value: value ?? this.value,
      valueUnit: valueUnit ?? this.valueUnit,
      diagramValue: diagramValue ?? this.diagramValue,
      painful: painful ?? this.painful,
      painAt: painAt ?? this.painAt,
      painFrom: painFrom ?? this.painFrom,
      painTo: painTo ?? this.painTo,
      reproducesMainSymptoms:
          reproducesMainSymptoms ?? this.reproducesMainSymptoms,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'movement': movement,
        'value': value,
        'valueUnit': valueUnit.name,
        'diagramValue': diagramValue,
        'painful': painful,
        'painAt': painAt,
        'painFrom': painFrom,
        'painTo': painTo,
        'reproducesMainSymptoms': reproducesMainSymptoms,
        'notes': notes,
      };

  factory RomFinding.fromJson(Map<String, dynamic> json) {
    final painAt = (json['painAt'] as num?)?.toDouble();
    final painFrom = (json['painFrom'] as num?)?.toDouble();
    final painTo = (json['painTo'] as num?)?.toDouble();
    return RomFinding(
      movement: json['movement'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble(),
      valueUnit: RomValueUnit.values.firstWhere(
        (e) => e.name == (json['valueUnit'] ?? 'deg'),
        orElse: () => RomValueUnit.deg,
      ),
      diagramValue: (json['diagramValue'] as num?)?.toDouble(),
      painful: (json['painful'] ?? false) as bool,
      painAt: painAt,
      painFrom: painFrom ?? (painAt != null ? painAt : null),
      painTo: painTo ?? (painAt != null ? painAt : null),
      reproducesMainSymptoms:
          (json['reproducesMainSymptoms'] ?? false) as bool,
      notes: json['notes'] as String?,
    );
  }
}

@immutable
class StrengthFinding {
  final String movementOrMyotome; // e.g. "C5 abduction"
  final int grade; // 0-5
  final bool painful;
  final String? notes;

  const StrengthFinding({
    required this.movementOrMyotome,
    this.grade = 5,
    this.painful = false,
    this.notes,
  });

  StrengthFinding copyWith({
    String? movementOrMyotome,
    int? grade,
    bool? painful,
    String? notes,
  }) {
    return StrengthFinding(
      movementOrMyotome: movementOrMyotome ?? this.movementOrMyotome,
      grade: grade ?? this.grade,
      painful: painful ?? this.painful,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'movementOrMyotome': movementOrMyotome,
        'grade': grade,
        'painful': painful,
        'notes': notes,
      };

  factory StrengthFinding.fromJson(Map<String, dynamic> json) =>
      StrengthFinding(
        movementOrMyotome: json['movementOrMyotome'] as String? ?? '',
        grade: (json['grade'] ?? 5) as int,
        painful: (json['painful'] ?? false) as bool,
        notes: json['notes'] as String?,
      );
}

@immutable
class NeuroFinding {
  final String structure; // e.g. "Dermatome C6", "ULNT1"
  final String status; // e.g. "normal", "reduced", "absent", "positive"
  final String? notes;

  const NeuroFinding({
    required this.structure,
    required this.status,
    this.notes,
  });

  NeuroFinding copyWith({
    String? structure,
    String? status,
    String? notes,
  }) {
    return NeuroFinding(
      structure: structure ?? this.structure,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'structure': structure,
        'status': status,
        'notes': notes,
      };

  factory NeuroFinding.fromJson(Map<String, dynamic> json) => NeuroFinding(
        structure: json['structure'] as String? ?? '',
        status: json['status'] as String? ?? 'normal',
        notes: json['notes'] as String?,
      );
}

@immutable
class JointMobilityFinding {
  final String level; // e.g. "C4-5"
  final String mobility; // "hypo", "normal", "hyper"
  final bool reproducesSymptoms;
  final String? notes;

  const JointMobilityFinding({
    required this.level,
    required this.mobility,
    this.reproducesSymptoms = false,
    this.notes,
  });

  JointMobilityFinding copyWith({
    String? level,
    String? mobility,
    bool? reproducesSymptoms,
    String? notes,
  }) {
    return JointMobilityFinding(
      level: level ?? this.level,
      mobility: mobility ?? this.mobility,
      reproducesSymptoms: reproducesSymptoms ?? this.reproducesSymptoms,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level,
        'mobility': mobility,
        'reproducesSymptoms': reproducesSymptoms,
        'notes': notes,
      };

  factory JointMobilityFinding.fromJson(Map<String, dynamic> json) =>
      JointMobilityFinding(
        level: json['level'] as String? ?? '',
        mobility: json['mobility'] as String? ?? 'normal',
        reproducesSymptoms: (json['reproducesSymptoms'] ?? false) as bool,
        notes: json['notes'] as String?,
      );
}

@immutable
class PalpationFinding {
  final String location;
  final String? quality; // e.g. "tender", "spasm", "heat"
  final String? notes;

  const PalpationFinding({
    required this.location,
    this.quality,
    this.notes,
  });

  PalpationFinding copyWith({
    String? location,
    String? quality,
    String? notes,
  }) {
    return PalpationFinding(
      location: location ?? this.location,
      quality: quality ?? this.quality,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'location': location,
        'quality': quality,
        'notes': notes,
      };

  factory PalpationFinding.fromJson(Map<String, dynamic> json) =>
      PalpationFinding(
        location: json['location'] as String? ?? '',
        quality: json['quality'] as String?,
        notes: json['notes'] as String?,
      );
}

@immutable
class ClinicalTestFinding {
  /// ID from your clinical_tests registry (this is the key that joins them).
  final String testId;

  final ClinicalTestResult result;
  final bool reproducesMainSymptoms;
  final String? notes;

  const ClinicalTestFinding({
    required this.testId,
    this.result = ClinicalTestResult.notTested,
    this.reproducesMainSymptoms = false,
    this.notes,
  });

  ClinicalTestFinding copyWith({
    String? testId,
    ClinicalTestResult? result,
    bool? reproducesMainSymptoms,
    String? notes,
  }) {
    return ClinicalTestFinding(
      testId: testId ?? this.testId,
      result: result ?? this.result,
      reproducesMainSymptoms:
          reproducesMainSymptoms ?? this.reproducesMainSymptoms,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'result': result.name,
        'reproducesMainSymptoms': reproducesMainSymptoms,
        'notes': notes,
      };

  factory ClinicalTestFinding.fromJson(Map<String, dynamic> json) =>
      ClinicalTestFinding(
        testId: json['testId'] as String? ?? '',
        result: ClinicalTestResult.values.firstWhere(
          (v) => v.name == (json['result'] ?? 'notTested'),
          orElse: () => ClinicalTestResult.notTested,
        ),
        reproducesMainSymptoms:
            (json['reproducesMainSymptoms'] ?? false) as bool,
        notes: json['notes'] as String?,
      );
}

// -----------------------------------------------------------------------------
// Analysis
// -----------------------------------------------------------------------------

@immutable
class AnalysisSection {
  final String primaryDiagnosis;
  final List<String> secondaryDiagnoses;
  final List<String> keyImpairments;

  final List<PainMechanism> painMechanisms;

  /// Free-text summary used by the "Assessment" tab.
  final String? summary;

  /// Clinical reasoning narrative.
  final String? reasoningSummary;

  /// Free-text contributing factors paragraph (biopsychosocial, load, etc.).
  final String? contributingFactorsText;

  /// Any explicit risk/benefit discussion for manual therapy.
  final String? manualTherapyRiskBenefit;

  final TernaryLevel prognosis;

  /// Optional recommendations / next-steps paragraph.
  final String? recommendations;

  const AnalysisSection({
    this.primaryDiagnosis = '',
    this.secondaryDiagnoses = const [],
    this.keyImpairments = const [],
    this.painMechanisms = const [],
    this.summary,
    this.reasoningSummary,
    this.contributingFactorsText,
    this.manualTherapyRiskBenefit,
    this.prognosis = TernaryLevel.moderate,
    this.recommendations,
  });

  AnalysisSection copyWith({
    String? primaryDiagnosis,
    List<String>? secondaryDiagnoses,
    List<String>? keyImpairments,
    List<PainMechanism>? painMechanisms,
    String? summary,
    String? reasoningSummary,
    String? contributingFactorsText,
    String? manualTherapyRiskBenefit,
    TernaryLevel? prognosis,
    String? recommendations,
  }) {
    return AnalysisSection(
      primaryDiagnosis: primaryDiagnosis ?? this.primaryDiagnosis,
      secondaryDiagnoses: secondaryDiagnoses ?? this.secondaryDiagnoses,
      keyImpairments: keyImpairments ?? this.keyImpairments,
      painMechanisms: painMechanisms ?? this.painMechanisms,
      summary: summary ?? this.summary,
      reasoningSummary: reasoningSummary ?? this.reasoningSummary,
      contributingFactorsText:
          contributingFactorsText ?? this.contributingFactorsText,
      manualTherapyRiskBenefit:
          manualTherapyRiskBenefit ?? this.manualTherapyRiskBenefit,
      prognosis: prognosis ?? this.prognosis,
      recommendations: recommendations ?? this.recommendations,
    );
  }

  Map<String, dynamic> toJson() => {
        'primaryDiagnosis': primaryDiagnosis,
        'secondaryDiagnoses': secondaryDiagnoses,
        'keyImpairments': keyImpairments,
        'painMechanisms': painMechanisms.map((e) => e.name).toList(),
        'summary': summary,
        'reasoningSummary': reasoningSummary,
        'contributingFactorsText': contributingFactorsText,
        'manualTherapyRiskBenefit': manualTherapyRiskBenefit,
        'prognosis': prognosis.name,
        'recommendations': recommendations,
      };

  factory AnalysisSection.fromJson(Map<String, dynamic> json) =>
      AnalysisSection(
        primaryDiagnosis: (json['primaryDiagnosis'] ?? '') as String,
        secondaryDiagnoses:
            (json['secondaryDiagnoses'] as List<dynamic>? ?? [])
                .map((e) => e as String)
                .toList(),
        keyImpairments: (json['keyImpairments'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        painMechanisms: (json['painMechanisms'] as List<dynamic>? ?? [])
            .map(
              (e) => PainMechanism.values.firstWhere(
                (v) => v.name == e,
                orElse: () => PainMechanism.uncertain,
              ),
            )
            .toList(),
        summary: json['summary'] as String?,
        reasoningSummary: json['reasoningSummary'] as String?,
        contributingFactorsText:
            json['contributingFactorsText'] as String?,
        manualTherapyRiskBenefit:
            json['manualTherapyRiskBenefit'] as String?,
        prognosis: TernaryLevel.values.firstWhere(
          (v) => v.name == (json['prognosis'] ?? 'moderate'),
          orElse: () => TernaryLevel.moderate,
        ),
        recommendations: json['recommendations'] as String?,
      );
}

// -----------------------------------------------------------------------------
// Plan
// -----------------------------------------------------------------------------

@immutable
class PlanSection {
  final List<GoalItem> shortTermGoals;
  final List<GoalItem> longTermGoals;
  final List<InterventionItem> plannedInterventions;

  /// Education / advice given this session.
  final String? educationAdvice;

  /// Explicit safety-netting advice (red-flag return instructions).
  final String? safetyNettingAdvice;

  /// When you'd like to review the patient.
  final DateTime? nextReviewDate;

  // ---- Extra fields to match current Plan tab UI ----

  /// Free-text "Treatment today" field.
  final String? treatmentToday;

  /// Free-text home exercise programme description.
  final String? homeExercise;

  /// Brief follow-up plan (e.g. "Review in 1 week").
  final String? followUpPlan;

  /// Any extra "other plan / referrals / investigations".
  final String? otherPlan;

  /// Short-term plan narrative (IFOMPT style).
  final String? planShortTermSummary;

  /// Medium-term plan narrative.
  final String? planMediumTermSummary;

  /// Outcome measures you plan to use / repeat.
  final String? outcomeMeasuresPlanned;

  /// Contingency plan if things deteriorate or don't progress.
  final String? contingencyPlan;

  const PlanSection({
    this.shortTermGoals = const [],
    this.longTermGoals = const [],
    this.plannedInterventions = const [],
    this.educationAdvice,
    this.safetyNettingAdvice,
    this.nextReviewDate,
    this.treatmentToday,
    this.homeExercise,
    this.followUpPlan,
    this.otherPlan,
    this.planShortTermSummary,
    this.planMediumTermSummary,
    this.outcomeMeasuresPlanned,
    this.contingencyPlan,
  });

  PlanSection copyWith({
    List<GoalItem>? shortTermGoals,
    List<GoalItem>? longTermGoals,
    List<InterventionItem>? plannedInterventions,
    String? educationAdvice,
    String? safetyNettingAdvice,
    DateTime? nextReviewDate,
    String? treatmentToday,
    String? homeExercise,
    String? followUpPlan,
    String? otherPlan,
    String? planShortTermSummary,
    String? planMediumTermSummary,
    String? outcomeMeasuresPlanned,
    String? contingencyPlan,
  }) {
    return PlanSection(
      shortTermGoals: shortTermGoals ?? this.shortTermGoals,
      longTermGoals: longTermGoals ?? this.longTermGoals,
      plannedInterventions: plannedInterventions ?? this.plannedInterventions,
      educationAdvice: educationAdvice ?? this.educationAdvice,
      safetyNettingAdvice: safetyNettingAdvice ?? this.safetyNettingAdvice,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      treatmentToday: treatmentToday ?? this.treatmentToday,
      homeExercise: homeExercise ?? this.homeExercise,
      followUpPlan: followUpPlan ?? this.followUpPlan,
      otherPlan: otherPlan ?? this.otherPlan,
      planShortTermSummary:
          planShortTermSummary ?? this.planShortTermSummary,
      planMediumTermSummary:
          planMediumTermSummary ?? this.planMediumTermSummary,
      outcomeMeasuresPlanned:
          outcomeMeasuresPlanned ?? this.outcomeMeasuresPlanned,
      contingencyPlan: contingencyPlan ?? this.contingencyPlan,
    );
  }

  Map<String, dynamic> toJson() => {
        'shortTermGoals': shortTermGoals.map((e) => e.toJson()).toList(),
        'longTermGoals': longTermGoals.map((e) => e.toJson()).toList(),
        'plannedInterventions':
            plannedInterventions.map((e) => e.toJson()).toList(),
        'educationAdvice': educationAdvice,
        'safetyNettingAdvice': safetyNettingAdvice,
        'nextReviewDate': nextReviewDate?.toIso8601String(),
        'treatmentToday': treatmentToday,
        'homeExercise': homeExercise,
        'followUpPlan': followUpPlan,
        'otherPlan': otherPlan,
        'planShortTermSummary': planShortTermSummary,
        'planMediumTermSummary': planMediumTermSummary,
        'outcomeMeasuresPlanned': outcomeMeasuresPlanned,
        'contingencyPlan': contingencyPlan,
      };

  factory PlanSection.fromJson(Map<String, dynamic> json) => PlanSection(
        shortTermGoals: (json['shortTermGoals'] as List<dynamic>? ?? [])
            .map((e) => GoalItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        longTermGoals: (json['longTermGoals'] as List<dynamic>? ?? [])
            .map((e) => GoalItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        plannedInterventions:
            (json['plannedInterventions'] as List<dynamic>? ?? [])
                .map(
                    (e) => InterventionItem.fromJson(e as Map<String, dynamic>))
                .toList(),
        educationAdvice: json['educationAdvice'] as String?,
        safetyNettingAdvice: json['safetyNettingAdvice'] as String?,
        nextReviewDate: json['nextReviewDate'] != null
            ? DateTime.parse(json['nextReviewDate'] as String)
            : null,
        treatmentToday: json['treatmentToday'] as String?,
        homeExercise: json['homeExercise'] as String?,
        followUpPlan: json['followUpPlan'] as String?,
        otherPlan: json['otherPlan'] as String?,
        planShortTermSummary: json['planShortTermSummary'] as String?,
        planMediumTermSummary: json['planMediumTermSummary'] as String?,
        outcomeMeasuresPlanned:
            json['outcomeMeasuresPlanned'] as String?,
        contingencyPlan: json['contingencyPlan'] as String?,
      );
}
