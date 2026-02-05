/// Patient-facing label map (Phase 3)
const Map<String, String> lumbarLabelsV1 = {
  // Titles
  'lumbar.title': 'Lower back',
  'lumbar.description': 'Answer a few questions to help your clinician prepare.',

  // Red flags (asked first)
  'lumbar.redflags.bladderBowelChange':
      'Have you noticed any new problems controlling your bladder or bowels?',
  'lumbar.redflags.saddleAnaesthesia':
      'Do you have any numbness around the groin/saddle area?',
  'lumbar.redflags.progressiveWeakness':
      'Is weakness in your leg/foot getting worse quickly?',
  'lumbar.redflags.feverUnwell':
      'Have you had fever or chills, or felt unusually unwell with this pain?',
  'lumbar.redflags.historyOfCancer':
      'Have you ever been treated for cancer?',
  'lumbar.redflags.recentTrauma':
      'Did this start after a significant fall, accident, or injury?',
  'lumbar.redflags.constantNightPain':
      'Is your pain constant and not eased by rest (including at night)?',

  // Pain
  'lumbar.pain.now': 'Pain right now (0–10)',
  'lumbar.pain.worst24h': 'Worst pain in the last 24 hours (0–10)',

  // Context
  'lumbar.context.ageBand': 'What is your age group?',
  'age.18_35': '18–35',
  'age.36_50': '36–50',
  'age.51_65': '51–65',
  'age.65plus': '65+',

  // History
  'lumbar.history.timeSinceStart': 'How long have you had this problem?',
  'time.lt48h': 'Less than 48 hours',
  'time.2_14d': '2–14 days',
  'time.2_6wk': '2–6 weeks',
  'time.gt6wk': 'More than 6 weeks',

  'lumbar.history.onset': 'How did it start?',
  'onset.sudden': 'Suddenly',
  'onset.gradual': 'Gradually',
  'onset.recurrent': 'It comes and goes / recurring',

  // Symptoms
  'lumbar.symptoms.painPattern': 'Where is the pain mainly felt?',
  'pattern.central': 'Mainly central lower back',
  'pattern.oneSide': 'Mostly one side',
  'pattern.bothSides': 'Both sides',

  'lumbar.symptoms.whereLeg': 'If you have leg symptoms, where do you feel them?',
  'where.none': 'No leg symptoms',
  'where.buttock': 'Buttock',
  'where.thigh': 'Thigh',
  'where.belowKnee': 'Below the knee',
  'where.foot': 'Foot',

  'lumbar.symptoms.pinsNeedles': 'Do you have pins and needles/tingling?',
  'lumbar.symptoms.numbness': 'Do you have numbness?',

  'lumbar.symptoms.aggravators': 'What tends to make it worse?',
  'aggs.none': 'None of these',
  'aggs.bendLift': 'Bending forward or lifting',
  'aggs.coughSneeze': 'Coughing or sneezing',
  'aggs.walk': 'Walking',
  'aggs.extend': 'Arching backwards / extending',
  'aggs.sitProlonged': 'Sitting for a long time',
  'aggs.stand': 'Standing',

  'lumbar.symptoms.easers': 'What tends to make it feel better?',
  'eases.none': 'Nothing in particular',
  'eases.backArched': 'Standing/arching backwards (if it helps)',
  'eases.lieKneesBent': 'Lying on your back with knees bent',
  'eases.shortWalk': 'A short gentle walk',

  // Function
  'lumbar.function.gaitAbility': 'How is your walking right now?',
  'gait.normal': 'Normal',
  'gait.limp': 'I’m limping',
  'gait.support': 'I need support (stick/rail/person)',
  'gait.cannot': 'I can’t walk',

  'lumbar.function.dayImpact': 'How much does this affect your day-to-day? (0–10)',

  // Narrative
  'lumbar.history.additionalInfo':
      'Anything else you want your clinician to know (cause, progression, treatments so far)?',
};
