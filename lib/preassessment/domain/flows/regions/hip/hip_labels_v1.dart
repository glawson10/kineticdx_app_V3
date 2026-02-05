const Map<String, String> hipLabelsV1 = {
  'hip.title': 'Hip',
  'hip.description': 'Answer a few questions to help your clinician prepare.',

  // Red flags
  'hip.redflags.highEnergyTrauma':
      'Did this start after a major fall, accident, or high-impact injury?',
  'hip.redflags.feverUnwell':
      'Have you had a fever or felt unusually unwell with this pain?',
  'hip.redflags.historyOfCancer': 'Have you ever been treated for cancer?',
  'hip.redflags.constantNightPain':
      'Is the pain constant and not eased by rest, including at night?',
  'hip.redflags.unableToWeightBear':
      'Are you unable to put weight through the leg at all?',

  // Side
  'hip.context.side': 'Which side is affected?',
  'side.left': 'Left',
  'side.right': 'Right',
  'side.both': 'Both',
  'side.unsure': 'Not sure',

  // Age
  'hip.context.ageBand': 'What is your age group?',
  'age.18_35': '18–35',
  'age.36_50': '36–50',
  'age.51_65': '51–65',
  'age.65plus': '65+',

  // Pain
  'hip.pain.now': 'Pain right now (0–10)',
  'hip.pain.worst24h': 'Worst pain in the last 24 hours (0–10)',

  // Location
  'hip.symptoms.painLocation': 'Where is the pain mainly felt?',
  'loc.groin': 'Groin / front of hip',
  'loc.outer': 'Outer side of hip',
  'loc.buttock': 'Buttock',
  'loc.diffuse': 'Hard to pinpoint / widespread',

  'hip.symptoms.groinPain': 'Do you have pain in the groin area?',
  'hip.symptoms.clickingCatching':
      'Do you notice clicking, catching, or locking?',
  'hip.symptoms.stiffness': 'Does the hip feel stiff?',

  // Behaviour
  'hip.symptoms.aggravators': 'What tends to make it worse?',
  'aggs.walk': 'Walking',
  'aggs.stairs': 'Going up or down stairs',
  'aggs.sitLong': 'Sitting for a long time',
  'aggs.twist': 'Twisting or pivoting',
  'aggs.run': 'Running',
  'aggs.none': 'None of these',

  'hip.symptoms.easers': 'What tends to make it feel better?',
  'eases.rest': 'Rest',
  'eases.shortWalk': 'Short gentle walk',
  'eases.heat': 'Heat',
  'eases.none': 'Nothing in particular',

  // Function
  'hip.function.gaitAbility': 'How is your walking?',
  'gait.normal': 'Normal',
  'gait.limp': 'Limping',
  'gait.support': 'Need support',
  'gait.cannot': 'Cannot walk',

  'hip.function.dayImpact': 'How much does this affect your day-to-day? (0–10)',

  // Narrative
  'hip.history.additionalInfo':
      'Anything else you want your clinician to know (cause, progression, treatments so far)?',

  // NEW red flags
  'hip.redflags.fallImpact':
      'Did this start after a fall or direct impact onto the hip?',
  'hip.redflags.tinyMovementAgony':
      'Is the pain extremely severe even with tiny movements of the hip/leg?',
  'hip.redflags.under16NewLimp':
      'Are you under 16 with a new limp or new hip/groin/knee pain?',
  'hip.redflags.amberRisks': 'Do any of these apply to you?',
  'risks.immunosuppression': 'Immunosuppression / reduced immunity',
  'risks.steroidUse': 'Regular steroid use',
  'risks.diabetes': 'Diabetes',
  'risks.other': 'Other significant medical risk factor',
  'risks.none': 'None of these',

  // NEW age bands
  'age.under16': 'Under 16',
  'age.16_17': '16–17',

  // NEW history
  'hip.history.onset': 'How did this start?',
  'onset.sudden': 'Sudden (hours–days)',
  'onset.gradual': 'Gradual (weeks–months)',
  'onset.unsure': 'Not sure',
  'hip.history.dysplasiaHistory':
      'Have you ever been told you have hip dysplasia/structural hip issues?',
  'hip.history.hypermobilityHistory':
      'Have you been told you are hypermobile / very flexible (or have a hypermobility diagnosis)?',

  // NEW sleep/irritability/features
  'hip.symptoms.sleep': 'Does this affect your sleep?',
  'sleep.none': 'No',
  'sleep.wakesSide': 'Wakes me when lying on the sore side',
  'sleep.wakesOther': 'Wakes me, but not specifically on the sore side',

  'hip.symptoms.irritabilityOn': 'How quickly does pain come on with activity?',
  'irritOn.immediate': 'Immediately',
  'irritOn.afterMinutes': 'After a few minutes',
  'irritOn.afterHours': 'After a longer time',
  'irritOn.variable': 'Varies / unsure',

  'hip.symptoms.irritabilityOff': 'How quickly does it settle after you stop?',
  'irritOff.minutes': 'Within minutes',
  'irritOff.hours': 'Within hours',
  'irritOff.days': 'Over days',
  'irritOff.doesNotSettle': 'Does not really settle',

  'hip.symptoms.pinsNeedles':
      'Any pins and needles, numbness, or shooting symptoms down the leg?',
  'hip.symptoms.coughStrain':
      'Does coughing/sneezing/straining worsen the pain?',
  'hip.symptoms.reproducibleSnapping':
      'Can you reproduce a snap/click at the front or side of the hip with movement?',
  'hip.symptoms.sitBonePain':
      'Is the pain mainly at the “sit bone” area (deep buttock/ischial area)?',

  // NEW aggravators
  'aggs.standWalk': 'Standing or walking (load-related)',
  'aggs.sideLying': 'Lying on the sore side',
};
