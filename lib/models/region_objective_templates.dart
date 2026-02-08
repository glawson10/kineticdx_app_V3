// lib/models/region_objective_templates.dart
//
// Region-specific templates for Objective findings.
// These drive the UI and help you auto-build RegionObjective
// instances with appropriate movement / strength / neuro labels.
// Normative ROM ranges (degrees) are attached per movement for clinician reference.

import 'soap_note.dart';
import 'clinical_tests.dart'; // for BodyRegion

/// One movement direction with optional normative range in degrees.
class RomMovementDef {
  final String movement;
  final int minDeg;
  final int maxDeg;

  const RomMovementDef({
    required this.movement,
    required this.minDeg,
    required this.maxDeg,
  });

  String get normalRangeLabel => '$minDeg–$maxDeg°';
}

class RegionObjectiveTemplate {
  final List<RomMovementDef> aromMovements;
  final List<RomMovementDef> promMovements;
  final List<String> strengthItems;
  final List<String> neuroItems;
  final List<String> jointMobilityLevels;
  final List<String> palpationAreas;

  const RegionObjectiveTemplate({
    this.aromMovements = const [],
    this.promMovements = const [],
    this.strengthItems = const [],
    this.neuroItems = const [],
    this.jointMobilityLevels = const [],
    this.palpationAreas = const [],
  });

  /// Helper to create an empty RegionObjective based on the template.
  RegionObjective createEmptyRegionObjective(BodyRegion region) {
    return RegionObjective(
      region: region,
      activeRom: aromMovements
          .map((m) => RomFinding(movement: m.movement))
          .toList(),
      passiveRom: promMovements
          .map((m) => RomFinding(movement: m.movement))
          .toList(),
      strength: strengthItems
          .map(
            (s) => StrengthFinding(
              movementOrMyotome: s,
            ),
          )
          .toList(),
      neuro: neuroItems
          .map(
            (n) => NeuroFinding(
              structure: n,
              status: 'normal',
            ),
          )
          .toList(),
      jointMobility: jointMobilityLevels
          .map(
            (lvl) => JointMobilityFinding(
              level: lvl,
              mobility: 'normal',
            ),
          )
          .toList(),
      palpation: palpationAreas
          .map(
            (area) => PalpationFinding(
              location: area,
            ),
          )
          .toList(),
    );
  }
}

/// Global map – one template per BodyRegion with normative ROM per movement.
const Map<BodyRegion, RegionObjectiveTemplate> regionObjectiveTemplates = {
  BodyRegion.cervical: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 50),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 60),
      RomMovementDef(movement: 'Lateral Flexion Left', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Lateral Flexion Right', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Rotation Left', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Rotation Right', minDeg: 0, maxDeg: 80),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 50),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 60),
      RomMovementDef(movement: 'Side-flexion Left', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Side-flexion Right', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Rotation Left', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Rotation Right', minDeg: 0, maxDeg: 80),
    ],
    strengthItems: [
      'C5 Shoulder Abduction',
      'C6 Elbow Flexion',
      'C7 Elbow Extension',
      'C8 Thumb Extension',
      'T1 Finger Abduction',
    ],
    neuroItems: [
      'Dermatome C3',
      'Dermatome C4',
      'Dermatome C5',
      'Dermatome C6',
      'Dermatome C7',
      'Dermatome C8',
      'Dermatome T1',
      'Reflex Biceps (C5-6)',
      'Reflex Brachioradialis (C6)',
      'Reflex Triceps (C7)',
      'ULNT1',
    ],
    jointMobilityLevels: [
      'C0-1',
      'C1-2',
      'C2-3',
      'C3-4',
      'C4-5',
      'C5-6',
      'C6-7',
      'C7-T1',
    ],
    palpationAreas: [
      'Cervical paraspinals',
      'SCM',
      'Upper trapezius',
      'Levator scapulae',
      'First rib',
    ],
  ),

  BodyRegion.thoracic: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 40),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Side-flexion Left', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Side-flexion Right', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Rotation Left', minDeg: 0, maxDeg: 35),
      RomMovementDef(movement: 'Rotation Right', minDeg: 0, maxDeg: 35),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 40),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Rotation Left', minDeg: 0, maxDeg: 35),
      RomMovementDef(movement: 'Rotation Right', minDeg: 0, maxDeg: 35),
    ],
    strengthItems: [
      'Mid trapezius',
      'Lower trapezius',
      'Rhomboids',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'T1-2',
      'T2-3',
      'T3-4',
      'T4-5',
      'T5-6',
      'T6-7',
      'T7-8',
      'T8-9',
      'T9-10',
      'T10-11',
      'T11-12',
    ],
    palpationAreas: [
      'Thoracic erectors',
      'Costovertebral region',
    ],
  ),

  BodyRegion.lumbar: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 60),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Side-flexion Left', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Side-flexion Right', minDeg: 0, maxDeg: 25),
      RomMovementDef(movement: 'Rotation Left', minDeg: 0, maxDeg: 5),
      RomMovementDef(movement: 'Rotation Right', minDeg: 0, maxDeg: 5),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 60),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 25),
    ],
    strengthItems: [
      'L2 Hip Flexion',
      'L3 Knee Extension',
      'L4 Ankle Dorsiflexion',
      'L5 Great Toe Extension',
      'S1 Plantarflexion',
      'S2 Knee Flexion',
    ],
    neuroItems: [
      'Dermatome L2',
      'Dermatome L3',
      'Dermatome L4',
      'Dermatome L5',
      'Dermatome S1',
      'Dermatome S2',
      'Reflex Patellar (L3-4)',
      'Reflex Achilles (S1)',
      'SLR',
      'Slump',
      'PKB / Femoral nerve test',
    ],
    jointMobilityLevels: [
      'L1-2',
      'L2-3',
      'L3-4',
      'L4-5',
      'L5-S1',
    ],
    palpationAreas: [
      'Lumbar paraspinals',
      'SIJ',
      'Gluteals',
    ],
  ),

  BodyRegion.shoulder: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 180),
      RomMovementDef(movement: 'Abduction', minDeg: 0, maxDeg: 180),
      RomMovementDef(movement: 'External Rotation', minDeg: 0, maxDeg: 90),
      RomMovementDef(movement: 'Internal Rotation', minDeg: 0, maxDeg: 70),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 60),
      RomMovementDef(movement: 'Scaption', minDeg: 0, maxDeg: 120),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 180),
      RomMovementDef(movement: 'Abduction', minDeg: 0, maxDeg: 180),
      RomMovementDef(movement: 'External Rotation', minDeg: 0, maxDeg: 90),
      RomMovementDef(movement: 'Internal Rotation', minDeg: 0, maxDeg: 70),
    ],
    strengthItems: [
      'Flexion',
      'Abduction',
      'External Rotation',
      'Internal Rotation',
      'Scapular Retraction',
      'Scaption',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'GH AP',
      'GH PA',
      'GH Inferior glide',
      'AC joint',
      'SC joint',
      'Scapulothoracic',
    ],
    palpationAreas: [
      'Supraspinatus tendon',
      'Infraspinatus tendon',
      'Subscapularis tendon',
      'Biceps tendon',
      'AC joint',
      'Scapular border',
    ],
  ),

  BodyRegion.elbow: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 150),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 0),
      RomMovementDef(movement: 'Supination', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Pronation', minDeg: 0, maxDeg: 80),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 150),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 0),
      RomMovementDef(movement: 'Supination', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Pronation', minDeg: 0, maxDeg: 80),
    ],
    strengthItems: [
      'Biceps',
      'Triceps',
      'Wrist Extensors',
      'Wrist Flexors',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'Humeroulnar AP',
      'Humeroulnar PA',
      'Humeroradial AP',
      'Humeroradial PA',
      'Proximal radioulnar AP',
      'Proximal radioulnar PA',
    ],
    palpationAreas: [
      'Lateral epicondyle',
      'Medial epicondyle',
      'Radial head',
    ],
  ),

  BodyRegion.wristHand: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Wrist Flexion', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Wrist Extension', minDeg: 0, maxDeg: 70),
      RomMovementDef(movement: 'Radial Deviation', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Ulnar Deviation', minDeg: 0, maxDeg: 30),
      RomMovementDef(movement: 'Finger Flexion/Extension', minDeg: 0, maxDeg: 0), // N/A degrees
      RomMovementDef(movement: 'Thumb Opposition', minDeg: 0, maxDeg: 0), // N/A
    ],
    promMovements: [
      RomMovementDef(movement: 'Wrist Flexion', minDeg: 0, maxDeg: 80),
      RomMovementDef(movement: 'Wrist Extension', minDeg: 0, maxDeg: 70),
      RomMovementDef(movement: 'Radial Deviation', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Ulnar Deviation', minDeg: 0, maxDeg: 30),
    ],
    strengthItems: [
      'Grip strength',
      'Pinch strength',
      'Finger abduction',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'Carpal AP',
      'Carpal PA',
      'MCP mobility',
      'PIP mobility',
      'DIP mobility',
    ],
    palpationAreas: [
      'Carpal bones',
      'TFCC region',
      'A1 pulley',
    ],
  ),

  BodyRegion.hip: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 120),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Abduction', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Adduction', minDeg: 0, maxDeg: 30),
      RomMovementDef(movement: 'Internal Rotation', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'External Rotation', minDeg: 0, maxDeg: 45),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 120),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Abduction', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'Adduction', minDeg: 0, maxDeg: 30),
      RomMovementDef(movement: 'Internal Rotation', minDeg: 0, maxDeg: 45),
      RomMovementDef(movement: 'External Rotation', minDeg: 0, maxDeg: 45),
    ],
    strengthItems: [
      'Flexion',
      'Extension',
      'Abduction',
      'Adduction',
      'Internal Rotation',
      'External Rotation',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'Long-axis distraction',
      'Lateral glide',
      'Posterior glide',
    ],
    palpationAreas: [
      'Greater trochanter',
      'Gluteus medius',
      'Gluteus maximus',
      'TFL / ITB',
    ],
  ),

  BodyRegion.knee: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 135),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 0),
    ],
    promMovements: [
      RomMovementDef(movement: 'Flexion', minDeg: 0, maxDeg: 135),
      RomMovementDef(movement: 'Extension', minDeg: 0, maxDeg: 0),
    ],
    strengthItems: [
      'Knee flexion',
      'Knee extension',
      'Glute medius',
      'Glute maximus',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'Tibiofemoral AP',
      'Tibiofemoral PA',
      'Patellofemoral superior',
      'Patellofemoral inferior',
      'Patellofemoral medial',
      'Patellofemoral lateral',
    ],
    palpationAreas: [
      'Medial joint line',
      'Lateral joint line',
      'Patellar tendon',
      'MCL',
      'LCL',
    ],
  ),

  BodyRegion.ankleFoot: RegionObjectiveTemplate(
    aromMovements: [
      RomMovementDef(movement: 'Dorsiflexion', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Plantarflexion', minDeg: 0, maxDeg: 50),
      RomMovementDef(movement: 'Inversion', minDeg: 0, maxDeg: 35),
      RomMovementDef(movement: 'Eversion', minDeg: 0, maxDeg: 15),
      RomMovementDef(movement: 'Toe flexion', minDeg: 0, maxDeg: 0), // N/A
      RomMovementDef(movement: 'Toe extension', minDeg: 0, maxDeg: 0), // N/A
    ],
    promMovements: [
      RomMovementDef(movement: 'Dorsiflexion', minDeg: 0, maxDeg: 20),
      RomMovementDef(movement: 'Plantarflexion', minDeg: 0, maxDeg: 50),
      RomMovementDef(movement: 'Inversion', minDeg: 0, maxDeg: 35),
      RomMovementDef(movement: 'Eversion', minDeg: 0, maxDeg: 15),
    ],
    strengthItems: [
      'Dorsiflexion',
      'Plantarflexion',
      'Inversion',
      'Eversion',
      'Toe flexion',
      'Toe extension',
    ],
    neuroItems: [],
    jointMobilityLevels: [
      'Talocrural AP',
      'Talocrural PA',
      'Subtalar mobility',
      'MTP mobility',
    ],
    palpationAreas: [
      'ATFL',
      'CFL',
      'PTFL',
      'Achilles tendon',
      'Plantar fascia',
    ],
  ),

  BodyRegion.other: RegionObjectiveTemplate(),
};
