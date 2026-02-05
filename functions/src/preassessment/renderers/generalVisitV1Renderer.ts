type AnswerMap = Record<string, any>;

function safeStr(v: unknown): string {
  return (v ?? "").toString().trim();
}

// ✅ No replaceAll (works on older TS libs/targets too)
function escapeHtml(s: string): string {
  const str = (s ?? "").toString();
  return str.replace(/[&<>"']/g, (ch) => {
    switch (ch) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      case "'":
        return "&#039;";
      default:
        return ch;
    }
  });
}

function readText(answers: AnswerMap, qid: string): string {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "text") return safeStr(a.v);
  return "";
}

function readSingle(answers: AnswerMap, qid: string): string {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "single") return safeStr(a.v);
  return "";
}

function readMulti(answers: AnswerMap, qid: string): string[] {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "multi" && Array.isArray(a.v)) {
    return a.v.map((x: any) => safeStr(x)).filter(Boolean);
  }
  return [];
}

function readBool(answers: AnswerMap, qid: string): boolean | null {
  const a = answers[qid];
  if (a && typeof a === "object" && a.t === "bool") return a.v === true;
  return null;
}

function yn(v: boolean | null): string {
  if (v === true) return "Yes";
  if (v === false) return "No";
  return "—";
}

function joinOrDash(items: string[]): string {
  return items.length ? items.join(", ") : "—";
}

// OptionId -> label maps (must match your Dart maps)
const concernClarityLabels: Record<string, string> = {
  "concern.single": "One main concern",
  "concern.multiple": "Multiple concerns",
  "concern.unsure": "Not sure",
};

const bodyAreaLabels: Record<string, string> = {
  "area.neck": "Neck",
  "area.upperBack": "Upper back",
  "area.lowerBack": "Lower back",
  "area.shoulder": "Shoulder",
  "area.elbow": "Elbow",
  "area.wristHand": "Wrist/Hand",
  "area.hip": "Hip",
  "area.knee": "Knee",
  "area.ankleFoot": "Ankle/Foot",
  "area.multiple": "Multiple areas",
  "area.general": "General / whole body",
};

const primaryImpactLabels: Record<string, string> = {
  "impact.work": "Work",
  "impact.sport": "Sport / exercise",
  "impact.sleep": "Sleep",
  "impact.dailyActivities": "Daily activities",
  "impact.generalMovement": "General movement",
  "impact.unclear": "Not sure",
};

const limitedActivityLabels: Record<string, string> = {
  "activity.sitting": "Sitting",
  "activity.standing": "Standing",
  "activity.walking": "Walking",
  "activity.lifting": "Lifting / carrying",
  "activity.exercise": "Exercise",
  "activity.workTasks": "Work tasks",
  "activity.sleep": "Sleep",
  "activity.other": "Other",
};

const durationLabels: Record<string, string> = {
  "duration.days": "Days",
  "duration.weeks": "Weeks",
  "duration.months": "Months",
  "duration.years": "Years",
  "duration.unsure": "Not sure",
};

const visitIntentLabels: Record<string, string> = {
  "intent.understanding": "Understand what’s going on",
  "intent.reassurance": "Reassurance",
  "intent.guidance": "Guidance",
  "intent.nextSteps": "Next steps",
  "intent.returnToActivity": "Return to activity",
  "intent.unsure": "Not sure",
};

function labelSingle(id: string, map: Record<string, string>): string {
  if (!id) return "—";
  return map[id] ?? id;
}

function labelsMulti(ids: string[], map: Record<string, string>): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of ids) {
    const id = safeStr(raw);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(map[id] ?? id);
  }
  return out;
}

export function renderGeneralVisitV1Html(input: {
  clinicId: string;
  clinicName: string;
  sessionId: string;
  submittedAt: Date;
  schemaVersion: number;
  clinicLogoUrl?: string;
  patient: { fullName: string; email: string; phone: string };
  answers: AnswerMap;
}): string {
  const {
    clinicName,
    sessionId,
    submittedAt,
    schemaVersion,
    clinicLogoUrl,
    patient,
    answers,
  } = input;

  const reason = readText(answers, "generalVisit.goals.reasonForVisit");
  const clarity = labelSingle(
    readSingle(answers, "generalVisit.meta.concernClarity"),
    concernClarityLabels
  );
  const areas = labelsMulti(
    readMulti(answers, "generalVisit.history.bodyAreas"),
    bodyAreaLabels
  );
  const impact = labelSingle(
    readSingle(answers, "generalVisit.function.primaryImpact"),
    primaryImpactLabels
  );
  const limited = labelsMulti(
    readMulti(answers, "generalVisit.function.limitedActivities"),
    limitedActivityLabels
  );
  const duration = labelSingle(
    readSingle(answers, "generalVisit.history.duration"),
    durationLabels
  );
  const intent = labelsMulti(
    readMulti(answers, "generalVisit.goals.visitIntent"),
    visitIntentLabels
  );

  const ackNE = yn(readBool(answers, "consent.notEmergency.ack"));
  const ackND = yn(readBool(answers, "consent.noDiagnosis.ack"));

  const submittedAtLocal = submittedAt.toISOString(); // you can format in clinic TZ if you store it

  // HTML template: keep it identical to your earlier template structure
  return `
<html lang="en">
  <body style="font-family: Arial, sans-serif; background:#f9fafb; padding:24px;">
    <div style="max-width:760px; margin:0 auto; background:#ffffff; border-radius:10px; overflow:hidden; border:1px solid #e5e7eb;">

      <div style="padding:20px 24px; border-bottom:1px solid #e5e7eb;">
        <div style="display:flex; align-items:center; justify-content:space-between; gap:16px;">
          <div>
            <h1 style="margin:0; font-size:18px;">Visit Context Questionnaire</h1>
            <p style="margin:6px 0 0; color:#6b7280; font-size:12px;">
              Flow: <strong>generalVisit.v1</strong> · Patient-reported intake snapshot (Phase 3)
            </p>
          </div>
          ${
            clinicLogoUrl
              ? `<img src="${escapeHtml(clinicLogoUrl)}" alt="${escapeHtml(
                  clinicName
                )}" style="max-height:44px; object-fit:contain;" />`
              : ""
          }
        </div>
      </div>

      <div style="padding:16px 24px; background:#fef3c7; border-bottom:1px solid #e5e7eb;">
        <p style="margin:0; font-size:12px; color:#92400e; line-height:1.45;">
          <strong>Important:</strong> This document contains information reported by the patient.
          It does not provide a diagnosis or treatment plan. If symptoms are severe, sudden, or urgent,
          seek emergency medical care.
        </p>
      </div>

      <div style="padding:18px 24px;">
        <h2 style="margin:0 0 10px; font-size:14px;">Submission details</h2>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <tr><td style="padding:6px 0; color:#6b7280; width:180px;">Clinic</td><td style="padding:6px 0;">${escapeHtml(
            clinicName
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">Intake session ID</td><td style="padding:6px 0;">${escapeHtml(
            sessionId
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">Submitted at</td><td style="padding:6px 0;">${escapeHtml(
            submittedAtLocal
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">Schema version</td><td style="padding:6px 0;">${schemaVersion}</td></tr>
        </table>
      </div>

      <div style="padding:0 24px 18px;">
        <h2 style="margin:0 0 10px; font-size:14px;">Patient details (reported)</h2>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <tr><td style="padding:6px 0; color:#6b7280; width:180px;">Name</td><td style="padding:6px 0;">${escapeHtml(
            patient.fullName || "—"
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">Email</td><td style="padding:6px 0;">${escapeHtml(
            patient.email || "—"
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">Phone</td><td style="padding:6px 0;">${escapeHtml(
            patient.phone || "—"
          )}</td></tr>
        </table>
      </div>

      <div style="padding:0 24px 18px;">
        <h2 style="margin:0 0 10px; font-size:14px;">Visit context</h2>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">What made you book this visit?</div>
          <div style="margin-top:6px; font-size:12px; white-space:pre-wrap;">${escapeHtml(
            reason || "—"
          )}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.goals.reasonForVisit</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">Is it one concern or multiple?</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(clarity)}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.meta.concernClarity</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">Areas involved (broad)</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(
            joinOrDash(areas)
          )}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.history.bodyAreas</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">Main impact</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(impact)}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.function.primaryImpact</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">Activities affected (optional)</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(
            joinOrDash(limited)
          )}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.function.limitedActivities</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px; margin-bottom:10px;">
          <div style="color:#6b7280; font-size:12px;">How long has this been going on?</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(duration)}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.history.duration</div>
        </div>

        <div style="padding:12px; border:1px solid #e5e7eb; border-radius:10px;">
          <div style="color:#6b7280; font-size:12px;">What would you like from the visit?</div>
          <div style="margin-top:6px; font-size:12px;">${escapeHtml(
            joinOrDash(intent)
          )}</div>
          <div style="margin-top:6px; color:#9ca3af; font-size:11px;">ID: generalVisit.goals.visitIntent</div>
        </div>
      </div>

      <div style="padding:0 24px 22px;">
        <h2 style="margin:0 0 10px; font-size:14px;">Acknowledgements</h2>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <tr><td style="padding:6px 0; color:#6b7280; width:360px;">Not an emergency (acknowledged)</td><td style="padding:6px 0;">${escapeHtml(
            ackNE
          )}</td></tr>
          <tr><td style="padding:6px 0; color:#6b7280;">No diagnosis from this questionnaire (acknowledged)</td><td style="padding:6px 0;">${escapeHtml(
            ackND
          )}</td></tr>
        </table>
        <div style="margin-top:10px; color:#9ca3af; font-size:11px;">
          IDs: consent.notEmergency.ack · consent.noDiagnosis.ack
        </div>
      </div>

      <div style="padding:14px 24px; border-top:1px solid #e5e7eb; color:#9ca3af; font-size:11px;">
        Generated by the platform as an immutable Phase 3 intake snapshot.
      </div>
    </div>
  </body>
</html>
  `.trim();
}
