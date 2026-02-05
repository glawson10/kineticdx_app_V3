1) Canonical questionId format
Required format
{flowId}.{domain}.{concept}[.{detail}]


Examples

consent.privacy.accepted

patient.email

region.selected

ankle.pain.now

ankle.redflags.nightPain

ankle.function.stairs

Rules

Lower camelCase for segments after the first dot (e.g., nightPain, worst24h)

No spaces, no hyphens

No UI/screen references (screen3, page2) — IDs must represent meaning, not navigation

No version numbers inside the questionId (versioning lives in flowVersion)

2) Namespace rules (what prefixes exist)

Even though consent + patient details are “before region”, we still store them in the same intake doc. IDs should clearly separate them:

Reserved prefixes

consent.* (policy understanding + acceptance)

patient.* (patient-reported details)

region.* (routing selection)

{flowId}.* for regional workshops (e.g., ankle.*, knee.*)

This makes summary generation and Phase 5 “keyAnswers” extraction trivial and safe.

3) Domain taxonomy (standard categories)

To prevent drift, domains are fixed and reused across flows.

Recommended domain list

meta (timestamps, optional internal flow markers — minimal)

pain

symptoms

history

redflags

function

lifestyle

goals

msk (only if needed; keep rare)

tests (Phase 3 may suggest test categories, not outcomes)

Examples

ankle.history.onset

ankle.pain.worst24h

ankle.symptoms.swelling

ankle.redflags.trauma

ankle.function.walking

ankle.goals.freeText

ankle.tests.balanceCategorySelected (category only)

4) Concept naming rules

Concept segment should describe meaning, not UI.

✅ Good

ankle.pain.now

ankle.pain.worst24h

ankle.history.onset

ankle.redflags.neuroSymptoms

ankle.function.run

❌ Bad

ankle.q12

ankle.slider1

ankle.step5Answer

5) Options must be stable (optionId rules)

For choice questions, store optionId, not display text.

OptionId format
{concept}.{option}


Examples:

For ankle.history.onset:

onset.sudden

onset.gradual

onset.unknown

For ankle.side (if asked in flow):

side.left

side.right

side.bilateral

Never store UI labels like “Sudden onset” as the value. Labels can change; IDs must not.

6) Answer typing rules (strict, typed union)

Keep the typed wrapper you already agreed to:

type AnswerValue =
  | { t: "bool", v: boolean }
  | { t: "int", v: number }
  | { t: "num", v: number }
  | { t: "text", v: string }
  | { t: "single", v: string }    // optionId
  | { t: "multi", v: string[] }   // optionIds
  | { t: "date", v: string }      // yyyy-mm-dd (metadata, not queries)
  | { t: "map", v: Record<string, any> }; // rare escape hatch

Type selection rules (canonical)

Pain scales 0–10 → int

ankle.pain.now: {t:"int", v: 6}

Percent sliders → int (0–100)

Yes/No → bool

Single choice → single (stores optionId)

Multi choice → multi (stores optionIds)

Free text → text (trimmed, max length enforced)

Dates (rare) → date as yyyy-mm-dd

Never use num for pain scales (keeps them consistent for summaries/triage)

The “map” escape hatch

Only for structured composite answers that would otherwise explode into many separate keys (use sparingly). Example: body chart selections (later).

If you find yourself using map often — we should instead define specific questionIds.

7) Required “core” questionIds (the minimum set)

These should exist in every intake session (even if some values are null/empty in draft):

Consent

consent.terms.accepted → bool

consent.privacy.accepted → bool

consent.dataStorage.accepted → bool

consent.notEmergency.ack → bool

consent.noDiagnosis.ack → bool

Patient details

patient.firstName → text

patient.lastName → text

patient.dateOfBirth → date OR store in patientDetails.dateOfBirth Timestamp only (pick one strategy; I recommend Timestamp in the block, not answers)

patient.email → text (or empty)

patient.phone → text (or empty)

Region selection

region.bodyArea → single (e.g., region.ankle)

region.side → single (e.g., side.left)

(Even though region is stored in regionSelection, having these IDs makes summaries and exports consistent. If you prefer not to duplicate, we can skip these IDs and rely on the block fields — but pick one and stay consistent.)

8) Flow-level required questionIds (per region)

Each region flow must include these baseline IDs (so clinician screens are consistent across regions):

{flowId}.pain.now → int (0–10)

{flowId}.pain.worst24h → int (0–10)

{flowId}.history.onset → single (onset.sudden|gradual|unsure)

{flowId}.redflags.any → bool (computed from red flag set OR asked directly — your choice)

{flowId}.function.primaryLimit → single (optional but recommended)

Then region-specific extras add on.

9) Backward compatibility & versioning rules
You may add new questionIds anytime

Adding is non-breaking

No schema bump needed

Might bump flowVersion if triage logic depends on it

You must NEVER change meaning of an existing questionId

If meaning changes, you must:

introduce a new questionId

bump flowVersion

keep reading old questionId for old sessions

You must NEVER change the stored type for an existing questionId

If type changes (e.g., int → single), you must:

create a new questionId

bump flowVersion

This is what keeps Phase 3 snapshots legally stable 

2. PHASE_3_INTAKE

 and makes Phase 5 referencing safe 

3. PHASE_3_TO_5_HANDOFF

.

10) “Key answers” extraction contract (for clinician list + Phase 5 reference)

Define a tiny whitelist per flow version:

Example for ankle.v1:

ankle.pain.now

ankle.pain.worst24h

ankle.history.onset

ankle.redflags.nightPain

ankle.redflags.neuroSymptoms

ankle.function.walking

This list becomes:

clinician intake list preview

clinician intake detail “highlights”

the only safe subset Phase 5 may reference (patient-reported) 

3. PHASE_3_TO_5_HANDOFF