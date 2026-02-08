import '../../../models/clinical_tests.dart';

/// Input kind for dynamically rendered region objective fields.
enum RegionFieldInputKind {
  text,
  number,
  boolean,
  select,
}

/// Metadata for normal range of motion, in degrees.
class RomNormalRange {
  final double min;
  final double max;

  const RomNormalRange({required this.min, required this.max});
}

/// Definition for a single structured objective field.
///
/// These drive the dynamic region-specific objective UI and make it possible
/// to:
/// - store all values in a structured map under objective.regionSpecific
/// - display normal ROM ranges per direction
/// - render appropriate widgets (number fields, switches, dropdowns)
class RegionFieldDefinition {
  final String key; // unique within region
  final String label;
  final String? description;
  final RegionFieldInputKind inputKind;
  final List<String> options; // for select
  final RomNormalRange? romNormal;

  const RegionFieldDefinition({
    required this.key,
    required this.label,
    this.description,
    required this.inputKind,
    this.options = const [],
    this.romNormal,
  });
}

/// Helper text for ROM fields based on RomNormalRange.
String romNormalHint(RomNormalRange? range) {
  if (range == null) return '';
  return 'Normal ~${range.min.toStringAsFixed(0)}–${range.max.toStringAsFixed(0)}°';
}

/// Normal ROM ranges per common joint movement direction.
///
/// These are approximate reference values; they are not used for validation,
/// only for clinician-facing hints and PDF context.
const Map<String, RomNormalRange> kGlobalRomNormals = {
  // Cervical spine (approx)
  'cervical_flex': RomNormalRange(min: 0, max: 50),
  'cervical_ext': RomNormalRange(min: 0, max: 60),
  'cervical_rotL': RomNormalRange(min: 0, max: 80),
  'cervical_rotR': RomNormalRange(min: 0, max: 80),
  'cervical_sbL': RomNormalRange(min: 0, max: 45),
  'cervical_sbR': RomNormalRange(min: 0, max: 45),

  // Thoracic rotation/extension (very approximate, per segment ranges vary)
  'thoracic_rotL': RomNormalRange(min: 0, max: 35),
  'thoracic_rotR': RomNormalRange(min: 0, max: 35),
  'thoracic_ext': RomNormalRange(min: 0, max: 25),

  // Lumbar spine
  'lumbar_flex': RomNormalRange(min: 0, max: 60),
  'lumbar_ext': RomNormalRange(min: 0, max: 25),
  'lumbar_sbL': RomNormalRange(min: 0, max: 25),
  'lumbar_sbR': RomNormalRange(min: 0, max: 25),
  'lumbar_rotL': RomNormalRange(min: 0, max: 5),
  'lumbar_rotR': RomNormalRange(min: 0, max: 5),

  // Shoulder (glenohumeral)
  'shoulder_flex': RomNormalRange(min: 0, max: 180),
  'shoulder_abd': RomNormalRange(min: 0, max: 180),
  'shoulder_er': RomNormalRange(min: 0, max: 90),
  'shoulder_ir': RomNormalRange(min: 0, max: 70),
  'shoulder_hbb': RomNormalRange(min: 0, max: 60),
  'shoulder_hbh': RomNormalRange(min: 0, max: 50),

  // Elbow
  'elbow_flex': RomNormalRange(min: 0, max: 150),
  'elbow_ext': RomNormalRange(min: 0, max: 0),
  'elbow_pro': RomNormalRange(min: 0, max: 80),
  'elbow_sup': RomNormalRange(min: 0, max: 80),

  // Wrist/hand
  'wrist_flex': RomNormalRange(min: 0, max: 80),
  'wrist_ext': RomNormalRange(min: 0, max: 70),
  'wrist_raddev': RomNormalRange(min: 0, max: 20),
  'wrist_ulndev': RomNormalRange(min: 0, max: 30),
  'wrist_pronation': RomNormalRange(min: 0, max: 80),
  'wrist_supination': RomNormalRange(min: 0, max: 80),

  // Hip
  'hip_flex': RomNormalRange(min: 0, max: 120),
  'hip_ext': RomNormalRange(min: 0, max: 20),
  'hip_abd': RomNormalRange(min: 0, max: 45),
  'hip_add': RomNormalRange(min: 0, max: 30),
  'hip_ir': RomNormalRange(min: 0, max: 45),
  'hip_er': RomNormalRange(min: 0, max: 45),

  // Knee
  'knee_flex': RomNormalRange(min: 0, max: 135),
  'knee_ext': RomNormalRange(min: 0, max: 0),

  // Ankle/foot
  'ankle_df': RomNormalRange(min: 0, max: 20),
  'ankle_pf': RomNormalRange(min: 0, max: 50),
  'ankle_inv': RomNormalRange(min: 0, max: 35),
  'ankle_ev': RomNormalRange(min: 0, max: 15),
};

RomNormalRange? romNormalForKey(String key) => kGlobalRomNormals[key];

/// Region-specific objective field definitions.
///
/// These keys are used both for UI rendering and for the
/// objective.regionSpecific map stored in Firestore.
final Map<BodyRegion, List<RegionFieldDefinition>> kRegionObjectiveFieldDefs = {
  BodyRegion.cervical: [
    // AROM: flex/ext/rotL/rotR/sbL/sbR (degrees + pain)
    RegionFieldDefinition(
      key: 'cervical_arom_flex_deg',
      label: 'AROM Flexion (deg)',
      description: 'Cervical flexion range',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_flex'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_flex_pain',
      label: 'Flexion painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_ext_deg',
      label: 'AROM Extension (deg)',
      description: 'Cervical extension range',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_ext'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_ext_pain',
      label: 'Extension painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_rotL_deg',
      label: 'AROM Rotation L (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_rotL'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_rotL_pain',
      label: 'Rotation L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_rotR_deg',
      label: 'AROM Rotation R (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_rotR'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_rotR_pain',
      label: 'Rotation R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_sbL_deg',
      label: 'AROM Sidebend L (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_sbL'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_sbL_pain',
      label: 'Sidebend L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_sbR_deg',
      label: 'AROM Sidebend R (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('cervical_sbR'),
    ),
    RegionFieldDefinition(
      key: 'cervical_arom_sbR_pain',
      label: 'Sidebend R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),

    // Upper cervical: flexion-rotation test L/R (deg + pain)
    RegionFieldDefinition(
      key: 'upper_cervical_frtL_deg',
      label: 'Upper cervical FRT L (deg)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'upper_cervical_frtL_pain',
      label: 'FRT L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'upper_cervical_frtR_deg',
      label: 'Upper cervical FRT R (deg)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'upper_cervical_frtR_pain',
      label: 'FRT R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),

    // Shoulder abduction relief sign (pos/neg)
    RegionFieldDefinition(
      key: 'shoulder_abduction_relief',
      label: 'Shoulder abduction relief sign',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Neuro: ULNT median/radial/ulnar (pos/neg/nt + notes)
    RegionFieldDefinition(
      key: 'ulnt_median_result',
      label: 'ULNT median',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'ulnt_median_notes',
      label: 'ULNT median notes',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'ulnt_radial_result',
      label: 'ULNT radial',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'ulnt_radial_notes',
      label: 'ULNT radial notes',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'ulnt_ulnar_result',
      label: 'ULNT ulnar',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'ulnt_ulnar_notes',
      label: 'ULNT ulnar notes',
      inputKind: RegionFieldInputKind.text,
    ),

    // DNF endurance (seconds)
    RegionFieldDefinition(
      key: 'dnf_endurance_sec',
      label: 'DNF endurance (sec)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Segmental mobility notes
    RegionFieldDefinition(
      key: 'segmental_mobility_notes',
      label: 'Segmental mobility notes',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.thoracic: [
    // AROM: rotL/rotR/ext (pain + notes)
    RegionFieldDefinition(
      key: 'thoracic_arom_rotL_pain',
      label: 'Rotation L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'thoracic_arom_rotR_pain',
      label: 'Rotation R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'thoracic_arom_ext_pain',
      label: 'Extension painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'thoracic_arom_notes',
      label: 'Thoracic AROM notes (deg / pattern)',
      inputKind: RegionFieldInputKind.text,
    ),

    // Rib mobility notes
    RegionFieldDefinition(
      key: 'rib_mobility_notes',
      label: 'Rib mobility notes',
      inputKind: RegionFieldInputKind.text,
    ),

    // Breathing pattern notes
    RegionFieldDefinition(
      key: 'breathing_pattern_notes',
      label: 'Breathing pattern notes',
      inputKind: RegionFieldInputKind.text,
    ),

    // PA spring levels
    RegionFieldDefinition(
      key: 'pa_spring_levels',
      label: 'PA spring levels / findings',
      inputKind: RegionFieldInputKind.text,
    ),

    // First rib tests
    RegionFieldDefinition(
      key: 'first_rib_tests',
      label: 'First rib tests (CRLF / spring)',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.lumbar: [
    // AROM: flex/ext/sbL/sbR/rotL/rotR (pain)
    RegionFieldDefinition(
      key: 'lumbar_arom_flex_pain',
      label: 'Flexion painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'lumbar_arom_ext_pain',
      label: 'Extension painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'lumbar_arom_sbL_pain',
      label: 'Sidebend L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'lumbar_arom_sbR_pain',
      label: 'Sidebend R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'lumbar_arom_rotL_pain',
      label: 'Rotation L painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'lumbar_arom_rotR_pain',
      label: 'Rotation R painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),

    // Repeated movements effect
    RegionFieldDefinition(
      key: 'repeated_movements_effect',
      label: 'Repeated movements effect',
      description: 'better / worse / no change',
      inputKind: RegionFieldInputKind.select,
      options: ['better', 'worse', 'no_change'],
    ),

    // SLR L/R (deg + symptoms)
    RegionFieldDefinition(
      key: 'slrL_deg',
      label: 'SLR L (deg)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'slrL_symptoms',
      label: 'SLR L symptoms',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'slrR_deg',
      label: 'SLR R (deg)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'slrR_symptoms',
      label: 'SLR R symptoms',
      inputKind: RegionFieldInputKind.text,
    ),

    // Slump L/R (pos/neg/nt)
    RegionFieldDefinition(
      key: 'slumpL_result',
      label: 'Slump L',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'slumpR_result',
      label: 'Slump R',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Myotomes/dermatomes/reflex summary strings
    RegionFieldDefinition(
      key: 'lumbar_myotomes_summary',
      label: 'Myotomes summary',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'lumbar_dermatomes_summary',
      label: 'Dermatomes summary',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'lumbar_reflexes_summary',
      label: 'Reflexes summary',
      inputKind: RegionFieldInputKind.text,
    ),

    // SIJ cluster
    RegionFieldDefinition(
      key: 'sij_distraction',
      label: 'SIJ distraction',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'sij_compression',
      label: 'SIJ compression',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'sij_thigh_thrust',
      label: 'SIJ thigh thrust',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'sij_sacral_thrust',
      label: 'SIJ sacral thrust',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'sij_gaenslen',
      label: 'SIJ Gaenslen',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Instability tests
    RegionFieldDefinition(
      key: 'instability_prone_instability',
      label: 'Prone instability test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'instability_passive_lumbar_extension',
      label: 'Passive lumbar extension',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
  ],

  BodyRegion.shoulder: [
    // AROM/PROM: flex/abd/ER/IR/HBB/HBH (pain)
    RegionFieldDefinition(
      key: 'shoulder_flex_deg',
      label: 'Flexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('shoulder_flex'),
    ),
    RegionFieldDefinition(
      key: 'shoulder_flex_pain',
      label: 'Flexion painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'shoulder_abd_deg',
      label: 'Abduction (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('shoulder_abd'),
    ),
    RegionFieldDefinition(
      key: 'shoulder_abd_pain',
      label: 'Abduction painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'shoulder_er_deg',
      label: 'External rotation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('shoulder_er'),
    ),
    RegionFieldDefinition(
      key: 'shoulder_er_pain',
      label: 'ER painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'shoulder_ir_deg',
      label: 'Internal rotation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('shoulder_ir'),
    ),
    RegionFieldDefinition(
      key: 'shoulder_ir_pain',
      label: 'IR painful?',
      inputKind: RegionFieldInputKind.boolean,
    ),
    RegionFieldDefinition(
      key: 'shoulder_hbb_level',
      label: 'Hand behind back (level)',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'shoulder_hbh_level',
      label: 'Hand behind head (level)',
      inputKind: RegionFieldInputKind.text,
    ),

    // Strength: ER/IR/abd/scaption (0-5)
    RegionFieldDefinition(
      key: 'strength_er_grade',
      label: 'Strength ER (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'strength_ir_grade',
      label: 'Strength IR (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'strength_abd_grade',
      label: 'Strength Abd (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'strength_scaption_grade',
      label: 'Strength Scaption (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Scapular dyskinesis notes
    RegionFieldDefinition(
      key: 'scapular_dyskinesis_notes',
      label: 'Scapular dyskinesis notes',
      inputKind: RegionFieldInputKind.text,
    ),

    // Impingement cluster
    RegionFieldDefinition(
      key: 'impingement_neer',
      label: 'Neer',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'impingement_hawkins',
      label: 'Hawkins-Kennedy',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'impingement_painful_arc',
      label: 'Painful arc',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Instability
    RegionFieldDefinition(
      key: 'instability_apprehension',
      label: 'Apprehension',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'instability_relocation',
      label: 'Relocation',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'instability_sulcus',
      label: 'Sulcus sign',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Labrum (optional)
    RegionFieldDefinition(
      key: 'labrum_obrien',
      label: "O'Brien",
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'labrum_biceps_load_ii',
      label: 'Biceps load II',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'labrum_crank',
      label: 'Crank',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
  ],

  BodyRegion.elbow: [
    // ROM
    RegionFieldDefinition(
      key: 'elbow_rom_flex_deg',
      label: 'Flexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('elbow_flex'),
    ),
    RegionFieldDefinition(
      key: 'elbow_rom_ext_deg',
      label: 'Extension (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('elbow_ext'),
    ),
    RegionFieldDefinition(
      key: 'elbow_rom_pro_deg',
      label: 'Pronation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('elbow_pro'),
    ),
    RegionFieldDefinition(
      key: 'elbow_rom_sup_deg',
      label: 'Supination (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('elbow_sup'),
    ),

    // Resisted tests
    RegionFieldDefinition(
      key: 'resisted_wrist_ext',
      label: 'Resisted wrist ext',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'resisted_wrist_flex',
      label: 'Resisted wrist flex',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'resisted_middle_finger',
      label: 'Resisted middle finger',
      inputKind: RegionFieldInputKind.text,
    ),

    // Neural: Tinel cubital
    RegionFieldDefinition(
      key: 'tinel_cubital',
      label: 'Tinel cubital',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Ligament: valgus/varus
    RegionFieldDefinition(
      key: 'valgus_stress',
      label: 'Valgus stress',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'varus_stress',
      label: 'Varus stress',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Palpation notes
    RegionFieldDefinition(
      key: 'elbow_palpation_notes',
      label: 'Palpation notes',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.wristHand: [
    // ROM
    RegionFieldDefinition(
      key: 'wrist_rom_flex_deg',
      label: 'Flexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_flex'),
    ),
    RegionFieldDefinition(
      key: 'wrist_rom_ext_deg',
      label: 'Extension (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_ext'),
    ),
    RegionFieldDefinition(
      key: 'wrist_rom_raddev_deg',
      label: 'Radial deviation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_raddev'),
    ),
    RegionFieldDefinition(
      key: 'wrist_rom_ulndev_deg',
      label: 'Ulnar deviation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_ulndev'),
    ),
    RegionFieldDefinition(
      key: 'wrist_rom_pronation_deg',
      label: 'Pronation (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_pronation'),
    ),
    RegionFieldDefinition(
      key: 'wrist_rom_supination_deg',
      label: 'Supination (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('wrist_supination'),
    ),

    // CTS tests
    RegionFieldDefinition(
      key: 'cts_phalen',
      label: 'Phalen',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'cts_tinel',
      label: 'Tinel (carpal tunnel)',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'cts_durkan',
      label: 'Durkan',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // DeQuervain
    RegionFieldDefinition(
      key: 'dequervain_finkelstein',
      label: 'Finkelstein',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Instability
    RegionFieldDefinition(
      key: 'instability_watson',
      label: 'Watson',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'instability_piano_key',
      label: 'Piano key',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Grip / pinch strength
    RegionFieldDefinition(
      key: 'grip_strength',
      label: 'Grip strength (kg or 0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'pinch_strength',
      label: 'Pinch strength (kg or 0–5)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Sensation notes
    RegionFieldDefinition(
      key: 'sensation_notes',
      label: 'Sensation notes',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.hip: [
    // AROM/PROM
    RegionFieldDefinition(
      key: 'hip_rom_flex_deg',
      label: 'Flexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_flex'),
    ),
    RegionFieldDefinition(
      key: 'hip_rom_ext_deg',
      label: 'Extension (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_ext'),
    ),
    RegionFieldDefinition(
      key: 'hip_rom_abd_deg',
      label: 'Abduction (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_abd'),
    ),
    RegionFieldDefinition(
      key: 'hip_rom_add_deg',
      label: 'Adduction (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_add'),
    ),
    RegionFieldDefinition(
      key: 'hip_rom_ir_deg',
      label: 'IR (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_ir'),
    ),
    RegionFieldDefinition(
      key: 'hip_rom_er_deg',
      label: 'ER (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('hip_er'),
    ),

    // Strength
    RegionFieldDefinition(
      key: 'hip_strength_abductors',
      label: 'Strength abductors (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'hip_strength_extensors',
      label: 'Strength extensors (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'hip_strength_ir',
      label: 'Strength IR (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),
    RegionFieldDefinition(
      key: 'hip_strength_er',
      label: 'Strength ER (0–5)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Trendelenburg
    RegionFieldDefinition(
      key: 'trendelenburg',
      label: 'Trendelenburg',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // FABER/FADIR/Scour
    RegionFieldDefinition(
      key: 'faber',
      label: 'FABER',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'fadir',
      label: 'FADIR',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'scour',
      label: 'Scour',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Thomas/Ober
    RegionFieldDefinition(
      key: 'thomas_test',
      label: 'Thomas test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'ober_test',
      label: 'Ober test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Palpation notes
    RegionFieldDefinition(
      key: 'hip_palpation_notes',
      label: 'Palpation notes (GT, etc.)',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.knee: [
    // ROM
    RegionFieldDefinition(
      key: 'knee_rom_flex_deg',
      label: 'Flexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('knee_flex'),
    ),
    RegionFieldDefinition(
      key: 'knee_rom_ext_deg',
      label: 'Extension (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('knee_ext'),
    ),

    // Effusion
    RegionFieldDefinition(
      key: 'effusion_stroke_test',
      label: 'Stroke test grade',
      inputKind: RegionFieldInputKind.text,
    ),

    // Ligaments
    RegionFieldDefinition(
      key: 'lig_lachman',
      label: 'Lachman',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'lig_ant_drawer',
      label: 'Anterior drawer',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'lig_post_drawer',
      label: 'Posterior drawer',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'lig_valgus',
      label: 'Valgus',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'lig_varus',
      label: 'Varus',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Meniscus
    RegionFieldDefinition(
      key: 'meniscus_mcmurray',
      label: 'McMurray',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'meniscus_thessaly',
      label: 'Thessaly',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'meniscus_jlt',
      label: 'Joint line tenderness',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // PF
    RegionFieldDefinition(
      key: 'pf_apprehension',
      label: 'Patellar apprehension',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'pf_clarkes',
      label: "Clarke's test",
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Functional
    RegionFieldDefinition(
      key: 'functional_squat',
      label: 'Squat notes',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'functional_step_down',
      label: 'Step-down notes',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.ankleFoot: [
    // ROM
    RegionFieldDefinition(
      key: 'ankle_rom_df_deg',
      label: 'Dorsiflexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('ankle_df'),
    ),
    RegionFieldDefinition(
      key: 'ankle_rom_pf_deg',
      label: 'Plantarflexion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('ankle_pf'),
    ),
    RegionFieldDefinition(
      key: 'ankle_rom_inv_deg',
      label: 'Inversion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('ankle_inv'),
    ),
    RegionFieldDefinition(
      key: 'ankle_rom_ev_deg',
      label: 'Eversion (deg)',
      inputKind: RegionFieldInputKind.number,
      romNormal: romNormalForKey('ankle_ev'),
    ),

    // Lateral ligaments
    RegionFieldDefinition(
      key: 'latlig_anterior_drawer',
      label: 'Anterior drawer',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'latlig_talar_tilt',
      label: 'Talar tilt',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Syndesmosis
    RegionFieldDefinition(
      key: 'syndesmosis_squeeze',
      label: 'Squeeze test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),
    RegionFieldDefinition(
      key: 'syndesmosis_er_stress',
      label: 'External rotation stress',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Achilles
    RegionFieldDefinition(
      key: 'achilles_thompson',
      label: 'Thompson test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Plantar fascia
    RegionFieldDefinition(
      key: 'plantar_fascia_windlass',
      label: 'Windlass test',
      inputKind: RegionFieldInputKind.select,
      options: ['pos', 'neg', 'nt'],
    ),

    // Foot posture
    RegionFieldDefinition(
      key: 'foot_posture_navicular_drop_mm',
      label: 'Navicular drop (mm)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Single leg calf raise reps
    RegionFieldDefinition(
      key: 'single_leg_calf_raise_reps',
      label: 'Single leg calf raise (reps)',
      inputKind: RegionFieldInputKind.number,
    ),

    // Balance test notes
    RegionFieldDefinition(
      key: 'balance_test_notes',
      label: 'Balance test notes',
      inputKind: RegionFieldInputKind.text,
    ),
  ],

  BodyRegion.other: [
    RegionFieldDefinition(
      key: 'generic_rom_notes',
      label:
          'ROM summary (list directions & degrees, use normal ranges as reference)',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'generic_strength_notes',
      label: 'Strength summary (0–5)',
      inputKind: RegionFieldInputKind.text,
    ),
    RegionFieldDefinition(
      key: 'generic_key_tests_notes',
      label: 'Key tests notes (plus registry tests below)',
      inputKind: RegionFieldInputKind.text,
    ),
  ],
};

