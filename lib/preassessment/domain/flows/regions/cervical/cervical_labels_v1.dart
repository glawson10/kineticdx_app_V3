const Map<String, String> cervicalLabelsV1 = {
  // ---------------------------------------------------------------------------
  // PAGE 1 — RED FLAGS / SAFETY (FIRST)
  // ---------------------------------------------------------------------------

  // Canadian C-spine / trauma risk factors
  'cervical.redflags.age65plus': 'Are you 65 years old or older?',
  'cervical.redflags.highSpeedCrash':
      'Did this start after a high-speed accident (e.g. high-speed car crash, e-bike/motorbike crash, being struck)?',
  'cervical.redflags.majorTrauma':
      'Did this start after a major accident or trauma (e.g. car accident, fall)?',
  'cervical.redflags.paresthesiaPostIncident':
      'After the incident, did you notice pins and needles / tingling in your arms or hands?',
  'cervical.redflags.unableWalkImmediately':
      'After the incident, were you unable to walk (even briefly)?',
  'cervical.redflags.immediateNeckPain':
      'Did you feel neck pain immediately after the incident?',
  'cervical.redflags.rotationLt45Both':
      'Right now, can you turn your head left AND right at least halfway (about 45°) without severe pain?',

  // Neuro / myelopathy style flags
  'cervical.redflags.progressiveNeurology':
      'Have your symptoms been getting progressively worse?',
  'cervical.redflags.widespreadNeuroDeficit':
      'Do you have widespread numbness/tingling or weakness (e.g. affecting both arms, or an arm and a leg)?',
  'cervical.redflags.armWeakness': 'Do you have weakness in your arm or hand?',
  'cervical.redflags.balanceOrWalkingIssues':
      'Have you had problems with balance or walking?',
  'cervical.redflags.handClumsiness':
      'Have you noticed clumsiness with your hands (e.g. dropping things, difficulty with buttons or writing)?',
  'cervical.redflags.bowelBladderChange':
      'Have you noticed changes in bladder or bowel control?',

  // Inflammatory/systemic style flags
  'cervical.redflags.nightPain':
      'Is your neck pain worse at night or does it wake you from sleep?',
  'cervical.redflags.morningStiffnessOver30min':
      'Do you have morning stiffness that lasts more than 30 minutes?',

  'cervical.redflags.systemicSymptoms':
      'Have you experienced any of the following recently?',
  'systemic.fever': 'Fever or chills',
  'systemic.unexplainedWeightLoss': 'Unexplained weight loss',
  'systemic.feelsUnwell': 'Feeling generally unwell',

  // Vascular / CAD cluster
  'cervical.redflags.visualDisturbance':
      'Have you had any new or unusual visual changes (e.g. blurred vision, double vision, loss of vision)?',
  'cervical.redflags.cadCluster':
      'Have you had a combination of concerning symptoms such as severe unusual headache, dizziness, nausea, fainting, trouble speaking, or facial numbness?',

  // ---------------------------------------------------------------------------
  // PAGE 2 — PAIN
  // ---------------------------------------------------------------------------

  'cervical.pain.now': 'How painful is your neck right now? (0–10)',
  'cervical.pain.worst24h':
      'What was the worst pain in the last 24 hours? (0–10)',

  // ---------------------------------------------------------------------------
  // PAGE 3 — HISTORY
  // ---------------------------------------------------------------------------

  'cervical.history.onset': 'How did this problem start?',
  'onset.sudden': 'Suddenly',
  'onset.gradual': 'Gradually',
  'onset.unsure': 'Not sure',

  'cervical.history.timeSinceStart': 'How long have you had this problem?',

  // Narrative
  'cervical.history.additionalInfo':
      'Anything else you think we should know about your neck problem?',

  // ---------------------------------------------------------------------------
  // PAGE 4 — SYMPTOMS (SCORING INPUTS)
  // ---------------------------------------------------------------------------

  // Pain distribution
  'cervical.symptoms.painLocation': 'Where is your neck pain mainly located?',
  'painLocation.central': 'Mainly in the centre of the neck',
  'painLocation.oneSide': 'Mainly on one side of the neck',
  'painLocation.bothSides': 'On both sides of the neck',

  // Arm symptoms (existing multi)
  'cervical.symptoms.armSymptoms':
      'Do you have any symptoms in your arm or hand?',
  'arm.numbness': 'Numbness',
  'arm.tingling': 'Pins and needles / tingling',
  'arm.weakness': 'Weakness',
  'arm.none': 'No arm symptoms',

  // Engine-required symptom booleans
  'cervical.symptoms.painIntoShoulder':
      'Does the pain spread into your shoulder (top of shoulder area)?',
  'cervical.symptoms.painBelowElbow':
      'Does the pain spread below your elbow into your forearm or hand?',
  'cervical.symptoms.armTingling':
      'Do you currently have pins and needles / tingling in your arm or hand?',
  'cervical.symptoms.coughSneezeWorse':
      'Does coughing or sneezing make your neck/arm symptoms worse?',
  'cervical.symptoms.neckMovementWorse':
      'Do neck movements make your symptoms worse?',

  // Headache + modifiers
  'cervical.symptoms.headache':
      'Do you get headaches that seem related to your neck pain?',
  'cervical.symptoms.headacheOneSide':
      'Are your headaches usually on one side?',
  'cervical.symptoms.headacheWorseWithNeck':
      'Do your headaches get worse with neck movement or sustained neck posture?',
  'cervical.symptoms.headacheBetterWithNeckCare':
      'Do your headaches improve when your neck symptoms are treated (e.g. rest, heat, massage, exercises)?',

  // Keep existing symptom items (still useful clinically)
  'cervical.symptoms.dizzinessOrVisual':
      'Have you experienced dizziness or visual disturbances?',
  'cervical.symptoms.nightOrConstantPain':
      'Is the pain constant or worse at night?',

  // ---------------------------------------------------------------------------
  // PAGE 5 — FUNCTION
  // ---------------------------------------------------------------------------

  'cervical.function.dayImpact':
      'How much does this affect your daily activities? (0–10)',
};
