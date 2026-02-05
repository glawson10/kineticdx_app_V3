// general_visit_v1_maps.dart
//
// Stable optionId -> human label maps for generalVisit.v1.
// UI labels can change later; optionIds must not.
//
// Matches canonical optionId rules. :contentReference[oaicite:3]{index=3}

const Map<String, String> gvConcernClarityLabels = {
  'concern.single': 'One main concern',
  'concern.multiple': 'Multiple concerns',
  'concern.unsure': 'Not sure',
};

const Map<String, String> gvBodyAreaLabels = {
  'area.neck': 'Neck',
  'area.upperBack': 'Upper back',
  'area.lowerBack': 'Lower back',
  'area.shoulder': 'Shoulder',
  'area.elbow': 'Elbow',
  'area.wristHand': 'Wrist/Hand',
  'area.hip': 'Hip',
  'area.knee': 'Knee',
  'area.ankleFoot': 'Ankle/Foot',
  'area.multiple': 'Multiple areas',
  'area.general': 'General / whole body',
};

const Map<String, String> gvPrimaryImpactLabels = {
  'impact.work': 'Work',
  'impact.sport': 'Sport / exercise',
  'impact.sleep': 'Sleep',
  'impact.dailyActivities': 'Daily activities',
  'impact.generalMovement': 'General movement',
  'impact.unclear': 'Not sure',
};

const Map<String, String> gvLimitedActivityLabels = {
  'activity.sitting': 'Sitting',
  'activity.standing': 'Standing',
  'activity.walking': 'Walking',
  'activity.lifting': 'Lifting / carrying',
  'activity.exercise': 'Exercise',
  'activity.workTasks': 'Work tasks',
  'activity.sleep': 'Sleep',
  'activity.other': 'Other',
};

const Map<String, String> gvDurationLabels = {
  'duration.days': 'Days',
  'duration.weeks': 'Weeks',
  'duration.months': 'Months',
  'duration.years': 'Years',
  'duration.unsure': 'Not sure',
};

const Map<String, String> gvVisitIntentLabels = {
  'intent.understanding': 'Understand what’s going on',
  'intent.reassurance': 'Reassurance',
  'intent.guidance': 'Guidance',
  'intent.nextSteps': 'Next steps',
  'intent.returnToActivity': 'Return to activity',
  'intent.unsure': 'Not sure',
};
