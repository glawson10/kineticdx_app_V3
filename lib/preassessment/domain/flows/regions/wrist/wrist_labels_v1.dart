const Map<String, String> wristLabelsV1 = {
  // Title/description
  'wrist.title': 'Wrist / hand',
  'wrist.description': 'Answer a few questions to help your clinician prepare.',

  // Red flags
  'wrist.redflags.systemic':
      'Have you experienced any of the following?',
  'system.fever': 'Fever or chills',
  'system.wtloss': 'Unexplained weight loss',
  'system.both_hands_tingles': 'Tingling in both hands',
  'system.extreme_colour_temp': 'Extreme colour/temperature changes in the hand',
  'system.constant_night': 'Constant pain or pain worse at night',

  'wrist.redflags.acuteInjury':
      'Did this start after a specific injury or accident?',
  'injury.yes': 'Yes',
  'injury.no': 'No',

  'wrist.redflags.injuryCluster':
      'If yes, did any of these happen at the time of injury?',
  'inj.no_weight_bear': 'Could not use the hand/wrist at all',
  'inj.pop_crack': 'Pop/crack at the time',
  'inj.deformity': 'Visible deformity',
  'inj.severe_pain': 'Severe pain immediately',
  'inj.immediate_numb': 'Immediate numbness after injury',

  // Context
  'wrist.context.side': 'Which side is affected?',
  'side.left': 'Left',
  'side.right': 'Right',
  'side.both': 'Both',
  'side.unsure': 'Not sure',

  // Zone
  'wrist.symptoms.zone': 'Where is the main pain?',
  'zone.radial': 'Thumb side (radial)',
  'zone.ulnar': 'Little finger side (ulnar)',
  'zone.dorsal': 'Back of wrist/hand (dorsal)',
  'zone.volar': 'Palm side (volar)',
  'zone.diffuse': 'Hard to pinpoint / widespread',

  // Onset
  'wrist.history.onset': 'How did it start?',
  'onset.sudden': 'Suddenly',
  'onset.gradual': 'Gradually',
  'onset.unsure': 'Not sure',

  // Mechanism
  'wrist.history.mechanism': 'What might have contributed to this?',
  'mech.foosh': 'Fall onto an outstretched hand',
  'mech.twist': 'Twist/awkward movement',
  'mech.typing': 'Repetitive typing/mouse use',
  'mech.grip_lift': 'Heavy gripping / lifting',

  // Aggravators
  'wrist.symptoms.aggravators': 'What tends to make it worse?',
  'aggs.typing': 'Typing / mouse use',
  'aggs.grip_lift': 'Gripping or lifting',
  'aggs.weight_bear': 'Weight bearing through the hand (push-ups, getting up from chair)',
  'aggs.twist': 'Twisting (opening jars, turning keys)',

  // Features
  'wrist.symptoms.features': 'Have you noticed any of these?',
  'feat.swelling': 'Swelling',
  'feat.bump_shape': 'A lump or change in shape',
  'feat.clicking': 'Clicking or clunking',
  'feat.weak_grip': 'Weak grip',
  'feat.tingle_thumb_index': 'Tingling in thumb/index finger',
  'feat.extreme_colour_temp': 'Extreme colour/temperature changes',

  // Weight bearing
  'wrist.function.weightBear':
      'Can you weight bear through the hand/wrist?',
  'wb.yes_ok': 'Yes, without much trouble',
  'wb.yes_pain': 'Yes, but it’s painful',
  'wb.no': 'No, I can’t',

  // Risks
  'wrist.context.risks': 'Any of the following apply?',
  'risk.post_meno': 'Post-menopausal',
  'risk.preg_postpartum': 'Pregnant or recently postpartum',

  // Narrative
  'wrist.history.additionalInfo':
      'Anything else you want your clinician to know (cause, progression, treatments so far)?',
};
