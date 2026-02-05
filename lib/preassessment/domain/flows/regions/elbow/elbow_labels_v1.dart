const Map<String, String> elbowLabelsV1 = {
  'elbow.title': 'Elbow',
  'elbow.description': 'Answer a few questions to help your clinician prepare.',

  // -------------------------------------------------------------------------
  // Red flags (asked first)
  // -------------------------------------------------------------------------
  'elbow.redflags.trauma':
      'Did this start after a significant injury or fall onto the arm?',
  'elbow.redflags.injuryForce':
      'Was there a strong force to the elbow (fall, collision, sudden twist, heavy load)?',
  'elbow.redflags.rapidSwelling':
      'Did the elbow swell up quickly after the injury?',
  'elbow.redflags.visibleDeformity':
      'Does the elbow look deformed or “out of place”?',
  'elbow.redflags.canStraighten':
      'Can you fully straighten the elbow?',
  'elbow.redflags.fever':
      'Do you have a fever or feel generally unwell with this elbow pain?',
  'elbow.redflags.infectionRisk':
      'Do you have a wound, recent injection, or a medical condition that increases infection risk?',
  'elbow.redflags.hotSwollenNoFever':
      'Is the elbow hot, very swollen, and painful without having a fever?',
  'elbow.redflags.neuroDeficit':
      'Do you have new numbness, tingling, or weakness in the hand or fingers?',

  // -------------------------------------------------------------------------
  // Context
  // -------------------------------------------------------------------------
  'elbow.context.side': 'Which elbow is affected?',
  'side.left': 'Left',
  'side.right': 'Right',
  'side.both': 'Both',
  'side.unsure': 'Not sure',

  'elbow.context.dominantSide': 'Which is your dominant hand?',
  'dom.left': 'Left',
  'dom.right': 'Right',
  'dom.unsure': 'Not sure',

  // -------------------------------------------------------------------------
  // Pain
  // -------------------------------------------------------------------------
  'elbow.pain.now': 'Pain right now (0–10)',
  'elbow.pain.worst24h': 'Worst pain in the last 24 hours (0–10)',

  // -------------------------------------------------------------------------
  // History
  // -------------------------------------------------------------------------
  'elbow.history.onset': 'How did this start?',
  'onset.gradual': 'Gradually over time',
  'onset.afterLoad': 'After repeated loading or overuse',
  'onset.afterTrauma': 'After an injury or sudden force',
  'onset.unsure': 'Not sure',

  // -------------------------------------------------------------------------
  // Symptoms
  // -------------------------------------------------------------------------
  'elbow.symptoms.painLocation': 'Where is the main pain?',
  'loc.lateral': 'Outer elbow (thumb side)',
  'loc.medial': 'Inner elbow (little-finger side)',
  'loc.posterior': 'Back of the elbow',
  'loc.anterior': 'Front of the elbow',
  'loc.diffuse': 'Hard to localise / general area',

  'elbow.symptoms.grippingPain': 'Is it painful with gripping?',
  'elbow.symptoms.stiffness': 'Does the elbow feel stiff?',
  'elbow.symptoms.swelling': 'Have you noticed swelling around the elbow?',
  'elbow.symptoms.swellingAfterActivity':
      'Does the elbow swell after activity or use?',
  'elbow.symptoms.clickSnap': 'Do you notice clicking or snapping?',
  'elbow.symptoms.catching': 'Does the elbow catch, lock, or feel stuck?',
  'elbow.symptoms.morningStiffness': 'Is it stiff first thing in the morning?',
  'elbow.symptoms.popAnterior':
      'Have you felt or heard a “pop” at the front of the elbow?',
  'elbow.symptoms.forearmThumbSidePain':
      'Do you get pain down the forearm on the thumb side?',
  'elbow.symptoms.paraUlnar':
      'Pins and needles or numbness in the ring and little finger?',
  'elbow.symptoms.paraThumbIndex':
      'Pins and needles or numbness in the thumb and index finger?',
  'elbow.symptoms.neckRadiation':
      'Does neck movement change your elbow or arm symptoms?',
  'elbow.symptoms.pronationPain':
      'Is it painful turning the palm down (like using a screwdriver)?',
  'elbow.symptoms.resistedExtensionPain':
      'Is it painful when you straighten the elbow against resistance?',
  'elbow.symptoms.throwValgusPain':
      'Do throwing or overhead movements cause pain on the inner elbow?',
  'elbow.symptoms.posteromedialEndRangeExtensionPain':
      'Does it hurt at the back/inner elbow when fully straightening the arm?',

  // -------------------------------------------------------------------------
  // Function
  // -------------------------------------------------------------------------
  'elbow.function.aggravators': 'Which activities make it worse? (Select all)',
  'aggs.palmDownGrip': 'Gripping with palm down (e.g., lifting a bag)',
  'aggs.twistJar': 'Twisting (e.g., opening a jar)',
  'aggs.palmUpCarry': 'Carrying with palm up (e.g., holding a tray)',
  'aggs.overheadThrow': 'Throwing or overhead activities',
  'aggs.restOnOlecranon': 'Leaning/resting on the point of the elbow',
  'aggs.pushUpWB': 'Pushing through the arm (push-up / getting up from chair)',
  'aggs.none': 'None of these',

  'elbow.function.dayImpact': 'How much does this affect your day?',
  'impact.none': 'Not at all',
  'impact.mild': 'A little',
  'impact.moderate': 'Moderately',
  'impact.severe': 'Severely',

  // -------------------------------------------------------------------------
  // Other
  // -------------------------------------------------------------------------
  'elbow.history.additionalInfo':
      'Anything else you want your clinician to know? (Optional)',
};
