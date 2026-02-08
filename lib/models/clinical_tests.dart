// lib/models/clinical_tests.dart
//
// Research-grade clinical test registry with metadata and (optional)
// diagnostic accuracy values. Designed for:
//  - Dropdown selection by body region
//  - Structured storage (Firestore / JSON)
//  - AI-powered extraction (using test `id`)
//  - PDF export summaries

import 'dart:convert';

/// Regions you care about in the app.
enum BodyRegion {
  cervical,
  thoracic,
  lumbar,
  shoulder,
  elbow,
  wristHand,
  hip,
  knee,
  ankleFoot,
  other, // 👈 added to match SoapNote + allow generic tests
}

/// Broad purpose/category of the clinical test.
enum TestCategory {
  neural,
  ligament,
  meniscus,
  labrum,
  tendon,
  muscle,
  instability,
  jointMobility,
  provocation, // pain provocation / pathology provocation
  functional,
  posture,
  vascular,
  other,
}

/// Rough evidence “grade” – not a formal GRADE rating, just a quick flag.
enum EvidenceLevel {
  high,
  moderate,
  low,
  veryLow,
  unknown,
}

/// Definition for one named clinical test.
class ClinicalTestDefinition {
  final String id; // stable key used in DB & AI
  final String name; // display name
  final List<String> synonyms; // alternative names / spellings
  final BodyRegion region;
  final TestCategory category;

  /// Primary tissues being biased or stressed (ligament, nerve, labrum…).
  final List<String> primaryStructures;

  /// Short clinical description of what the test is trying to detect.
  final String purpose;

  /// Diagnostic accuracy – optional, can be null if unknown or mixed.
  /// Values are typically proportions from 0.0 – 1.0 based on pooled data.
  final double? sensitivity;
  final double? specificity;
  final double? lrPositive;
  final double? lrNegative;

  final EvidenceLevel evidenceLevel;

  /// Short reference string (e.g. “Majlesi 2008 J Clin Rheumatol”).
  final String? keyReference;

  /// Should this appear at the top of dropdowns for this region?
  final bool isCommon;

  const ClinicalTestDefinition({
    required this.id,
    required this.name,
    required this.synonyms,
    required this.region,
    required this.category,
    required this.primaryStructures,
    required this.purpose,
    this.sensitivity,
    this.specificity,
    this.lrPositive,
    this.lrNegative,
    this.evidenceLevel = EvidenceLevel.unknown,
    this.keyReference,
    this.isCommon = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'synonyms': synonyms,
        'region': region.name,
        'category': category.name,
        'primaryStructures': primaryStructures,
        'purpose': purpose,
        'sensitivity': sensitivity,
        'specificity': specificity,
        'lrPositive': lrPositive,
        'lrNegative': lrNegative,
        'evidenceLevel': evidenceLevel.name,
        'keyReference': keyReference,
        'isCommon': isCommon,
      };

  factory ClinicalTestDefinition.fromJson(Map<String, dynamic> json) {
    return ClinicalTestDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      synonyms:
          (json['synonyms'] as List<dynamic>? ?? const []).cast<String>(),
      region: BodyRegion.values
          .firstWhere((e) => e.name == json['region'] as String),
      category: TestCategory.values
          .firstWhere((e) => e.name == json['category'] as String),
      primaryStructures:
          (json['primaryStructures'] as List<dynamic>? ?? const [])
              .cast<String>(),
      purpose: json['purpose'] as String? ?? '',
      sensitivity: (json['sensitivity'] as num?)?.toDouble(),
      specificity: (json['specificity'] as num?)?.toDouble(),
      lrPositive: (json['lrPositive'] as num?)?.toDouble(),
      lrNegative: (json['lrNegative'] as num?)?.toDouble(),
      evidenceLevel: EvidenceLevel.values.firstWhere(
        (e) => e.name == (json['evidenceLevel'] as String? ?? 'unknown'),
        orElse: () => EvidenceLevel.unknown,
      ),
      keyReference: json['keyReference'] as String?,
      isCommon: json['isCommon'] as bool? ?? false,
    );
  }

  /// Optional helpers if you ever want to ship lists of definitions
  /// to the AI or store them as a blob.
  static String listToRawJson(List<ClinicalTestDefinition> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ClinicalTestDefinition> listFromRawJson(String source) {
    final data = jsonDecode(source) as List<dynamic>;
    return data
        .map((e) => ClinicalTestDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Registry holding all tests & helpers for querying by region / id.
class ClinicalTestRegistry {
  ClinicalTestRegistry._internal();

  /// Global singleton instance so UI can call:
  /// ClinicalTestRegistry.instance.testsForRegion(region)
  static final ClinicalTestRegistry instance =
      ClinicalTestRegistry._internal();

  /// Backing store for tests (shared).
  static final List<ClinicalTestDefinition> _allTests = [
    // ------------------------------------------------------------
    // CERVICAL SPINE
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'cervical_spurling',
      name: 'Spurling Test',
      synonyms: ['Foraminal Compression Test'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['cervical nerve root', 'intervertebral foramen'],
      purpose: 'Provocation test for cervical radiculopathy by narrowing the '
          'foramen with extension, side flexion and axial compression.',
      sensitivity: null,
      specificity: null,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Various radiculopathy diagnostic studies',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_distraction',
      name: 'Cervical Distraction Test',
      synonyms: ['Neck Distraction Test'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['cervical nerve roots', 'facet joints'],
      purpose:
          'Symptom relief test for radiculopathy – reduction of arm symptoms '
          'with manual traction suggests nerve root involvement.',
      sensitivity: null,
      specificity: null,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Commonly used in radiculopathy test clusters',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_sharp_purser',
      name: 'Sharp–Purser Test',
      synonyms: ['Transverse Ligament Test'],
      region: BodyRegion.cervical,
      category: TestCategory.instability,
      primaryStructures: ['transverse ligament', 'C1–C2 complex'],
      purpose:
          'Assesses atlantoaxial instability due to transverse ligament '
          'insufficiency; relocation “clunk” and symptom change are key.',
      sensitivity: null,
      specificity: null,
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Cook 2005; IFOMPT cervical framework',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_alar_ligament',
      name: 'Alar Ligament Stress Test',
      synonyms: ['Alar Ligament Rotation Test', 'Side-Bend Alar Test'],
      region: BodyRegion.cervical,
      category: TestCategory.instability,
      primaryStructures: ['alar ligaments', 'C0–C2 complex'],
      purpose:
          'Assesses integrity of the alar ligaments by checking coupled motion '
          'between C2 and the occiput during rotation/side-bend.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Cook 2005; IFOMPT cervical framework',
    ),
    ClinicalTestDefinition(
      id: 'cervical_flexion_rotation',
      name: 'Flexion–Rotation Test (C1–C2)',
      synonyms: ['C1–C2 Rotation Test'],
      region: BodyRegion.cervical,
      category: TestCategory.jointMobility,
      primaryStructures: ['C1–C2 facet joints', 'upper cervical spine'],
      purpose:
          'Measures C1–C2 rotation range; commonly used for cervicogenic '
          'headache assessment and upper cervical dysfunction.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Dvorak 1987; Panjabi et al. 1988',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_ccft',
      name: 'Craniocervical Flexion Test',
      synonyms: ['Deep Neck Flexor Test', 'CCFT'],
      region: BodyRegion.cervical,
      category: TestCategory.functional,
      primaryStructures: ['longus colli', 'deep neck flexors'],
      purpose:
          'Assesses deep cervical flexor activation and endurance using a '
          'pressure biofeedback unit, often in neck pain and headache.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Jull et al. 2008',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_dnflexor_endurance',
      name: 'Deep Neck Flexor Endurance Test',
      synonyms: ['DNF Endurance'],
      region: BodyRegion.cervical,
      category: TestCategory.functional,
      primaryStructures: ['deep neck flexors'],
      purpose:
          'Measures endurance of the deep cervical flexors in supine head hold.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Grimmer 1994; neck pain endurance studies',
    ),
    ClinicalTestDefinition(
      id: 'cervical_ultt1',
      name: 'ULNT1 – Median Nerve Bias',
      synonyms: ['Upper Limb Tension Test 1', 'Median ULTT'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['median nerve', 'C5–T1 nerve roots'],
      purpose:
          'Neurodynamic provocation test for median nerve/neurodynamic '
          'mechanosensitivity, often used in the radiculopathy cluster.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Butler 1991; Shacklock 2005',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_ultt_radial',
      name: 'ULNT – Radial Nerve Bias',
      synonyms: ['ULNT2b', 'Radial ULTT'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['radial nerve', 'C5–T1 nerve roots'],
      purpose:
          'Neurodynamic provocation test stressing radial nerve structures.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Butler 1991; Shacklock 2005',
    ),
    ClinicalTestDefinition(
      id: 'cervical_ultt_ulnar',
      name: 'ULNT – Ulnar Nerve Bias',
      synonyms: ['ULNT3', 'Ulnar ULTT'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['ulnar nerve', 'C7–T1 nerve roots'],
      purpose:
          'Neurodynamic provocation test stressing ulnar nerve structures.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Butler 1991; Shacklock 2005',
    ),

    // ------------------------------------------------------------
    // THORACIC SPINE
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'thoracic_pa_springing',
      name: 'Thoracic PA Springing',
      synonyms: ['Thoracic PAIVMs'],
      region: BodyRegion.thoracic,
      category: TestCategory.jointMobility,
      primaryStructures: ['thoracic zygapophyseal joints', 'ribs'],
      purpose:
          'Assesses segmental mobility and symptom provocation with PA '
          'springing over thoracic spinous processes.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Maitland manual therapy concepts',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'thoracic_rotation_sitting',
      name: 'Thoracic Rotation in Sitting',
      synonyms: ['Seated Thoracic Rotation'],
      region: BodyRegion.thoracic,
      category: TestCategory.functional,
      primaryStructures: ['thoracic spine', 'ribs'],
      purpose:
          'Functional rotation ROM assessment, often used for neck/shoulder '
          'or rib pain differentials.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Common manual therapy practice',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'thoracic_rib_spring',
      name: 'Rib Springing Test',
      synonyms: ['Costovertebral Springing'],
      region: BodyRegion.thoracic,
      category: TestCategory.jointMobility,
      primaryStructures: ['costovertebral joints', 'costotransverse joints'],
      purpose:
          'Assesses rib joint mobility and pain provocation, often for rib '
          'dysfunction and thoracic pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Manual therapy rib assessment',
    ),
    ClinicalTestDefinition(
      id: 'thoracic_slump',
      name: 'Thoracic Slump (Upper Thoracic Bias)',
      synonyms: ['Slump with thoracic emphasis'],
      region: BodyRegion.thoracic,
      category: TestCategory.neural,
      primaryStructures: ['thoracic nerve roots', 'dural system'],
      purpose:
          'Seated neural provocation test incorporating thoracic flexion for '
          'upper thoracic neural symptoms.',
      evidenceLevel: EvidenceLevel.veryLow,
      keyReference: 'Adaptation of classic Slump test',
    ),

    // ------------------------------------------------------------
    // LUMBAR SPINE & SIJ
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'lumbar_slump',
      name: 'Slump Test',
      synonyms: ['Seated Slump'],
      region: BodyRegion.lumbar,
      category: TestCategory.neural,
      primaryStructures: ['lumbosacral nerve roots', 'dural system'],
      purpose:
          'Seated neurodynamic test for lumbar disc herniation / radiculopathy.',
      sensitivity: 0.84,
      specificity: 0.83,
      lrPositive: null,
      lrNegative: null,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Majlesi 2008 J Clin Rheumatol',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'lumbar_slr',
      name: 'Straight Leg Raise (SLR)',
      synonyms: ['Lasègue Test', 'Straight Leg Raising'],
      region: BodyRegion.lumbar,
      category: TestCategory.neural,
      primaryStructures: ['sciatic nerve', 'L4–S1 nerve roots'],
      purpose:
          'Supine neurodynamic test for lumbar disc herniation and nerve root '
          'irritation.',
      sensitivity: 0.91,
      specificity: 0.26,
      lrPositive: 0.35,
      lrNegative: 1.2,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Lasègue meta-analysis; Majlesi 2008',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'lumbar_cross_slr',
      name: 'Crossed Straight Leg Raise',
      synonyms: ['Contralateral SLR'],
      region: BodyRegion.lumbar,
      category: TestCategory.neural,
      primaryStructures: ['sciatic nerve', 'contralateral nerve root'],
      purpose:
          'Provocative test where lifting the asymptomatic leg reproduces '
          'symptoms in the affected leg; more specific for disc herniation.',
      sensitivity: 0.29,
      specificity: 0.88,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Lasègue meta-analysis values',
    ),
    ClinicalTestDefinition(
      id: 'lumbar_prone_knee_bend',
      name: 'Prone Knee Bend',
      synonyms: ['Femoral Nerve Stretch', 'PKB'],
      region: BodyRegion.lumbar,
      category: TestCategory.neural,
      primaryStructures: ['femoral nerve', 'L2–L4 nerve roots'],
      purpose:
          'Prone neurodynamic test stressing femoral nerve and upper lumbar '
          'nerve roots.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Neurodynamic testing for upper lumbar radiculopathy',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'lumbar_prone_instability',
      name: 'Prone Instability Test',
      synonyms: ['Lumbar Instability Test'],
      region: BodyRegion.lumbar,
      category: TestCategory.instability,
      primaryStructures: ['lumbar segments', 'passive restraints'],
      purpose:
          'Checks for symptomatic lumbar segmental instability; reduction of '
          'pain with active extension suggests instability.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hicks et al. instability prediction rules',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'lumbar_quadrant',
      name: 'Lumbar Quadrant Test',
      synonyms: ['Kemp’s Test'],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['facet joints', 'foramina', 'disc'],
      purpose:
          'Extension–rotation provocation of lumbar facets and foramina; often '
          'used in facet-related pain assessment.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Facet joint provocation literature',
    ),
    // SIJ cluster – documented individually so you can record each result
    ClinicalTestDefinition(
      id: 'sij_distraction',
      name: 'SIJ Distraction Test',
      synonyms: ['Gapping Test'],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['sacroiliac joint', 'anterior SI ligaments'],
      purpose:
          'Stresses anterior SI ligaments; part of pain provocation test cluster '
          'for SIJ-related pain.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Laslett SIJ pain cluster',
    ),
    ClinicalTestDefinition(
      id: 'sij_compression',
      name: 'SIJ Compression Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['sacroiliac joint', 'posterior SI ligaments'],
      purpose:
          'Compresses SI joint structures; part of Laslett SIJ pain cluster.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Laslett SIJ pain cluster',
    ),
    ClinicalTestDefinition(
      id: 'sij_thigh_thrust',
      name: 'Thigh Thrust Test',
      synonyms: ['Posterior Shear Test'],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['SIJ', 'posterior ligaments'],
      purpose:
          'Posterior shear stress through femur into SIJ; sensitive for SIJ pain '
          'as part of cluster.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Laslett SIJ pain cluster',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'sij_sacral_thrust',
      name: 'Sacral Thrust Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['sacroiliac joint'],
      purpose:
          'PA force over sacrum provoking SIJ-related symptoms as part of '
          'cluster.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Laslett SIJ pain cluster',
    ),
    ClinicalTestDefinition(
      id: 'sij_gaenslen',
      name: 'Gaenslen’s Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.provocation,
      primaryStructures: ['SIJ', 'hip'],
      purpose:
          'Provocative test combining hip flexion and extension to stress SIJ.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Laslett SIJ pain cluster',
    ),

    // ------------------------------------------------------------
    // SHOULDER
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'shoulder_hawkins_kennedy',
      name: 'Hawkins–Kennedy Test',
      synonyms: ['Hawkins Test'],
      region: BodyRegion.shoulder,
      category: TestCategory.provocation,
      primaryStructures: ['subacromial space', 'rotator cuff tendons'],
      purpose:
          'Passive elevation in scapular plane with internal rotation to provoke '
          'subacromial impingement.',
      sensitivity: 0.79,
      specificity: 0.59,
      lrPositive: 1.9,
      lrNegative: 0.36,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hegedus 2012; Kelly 2010; Alqunaee 2012',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_neer',
      name: 'Neer Impingement Test',
      synonyms: ['Neer Sign'],
      region: BodyRegion.shoulder,
      category: TestCategory.provocation,
      primaryStructures: ['subacromial space', 'rotator cuff'],
      purpose:
          'Passive forward elevation in internal rotation to compress structures '
          'under the acromion.',
      sensitivity: 0.72,
      specificity: 0.60,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hegedus 2012 systematic review',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_painful_arc',
      name: 'Painful Arc Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.provocation,
      primaryStructures: ['subacromial space', 'rotator cuff'],
      purpose:
          'Active abduction assesses for pain between ~60–120° indicative of '
          'subacromial involvement.',
      sensitivity: 0.53,
      specificity: 0.76,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hegedus 2012 meta-analysis',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_empty_can',
      name: 'Empty Can (Jobe) Test',
      synonyms: ['Supraspinatus Test'],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['supraspinatus tendon'],
      purpose:
          'Resisted elevation in scapular plane with internal rotation to detect '
          'supraspinatus pathology.',
      sensitivity: 0.69,
      specificity: 0.62,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Alqunaee 2012; Hegedus 2012',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_drop_arm',
      name: 'Drop Arm Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['supraspinatus', 'rotator cuff'],
      purpose:
          'Assesses full-thickness cuff tears by inability to smoothly lower the arm.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Rotator cuff tear diagnostic studies',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_er_lag',
      name: 'External Rotation Lag Sign',
      synonyms: ['ER Lag Test'],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['supraspinatus', 'infraspinatus'],
      purpose:
          'Detects full-thickness tears of external rotators via inability to maintain '
          'passively placed ER position.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Rotator cuff tear diagnostic literature',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_lift_off',
      name: 'Lift-Off Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['subscapularis tendon'],
      purpose:
          'Detects subscapularis tear/dysfunction by ability to lift hand off back.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Subscapularis test literature',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_belly_press',
      name: 'Belly Press Test',
      synonyms: ['Napoleon Test'],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['subscapularis'],
      purpose:
          'Alternative to Lift-Off for limited IR; pressing into abdomen while '
          'maintaining elbow forward.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Subscapularis assessment studies',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_apprehension',
      name: 'Apprehension Test',
      synonyms: ['Crank Apprehension'],
      region: BodyRegion.shoulder,
      category: TestCategory.instability,
      primaryStructures: ['anterior capsule', 'labrum', 'GH ligaments'],
      purpose:
          'Provokes feelings of apprehension (not just pain) in abduction/ER '
          'as indicator of anterior instability.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Shoulder instability diagnostic literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_relocation',
      name: 'Relocation Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.instability,
      primaryStructures: ['anterior GH capsule'],
      purpose:
          'Posteriorly directed force in apprehension position; reduction in symptoms '
          'supports anterior instability diagnosis.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Shoulder instability investigation',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_sulcus_sign',
      name: 'Sulcus Sign',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.instability,
      primaryStructures: ['inferior capsule', 'GH ligaments'],
      purpose:
          'Assesses inferior/multidirectional laxity with traction causing sulcus under acromion.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Multidirectional instability descriptions',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_obriens',
      name: 'O’Brien’s Active Compression Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.labrum,
      primaryStructures: ['superior labrum', 'AC joint'],
      purpose:
          'Provokes pain with resisted forward flexion in IR vs ER; used for SLAP '
          'and AC joint assessment.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'SLAP lesion test literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'shoulder_biceps_load2',
      name: 'Biceps Load II',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.labrum,
      primaryStructures: ['superior labrum', 'biceps anchor'],
      purpose:
          'Supine abduction/ER with resisted elbow flexion to stress superior labrum.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'SLAP diagnostic studies',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_crank',
      name: 'Crank Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.labrum,
      primaryStructures: ['glenoid labrum'],
      purpose:
          'Axial load with rotation in elevation; provokes clicking/pain in labral pathology.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Labral lesion literature',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_speeds',
      name: 'Speed’s Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['long head of biceps tendon'],
      purpose:
          'Resisted forward flexion in supination; used for biceps and SLAP involvement.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Biceps/SLAP diagnostic accuracy review',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_cross_body_adduction',
      name: 'Cross-Body Adduction Test',
      synonyms: ['Scarf Test'],
      region: BodyRegion.shoulder,
      category: TestCategory.provocation,
      primaryStructures: ['AC joint'],
      purpose:
          'Horizontal adduction provokes AC joint pain; part of AC cluster.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'AC joint diagnostic cluster studies',
      isCommon: true,
    ),

    // ------------------------------------------------------------
    // ELBOW
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'elbow_cozens',
      name: 'Cozen’s Test',
      synonyms: ['Resisted Wrist Extension Test'],
      region: BodyRegion.elbow,
      category: TestCategory.tendon,
      primaryStructures: ['ECRB tendon', 'lateral epicondyle'],
      purpose:
          'Provokes pain at lateral epicondyle with resisted wrist extension; classic test '
          'for lateral epicondylalgia (tennis elbow).',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Lateral epicondylalgia clinical tests',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'elbow_mills',
      name: 'Mill’s Test',
      synonyms: [],
      region: BodyRegion.elbow,
      category: TestCategory.tendon,
      primaryStructures: ['wrist extensors', 'lateral epicondyle'],
      purpose:
          'Passive stretch of wrist extensors with elbow extension; provokes tennis elbow symptoms.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Lateral epicondylalgia assessment',
    ),
    ClinicalTestDefinition(
      id: 'elbow_maudsley',
      name: 'Maudsley’s Test',
      synonyms: ['Middle Finger Resistance Test'],
      region: BodyRegion.elbow,
      category: TestCategory.tendon,
      primaryStructures: ['ECRB', 'common extensor origin'],
      purpose:
          'Resisted middle finger extension stresses ECRB; used for lateral elbow pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Tennis elbow test descriptions',
    ),
    ClinicalTestDefinition(
      id: 'elbow_golfers',
      name: 'Golfer’s Elbow Test',
      synonyms: ['Medial Epicondylitis Test'],
      region: BodyRegion.elbow,
      category: TestCategory.tendon,
      primaryStructures: ['wrist flexor tendons', 'medial epicondyle'],
      purpose:
          'Passive wrist/finger extension with elbow extension provoking medial epicondyle pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Medial epicondylalgia descriptions',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'elbow_valgus_stress',
      name: 'Valgus Stress Test',
      synonyms: ['Elbow MCL Stress'],
      region: BodyRegion.elbow,
      category: TestCategory.ligament,
      primaryStructures: ['ulnar collateral ligament (MCL)'],
      purpose:
          'Applies valgus force at 0–30° flexion to assess MCL integrity.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Thrower’s elbow literature',
    ),
    ClinicalTestDefinition(
      id: 'elbow_moving_valgus',
      name: 'Moving Valgus Stress Test',
      synonyms: [],
      region: BodyRegion.elbow,
      category: TestCategory.ligament,
      primaryStructures: ['MCL complex'],
      purpose:
          'Dynamic valgus stress from flexion to extension; sensitive for MCL pathology in throwers.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'O’Driscoll moving valgus test study',
    ),
    ClinicalTestDefinition(
      id: 'elbow_tinel_cubital',
      name: 'Tinel’s Sign – Cubital Tunnel',
      synonyms: [],
      region: BodyRegion.elbow,
      category: TestCategory.neural,
      primaryStructures: ['ulnar nerve'],
      purpose:
          'Percussion over cubital tunnel reproduces paresthesia in ulnar distribution.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Cubital tunnel syndrome assessment',
      isCommon: true,
    ),

    // ------------------------------------------------------------
    // WRIST & HAND
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'wrist_phalens',
      name: 'Phalen’s Test',
      synonyms: ['Wrist Flexion Test'],
      region: BodyRegion.wristHand,
      category: TestCategory.neural,
      primaryStructures: ['median nerve', 'carpal tunnel'],
      purpose:
          'Sustained wrist flexion provokes carpal tunnel symptoms (median nerve).',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'CTS diagnostic accuracy studies',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'wrist_tinel_median',
      name: 'Tinel’s Sign – Wrist',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.neural,
      primaryStructures: ['median nerve'],
      purpose:
          'Percussion at carpal tunnel reproduces paresthesia in median nerve distribution.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'CTS diagnostic cluster studies',
    ),
    ClinicalTestDefinition(
      id: 'wrist_durkan',
      name: 'Durkan’s Compression Test',
      synonyms: ['Carpal Compression Test'],
      region: BodyRegion.wristHand,
      category: TestCategory.neural,
      primaryStructures: ['median nerve'],
      purpose:
          'Direct compression over carpal tunnel; often more sensitive for CTS than Tinel.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Durkan original CTS study',
    ),
    ClinicalTestDefinition(
      id: 'wrist_finkelstein',
      name: 'Finkelstein’s Test',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.tendon,
      primaryStructures: ['APL', 'EPB', 'first dorsal compartment'],
      purpose:
          'Ulnar deviation with thumb in fist provokes pain in de Quervain’s tenosynovitis.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'De Quervain’s test literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'wrist_watson',
      name: 'Watson’s Test',
      synonyms: ['Scaphoid Shift Test'],
      region: BodyRegion.wristHand,
      category: TestCategory.instability,
      primaryStructures: ['scapholunate ligament', 'scaphoid'],
      purpose:
          'Dorsal pressure on scaphoid with radial–ulnar deviation demonstrates clunk/pain in SL instability.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Scapholunate instability assessment',
    ),
    ClinicalTestDefinition(
      id: 'wrist_tfcc_load',
      name: 'TFCC Load Test',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.provocation,
      primaryStructures: ['TFCC', 'ulnocarpal joint'],
      purpose:
          'Ulnar deviation with axial load and rotation provokes TFCC pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'TFCC pathology assessment',
    ),
    ClinicalTestDefinition(
      id: 'hand_cmc_grind',
      name: 'CMC Grind Test',
      synonyms: ['Thumb CMC Grind'],
      region: BodyRegion.wristHand,
      category: TestCategory.provocation,
      primaryStructures: ['first CMC joint'],
      purpose:
          'Axial compression and rotation at first CMC reproduces OA pain and crepitus.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Thumb CMC OA clinical tests',
    ),

    // ------------------------------------------------------------
    // HIP
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'hip_faber',
      name: 'FABER (Patrick’s) Test',
      synonyms: ['Figure-4 Test'],
      region: BodyRegion.hip,
      category: TestCategory.provocation,
      primaryStructures: ['hip joint', 'SIJ'],
      purpose:
          'Flexion–abduction–external rotation position; location of pain helps '
          'differentiate hip vs SIJ.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hip/SIJ differential diagnosis literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'hip_fadir',
      name: 'FADIR Test',
      synonyms: ['Impingement Test'],
      region: BodyRegion.hip,
      category: TestCategory.provocation,
      primaryStructures: ['femoroacetabular joint', 'labrum'],
      purpose:
          'Flexion–adduction–internal rotation to provoke FAI/labral symptoms.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'FAI/labral impingement studies',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'hip_scour',
      name: 'Hip Scour Test',
      synonyms: ['Quadrant Test (Hip)'],
      region: BodyRegion.hip,
      category: TestCategory.labrum,
      primaryStructures: ['hip joint surfaces', 'labrum'],
      purpose:
          'Axial load with arc of motion; detects intra-articular hip pathology.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Hip labral pathology test descriptions',
    ),
    ClinicalTestDefinition(
      id: 'hip_trendelenburg',
      name: 'Trendelenburg Sign',
      synonyms: [],
      region: BodyRegion.hip,
      category: TestCategory.functional,
      primaryStructures: ['gluteus medius', 'hip abductors'],
      purpose:
          'Single-leg stance test; pelvic drop indicates abductor weakness or dysfunction.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Hip abductor dysfunction studies',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'hip_thomas',
      name: 'Thomas Test',
      synonyms: [],
      region: BodyRegion.hip,
      category: TestCategory.muscle,
      primaryStructures: ['hip flexors', 'iliopsoas', 'rectus femoris'],
      purpose:
          'Assess hip flexor length and contribution to anterior hip/thigh symptoms.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Classic muscle length testing',
    ),
    ClinicalTestDefinition(
      id: 'hip_ober',
      name: 'Ober’s Test',
      synonyms: [],
      region: BodyRegion.hip,
      category: TestCategory.muscle,
      primaryStructures: ['ITB', 'TFL'],
      purpose:
          'Assesses ITB/TFL tightness via side-lying hip adduction drop.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'ITB tightness assessment',
    ),

    // ------------------------------------------------------------
    // KNEE
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'knee_lachman',
      name: 'Lachman Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['ACL'],
      purpose:
          'Gold-standard clinical test for ACL integrity; ~20–30° knee flexion with anterior tibial translation.',
      sensitivity: 0.85,
      specificity: 0.94,
      lrPositive: null,
      lrNegative: null,
      evidenceLevel: EvidenceLevel.high,
      keyReference: 'Benjaminse 2006; Krakowski 2019',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'knee_ant_drawer',
      name: 'Anterior Drawer (Knee)',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['ACL'],
      purpose:
          'Assesses ACL laxity at 90° flexion with anterior tibial translation.',
      sensitivity: 0.69,
      specificity: 0.93,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Krakowski 2019 ACL diagnostic accuracy',
    ),
    ClinicalTestDefinition(
      id: 'knee_posterior_drawer',
      name: 'Posterior Drawer',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['PCL'],
      purpose:
          'Assesses PCL laxity via posterior tibial translation at 90° flexion.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'PCL diagnostic literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'knee_posterior_sag',
      name: 'Posterior Sag Sign',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['PCL'],
      purpose:
          'Visual posterior displacement of tibial plateau relative to femur '
          'indicating PCL deficiency.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'PCL exam studies',
    ),
    ClinicalTestDefinition(
      id: 'knee_mcmurray',
      name: 'McMurray Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.meniscus,
      primaryStructures: ['medial meniscus', 'lateral meniscus'],
      purpose:
          'Flexion–extension with rotation and varus/valgus to provoke meniscal '
          'pain/clicking.',
      sensitivity: 0.65,
      specificity: 0.83,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Krakowski 2019 meniscus accuracy',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'knee_thessaly',
      name: 'Thessaly Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.meniscus,
      primaryStructures: ['menisci'],
      purpose:
          'Weightbearing rotation at 20° flexion; provokes joint line pain/locking.',
      sensitivity: 0.85,
      specificity: 0.54,
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Krakowski 2019; Karachalios original study',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'knee_apley',
      name: 'Apley’s Compression Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.meniscus,
      primaryStructures: ['menisci'],
      purpose:
          'Prone compression with rotation stresses meniscal structures; distraction '
          'helps differentiate capsular vs meniscal.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Classic meniscus examination',
    ),
    ClinicalTestDefinition(
      id: 'knee_valgus_stress',
      name: 'Valgus Stress Test (MCL)',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['MCL'],
      purpose:
          'Assesses MCL integrity with valgus force at 0° and 30° knee flexion.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Collateral ligament examination',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'knee_varus_stress',
      name: 'Varus Stress Test (LCL)',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.ligament,
      primaryStructures: ['LCL'],
      purpose:
          'Assesses LCL integrity with varus stress at 0° and 30°.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Collateral ligament exam literature',
    ),
    ClinicalTestDefinition(
      id: 'knee_clarkes',
      name: 'Clarke’s Test (Patellar Grind)',
      synonyms: ['Patellofemoral Grind'],
      region: BodyRegion.knee,
      category: TestCategory.provocation,
      primaryStructures: ['patellofemoral joint'],
      purpose:
          'Superior patellar glide with resisted quadriceps contraction; used in PF pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'PF pain clinical test literature',
    ),
    ClinicalTestDefinition(
      id: 'knee_patellar_apprehension',
      name: 'Patellar Apprehension Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.instability,
      primaryStructures: ['medial PF restraints'],
      purpose:
          'Lateral patellar glide in slight flexion evokes apprehension (not just pain) '
          'in patients with instability.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Patellar instability assessment',
    ),

    // ------------------------------------------------------------
    // ANKLE & FOOT
    // ------------------------------------------------------------
    ClinicalTestDefinition(
      id: 'ankle_ant_drawer',
      name: 'Anterior Drawer (Ankle)',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.ligament,
      primaryStructures: ['ATFL', 'anterior capsule'],
      purpose:
          'Assesses anterior talofibular ligament integrity / lateral ankle sprain.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Ankle sprain diagnostic literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'ankle_talar_tilt',
      name: 'Talar Tilt Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.ligament,
      primaryStructures: ['CFL', 'ATFL', 'deltoid (eversion)'],
      purpose:
          'Inversion or eversion stress in neutral to assess lateral or medial ligament injuries.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Lateral ankle sprain exam',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'ankle_squeeze',
      name: 'Squeeze Test (Syndesmosis)',
      synonyms: ['Fibular Compression Test'],
      region: BodyRegion.ankleFoot,
      category: TestCategory.ligament,
      primaryStructures: ['tibiofibular syndesmosis'],
      purpose:
          'Compression of tibia/fibula proximally reproducing pain distally in syndesmotic injury.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'High ankle sprain diagnostic studies',
    ),
    ClinicalTestDefinition(
      id: 'ankle_external_rotation',
      name: 'External Rotation Stress Test',
      synonyms: ['Kleiger Test'],
      region: BodyRegion.ankleFoot,
      category: TestCategory.ligament,
      primaryStructures: ['syndesmosis', 'deltoid ligament'],
      purpose:
          'ER of foot relative to tibia stresses syndesmotic and deltoid structures.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Syndesmosis injury literature',
    ),
    ClinicalTestDefinition(
      id: 'ankle_thompson',
      name: 'Thompson Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.tendon,
      primaryStructures: ['Achilles tendon'],
      purpose:
          'Calf squeeze test for Achilles rupture (absence of plantarflexion).',
      evidenceLevel: EvidenceLevel.high,
      keyReference: 'Achilles rupture clinical tests',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'foot_windlass',
      name: 'Windlass Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.provocation,
      primaryStructures: ['plantar fascia'],
      purpose:
          'Passive extension of hallux with weightbearing; provokes plantar heel pain in fasciopathy.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Plantar fasciitis test literature',
    ),
    ClinicalTestDefinition(
      id: 'foot_navicular_drop',
      name: 'Navicular Drop Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.posture,
      primaryStructures: ['medial arch', 'midfoot'],
      purpose:
          'Quantifies change in navicular height from NWB to WB as a measure of foot pronation.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Foot posture assessment studies',
    ),
    ClinicalTestDefinition(
      id: 'foot_tarsal_tunnel_tinel',
      name: 'Tinel’s – Tarsal Tunnel',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.neural,
      primaryStructures: ['tibial nerve'],
      purpose:
          'Percussion posterior to medial malleolus reproduces paresthesia in tibial nerve distribution.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Tarsal tunnel syndrome descriptions',
    ),

    // ============================================================
    // MORE CERVICAL TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'cervical_lhermitte',
      name: 'Lhermitte’s Sign',
      synonyms: [],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['cervical spinal cord', 'dural structures'],
      purpose:
          'Electric shock sensation down spine/limbs with neck flexion; suggests cervical cord involvement.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Classical cervical myelopathy sign descriptions',
    ),
    ClinicalTestDefinition(
      id: 'cervical_hoffmann',
      name: 'Hoffmann’s Sign',
      synonyms: [],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['corticospinal tract'],
      purpose:
          'Flicking distal phalanx of middle finger produces thumb/index flexion; UMN sign in cervical myelopathy.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Cervical myelopathy clinical cluster studies',
    ),
    ClinicalTestDefinition(
      id: 'cervical_babinski',
      name: 'Babinski Sign',
      synonyms: [],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['corticospinal tract'],
      purpose:
          'Stroke lateral plantar foot; great toe extension/fanning of toes indicates UMN lesion.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'UMN lesion examination',
    ),
    ClinicalTestDefinition(
      id: 'cervical_shoulder_abduction_relief',
      name: 'Shoulder Abduction Relief Sign',
      synonyms: ['Bakody Sign'],
      region: BodyRegion.cervical,
      category: TestCategory.neural,
      primaryStructures: ['cervical nerve roots', 'brachial plexus'],
      purpose:
          'Placing hand on head reduces radicular arm pain; supports cervical radiculopathy.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Radiculopathy test clusters',
    ),
    ClinicalTestDefinition(
      id: 'cervical_adson',
      name: 'Adson’s Test',
      synonyms: [],
      region: BodyRegion.cervical,
      category: TestCategory.vascular,
      primaryStructures: ['subclavian artery', 'scalene triangle'],
      purpose:
          'Assesses thoracic outlet compression with head rotation, extension, and deep inspiration while monitoring radial pulse.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Thoracic outlet syndrome literature',
    ),
    ClinicalTestDefinition(
      id: 'cervical_roos',
      name: 'Roos Test (EAST)',
      synonyms: ['Elevated Arm Stress Test'],
      region: BodyRegion.cervical,
      category: TestCategory.vascular,
      primaryStructures: ['brachial plexus', 'thoracic outlet'],
      purpose:
          'Patient holds arms in 90/90 and repeatedly opens/closes hands for 3 min; reproduction of symptoms suggests TOS.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Thoracic outlet syndrome assessment',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'cervical_wright',
      name: 'Wright’s Hyperabduction Test',
      synonyms: [],
      region: BodyRegion.cervical,
      category: TestCategory.vascular,
      primaryStructures: ['axillary artery', 'brachial plexus'],
      purpose:
          'Abduction and ER of arm with pulse monitoring to detect costocoracoid compression in TOS.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'TOS test descriptions',
    ),
    ClinicalTestDefinition(
      id: 'cervical_costoclavicular',
      name: 'Costoclavicular Test',
      synonyms: ['Military Brace Test'],
      region: BodyRegion.cervical,
      category: TestCategory.vascular,
      primaryStructures: ['subclavian vessels', 'brachial plexus'],
      purpose:
          'Retracted/ depressed shoulders with chest elevation and pulse monitoring to stress costoclavicular space.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'TOS clinical exam',
    ),

    // ============================================================
    // MORE THORACIC TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'thoracic_first_rib_crlf',
      name: 'Cervical Rotation Lateral Flexion Test',
      synonyms: ['First Rib CRLF Test'],
      region: BodyRegion.thoracic,
      category: TestCategory.jointMobility,
      primaryStructures: ['first rib', 'CT junction'],
      purpose:
          'Assesses first rib hypomobility by rotating away and side-bending toward the rib; limited motion suggests elevation.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Thoracic outlet / first rib assessment studies',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'thoracic_first_rib_spring',
      name: 'First Rib Spring Test',
      synonyms: [],
      region: BodyRegion.thoracic,
      category: TestCategory.jointMobility,
      primaryStructures: ['first rib', 'costotransverse joint'],
      purpose:
          'PA springing on first rib to assess mobility and reproduce symptoms radiating to neck/shoulder.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Manual therapy first rib evaluation',
    ),
    ClinicalTestDefinition(
      id: 'thoracic_sitting_compression',
      name: 'Seated Thoracic Compression Test',
      synonyms: [],
      region: BodyRegion.thoracic,
      category: TestCategory.provocation,
      primaryStructures: ['thoracic vertebrae', 'disc', 'facets'],
      purpose:
          'Axial compression through shoulders in sitting to provoke thoracic symptoms.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Thoracic spine assessment descriptions',
    ),
    ClinicalTestDefinition(
      id: 'thoracic_sitting_distraction',
      name: 'Seated Thoracic Distraction Test',
      synonyms: [],
      region: BodyRegion.thoracic,
      category: TestCategory.provocation,
      primaryStructures: ['thoracic joints', 'disc'],
      purpose:
          'Axial distraction to reduce compressive symptoms and help differentiate thoracic vs rib pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Manual therapy exam techniques',
    ),
    ClinicalTestDefinition(
      id: 'thoracic_breathing_pattern',
      name: 'Breathing Pattern Assessment',
      synonyms: ['Costal vs diaphragmatic breathing'],
      region: BodyRegion.thoracic,
      category: TestCategory.functional,
      primaryStructures: ['rib cage', 'diaphragm', 'intercostals'],
      purpose:
          'Visual and palpatory assessment of upper chest vs diaphragmatic breathing, rib expansion, and symmetry.',
      evidenceLevel: EvidenceLevel.veryLow,
      keyReference: 'Respiratory pattern assessment literature',
    ),

    // ============================================================
    // MORE LUMBAR / SIJ TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'lumbar_passive_lumbar_extension',
      name: 'Passive Lumbar Extension Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.instability,
      primaryStructures: ['lumbar segments', 'passive restraints'],
      purpose:
          'Passive elevation of extended legs in prone; reports of “heavy, unstable lumbar region” suggest instability.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Lumbar instability clinical prediction literature',
    ),
    ClinicalTestDefinition(
      id: 'lumbar_beighton',
      name: 'Beighton Hypermobility Score',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.functional,
      primaryStructures: ['connective tissue overall'],
      purpose:
          'Nine-point scoring system for generalized joint hypermobility, relevant to instability and pain presentations.',
      evidenceLevel: EvidenceLevel.high,
      keyReference: 'Beighton 1973; hypermobility criteria',
    ),
    ClinicalTestDefinition(
      id: 'lumbar_schober',
      name: 'Schober Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.jointMobility,
      primaryStructures: ['lumbar spine', 'thoracolumbar fascia'],
      purpose:
          'Measure change in distance between lumbar skin marks with forward flexion to quantify lumbar ROM.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Schober 1937; ankylosing spondylitis monitoring',
    ),
    ClinicalTestDefinition(
      id: 'lumbar_modified_schober',
      name: 'Modified Schober Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.jointMobility,
      primaryStructures: ['lumbar spine'],
      purpose:
          'Variation of Schober using standardized landmarks to improve reliability.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Macrae & Wright modifications',
    ),
    ClinicalTestDefinition(
      id: 'sij_stork_gillet',
      name: 'Stork (Gillet) Test',
      synonyms: [],
      region: BodyRegion.lumbar,
      category: TestCategory.jointMobility,
      primaryStructures: ['SIJ', 'innominate'],
      purpose:
          'Assesses innominate movement relative to sacrum during hip flexion; abnormal motion suggests SIJ dysfunction.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'SIJ mobility test descriptions',
    ),
    ClinicalTestDefinition(
      id: 'lumbar_sorensen',
      name: 'Sorensen Test',
      synonyms: ['Biering–Sorensen'],
      region: BodyRegion.lumbar,
      category: TestCategory.functional,
      primaryStructures: ['lumbar extensors'],
      purpose:
          'Measures isometric endurance of trunk extensors in prone over table.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Low back pain endurance literature',
    ),

    // ============================================================
    // MORE SHOULDER TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'shoulder_yocum',
      name: 'Yocum Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.provocation,
      primaryStructures: ['subacromial space', 'rotator cuff'],
      purpose:
          'Touch hand to opposite shoulder and elevate elbow; impingement provocation variant.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Impingement cluster descriptions',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_full_can',
      name: 'Full Can Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['supraspinatus'],
      purpose:
          'Resisted elevation in scapular plane with thumb up (ER); alternative to Empty Can with possibly less pain.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Rotator cuff tear diagnostic comparisons',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_hornblowers',
      name: 'Hornblower’s Sign',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['teres minor', 'infraspinatus'],
      purpose:
          'Assesses external rotation strength at 90° abduction; weakness suggests posterosuperior cuff tear.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Massive cuff tear descriptions',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_irrst',
      name: 'Internal Rotation Resisted Strength Test',
      synonyms: ['IRRST'],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['rotator cuff', 'infraspinatus'],
      purpose:
          'Compares IR vs ER strength at 90° abduction to distinguish internal impingement vs outlet impingement.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Walch internal impingement literature',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_posterior_apprehension',
      name: 'Posterior Apprehension Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.instability,
      primaryStructures: ['posterior capsule', 'posterior labrum'],
      purpose:
          'Assesses posterior instability with flexion, adduction, and IR with posterior force.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Posterior instability exam descriptions',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_yergason',
      name: 'Yergason’s Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.tendon,
      primaryStructures: ['biceps tendon', 'transverse humeral ligament'],
      purpose:
          'Resisted forearm supination with elbow flexed; pain or snapping suggests bicipital tendinopathy or subluxation.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Biceps tendon test descriptions',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_kim',
      name: 'Kim Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.labrum,
      primaryStructures: ['posteroinferior labrum'],
      purpose:
          'Axial load with 90° abduction and diagonal elevation; pain/clicking suggests posteroinferior labral lesion.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Kim et al. labral lesion study',
    ),
    ClinicalTestDefinition(
      id: 'shoulder_jerk',
      name: 'Jerk Test',
      synonyms: [],
      region: BodyRegion.shoulder,
      category: TestCategory.labrum,
      primaryStructures: ['posteroinferior labrum'],
      purpose:
          'Horizontal adduction with axial load; sudden jerk/clunk indicates posterior labral pathology.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Posterior labrum test descriptions',
    ),

    // ============================================================
    // MORE ELBOW TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'elbow_varus_stress',
      name: 'Varus Stress Test',
      synonyms: [],
      region: BodyRegion.elbow,
      category: TestCategory.ligament,
      primaryStructures: ['LCL complex'],
      purpose:
          'Applies varus force at 0–30° flexion to assess lateral collateral ligament integrity.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Elbow instability literature',
    ),
    ClinicalTestDefinition(
      id: 'elbow_plri',
      name: 'Posterolateral Rotatory Instability Test',
      synonyms: ['PLRI Test'],
      region: BodyRegion.elbow,
      category: TestCategory.instability,
      primaryStructures: ['LCL complex', 'posterolateral capsule'],
      purpose:
          'Supine test with axial load, supination, and valgus to provoke posterior-lateral subluxation.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'O’Driscoll PLRI description',
    ),
    ClinicalTestDefinition(
      id: 'elbow_chair_sign',
      name: 'Chair Push-Up Test',
      synonyms: ['Chair Sign'],
      region: BodyRegion.elbow,
      category: TestCategory.instability,
      primaryStructures: ['LCL complex'],
      purpose:
          'Patient pushes up from a chair; apprehension or giving way suggests posterolateral rotatory instability.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'PLRI functional tests',
    ),
    ClinicalTestDefinition(
      id: 'elbow_tabletop_relocation',
      name: 'Tabletop Relocation Test',
      synonyms: [],
      region: BodyRegion.elbow,
      category: TestCategory.instability,
      primaryStructures: ['LCL complex'],
      purpose:
          'Modified press-up with elbow in extension; manual stabilization reduces symptoms, supporting PLRI.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'O’Driscoll PLRI work',
    ),

    // ============================================================
    // MORE WRIST & HAND TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'hand_froment',
      name: 'Froment’s Sign',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.neural,
      primaryStructures: ['ulnar nerve', 'adductor pollicis'],
      purpose:
          'Pinch paper between thumb and index; IP flexion of thumb suggests ulnar nerve palsy.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Ulnar neuropathy descriptions',
    ),
    ClinicalTestDefinition(
      id: 'hand_wartenberg',
      name: 'Wartenberg’s Sign',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.neural,
      primaryStructures: ['ulnar nerve'],
      purpose:
          'Inability to adduct little finger indicates ulnar nerve involvement.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Ulnar neuropathy exams',
    ),
    ClinicalTestDefinition(
      id: 'hand_allen',
      name: 'Allen Test',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.vascular,
      primaryStructures: ['radial artery', 'ulnar artery'],
      purpose:
          'Assesses patency of radial and ulnar arteries via sequential compression and release.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Vascular assessment literature',
    ),
    ClinicalTestDefinition(
      id: 'hand_bunnell_littler',
      name: 'Bunnell–Littler Test',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.muscle,
      primaryStructures: ['intrinsic hand muscles', 'PIP joint structures'],
      purpose:
          'Differentiates intrinsic tightness vs capsular restriction of PIP flexion.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Hand intrinsic tightness assessment',
    ),
    ClinicalTestDefinition(
      id: 'wrist_lunotriquetral_ballottement',
      name: 'Lunotriquetral Ballottement Test',
      synonyms: [],
      region: BodyRegion.wristHand,
      category: TestCategory.instability,
      primaryStructures: ['lunotriquetral ligament'],
      purpose:
          'Shear lunate and triquetrum to elicit pain or clicking in LT instability.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Wrist instability literature',
    ),
    ClinicalTestDefinition(
      id: 'wrist_piano_key',
      name: 'Piano Key Test',
      synonyms: ['DRUJ Ballottement'],
      region: BodyRegion.wristHand,
      category: TestCategory.instability,
      primaryStructures: ['distal radioulnar joint'],
      purpose:
          'Depress distal ulna like a piano key; excessive mobility or pain suggests DRUJ instability.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'DRUJ instability descriptions',
    ),

    // ============================================================
    // MORE HIP TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'hip_fair',
      name: 'FAIR Test (Piriformis)',
      synonyms: ['Flexion–Adduction–Internal Rotation (Piriformis)'],
      region: BodyRegion.hip,
      category: TestCategory.provocation,
      primaryStructures: ['piriformis', 'sciatic nerve'],
      purpose:
          'Provokes buttock/leg pain with flexion, adduction, and IR to assess piriformis syndrome.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Piriformis syndrome clinical tests',
    ),
    ClinicalTestDefinition(
      id: 'hip_resisted_external_derotation',
      name: 'Resisted External De-rotation Test',
      synonyms: [],
      region: BodyRegion.hip,
      category: TestCategory.tendon,
      primaryStructures: ['gluteus medius', 'gluteus minimus'],
      purpose:
          'Assesses lateral hip/gluteal tendinopathy by resisting external rotation from flexed IR position.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Gluteal tendinopathy diagnostic literature',
      isCommon: true,
    ),
    ClinicalTestDefinition(
      id: 'hip_log_roll',
      name: 'Log Roll Test',
      synonyms: [],
      region: BodyRegion.hip,
      category: TestCategory.labrum,
      primaryStructures: ['hip capsule', 'labrum'],
      purpose:
          'Passive IR/ER of relaxed leg; excessive motion or clicking suggests capsular or labral pathology.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Intra-articular hip exam descriptions',
    ),

    // ============================================================
    // MORE KNEE TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'knee_noble',
      name: 'Noble Compression Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.tendon,
      primaryStructures: ['ITB', 'lateral femoral condyle'],
      purpose:
          'Pressure over lateral femoral epicondyle during knee flex/ext to provoke ITB friction pain.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'ITB syndrome tests',
    ),
    ClinicalTestDefinition(
      id: 'knee_eges',
      name: 'Ege’s Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.meniscus,
      primaryStructures: ['menisci'],
      purpose:
          'Squatting with tibial rotation; pain/clicking medially or laterally indicates meniscal tear.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Ege 1999 meniscus test study',
    ),
    ClinicalTestDefinition(
      id: 'knee_stroke',
      name: 'Stroke Test',
      synonyms: ['Brush Test'],
      region: BodyRegion.knee,
      category: TestCategory.other,
      primaryStructures: ['knee joint capsule', 'effusion'],
      purpose:
          'Stroke technique around patella to grade joint effusion (wave or bulge sign).',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Knee effusion grading literature',
    ),
    ClinicalTestDefinition(
      id: 'knee_patellar_tap',
      name: 'Patellar Tap Test',
      synonyms: ['Ballottement Test'],
      region: BodyRegion.knee,
      category: TestCategory.other,
      primaryStructures: ['knee effusion'],
      purpose:
          'Downward pressure on patella detects floating/boggy sensation in large effusions.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Clinical knee effusion assessment',
    ),
    ClinicalTestDefinition(
      id: 'knee_mcconnell',
      name: 'McConnell Test',
      synonyms: [],
      region: BodyRegion.knee,
      category: TestCategory.provocation,
      primaryStructures: ['patellofemoral joint'],
      purpose:
          'Assesses PF pain by resisted extension in varying angles and retesting with patellar glide.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'McConnell PF pain program literature',
    ),

    // ============================================================
    // MORE ANKLE & FOOT TESTS
    // ============================================================
    ClinicalTestDefinition(
      id: 'ankle_anterior_impingement',
      name: 'Anterior Impingement Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.provocation,
      primaryStructures: ['anterior ankle joint capsule', 'osteophytes'],
      purpose:
          'Forced dorsiflexion with anterior joint line palpation to provoke pain in anterior impingement syndromes.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Anterior ankle impingement literature',
    ),
    ClinicalTestDefinition(
      id: 'foot_morton_squeeze',
      name: 'Morton’s Squeeze Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.neural,
      primaryStructures: ['interdigital nerve', 'metatarsal heads'],
      purpose:
          'Forefoot squeeze to reproduce burning pain/paresthesia in Morton’s neuroma.',
      evidenceLevel: EvidenceLevel.moderate,
      keyReference: 'Morton’s neuroma exam descriptions',
    ),
    ClinicalTestDefinition(
      id: 'foot_mulder_click',
      name: 'Mulder’s Click Test',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.neural,
      primaryStructures: ['interdigital nerve'],
      purpose:
          'Squeeze forefoot while palpating interspace; palpable click and pain suggest neuroma.',
      evidenceLevel: EvidenceLevel.low,
      keyReference: 'Morton’s neuroma literature',
    ),
    ClinicalTestDefinition(
      id: 'calf_homans',
      name: 'Homan’s Sign',
      synonyms: [],
      region: BodyRegion.ankleFoot,
      category: TestCategory.vascular,
      primaryStructures: ['deep veins of calf'],
      purpose:
          'Pain in calf with passive dorsiflexion and knee extension; historically used for DVT but poor accuracy.',
      evidenceLevel: EvidenceLevel.veryLow,
      keyReference:
          'DVT clinical exam reviews (not recommended standalone)',
    ),
  ];

  static List<ClinicalTestDefinition> get allTests =>
      List.unmodifiable(_allTests);

  static List<ClinicalTestDefinition> testsForRegion(BodyRegion region) {
    final filtered = _allTests.where((t) => t.region == region).toList();
    filtered.sort((a, b) {
      if (a.isCommon == b.isCommon) {
        return a.name.compareTo(b.name);
      }
      return a.isCommon ? -1 : 1;
    });
    return filtered;
  }

  static ClinicalTestDefinition? byId(String id) {
    try {
      return _allTests.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static String toRawJson() =>
      jsonEncode(_allTests.map((t) => t.toJson()).toList());
}

/// UI-facing alias so widgets can refer to `ClinicalTest` instead of
/// `ClinicalTestDefinition`.
typedef ClinicalTest = ClinicalTestDefinition;

