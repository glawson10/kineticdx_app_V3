// functions/src/index.ts
import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

// ─────────────────────────────
// Firebase init (ONLY ONCE)
// ─────────────────────────────
if (!admin.apps.length) admin.initializeApp();

// ─────────────────────────────
// Region (single source of truth)
// ─────────────────────────────
const REGION = "europe-west3";

// ─────────────────────────────
// Runtime service account (workaround)
// ─────────────────────────────
const RUNTIME_SA = "326894670032-compute@developer.gserviceaccount.com";

// ─────────────────────────────
// Secrets (MUST be declared in index for v2 analysis)
// ─────────────────────────────
export const BREVO_API_KEY = defineSecret("BREVO_API_KEY");

// ─────────────────────────────
// Schema versions
// ─────────────────────────────
import { SCHEMA_VERSIONS } from "./schema/schemaVersions";

// ─────────────────────────────
// Clinic / membership
// ─────────────────────────────
import { createClinic } from "./clinic/createClinic";
import { inviteMember } from "./clinic/inviteMember";
import { acceptInvite } from "./clinic/acceptInvite";
import { updateClinicProfile } from "./clinic/updateClinicProfile";
import { setMembershipStatus } from "./clinic/setMembershipStatus";
import { syncMyDisplayName } from "./clinic/syncMyDisplayName";
import { updateMemberProfile } from "./clinic/updateMemberProfile";
import { upsertStaffProfile } from "./clinic/staff/upsertStaffProfile";
import { setStaffAvailabilityDefault } from "./clinic/staff/setStaffAvailabilityDefault";

// ─────────────────────────────
// Closures
// ─────────────────────────────
import { createClosure } from "./clinic/closures/createClosure";
import { deleteClosure } from "./clinic/closures/deleteClosure";

// ─────────────────────────────
// Booking / patients / episodes
// ─────────────────────────────
import { createAppointment } from "./clinic/createAppointment";
import { deleteAppointment } from "./clinic/deleteAppointment";
import { updateAppointment } from "./clinic/updateAppointment";
import { updateAppointmentStatus } from "./clinic/updateAppointmentStatus";

import { createPatient } from "./clinic/patients/createPatient";
import { updatePatient } from "./clinic/patients/updatePatient";
import { mergePatients } from "./clinic/patients/mergePatients";
import { deletePatient } from "./clinic/patients/deletePatient";

import { createEpisode } from "./clinic/episode/createEpisode";
import { updateEpisode } from "./clinic/episode/updateEpisode";
import { closeEpisode } from "./clinic/episode/closeEpisode";

// ─────────────────────────────
// Clinical notes
// ─────────────────────────────
import { createClinicalNote } from "./clinic/notes/createClinicalNote";
import { amendClinicalNote } from "./clinic/notes/amendClinicalNote";

// ─────────────────────────────
// Registries
// ─────────────────────────────
import { upsertClinicalTest } from "./clinic/registries/upsertClinicalTest";
import { deleteClinicalTest } from "./clinic/registries/deleteClinicalTest";
import { upsertOutcomeMeasure } from "./clinic/registries/upsertOutcomeMeasure";
import { deleteOutcomeMeasure } from "./clinic/registries/deleteOutcomeMeasure";

// ─────────────────────────────
// Assessments
// ─────────────────────────────
import { submitAssessment } from "./clinic/assessments/submitAssessment";
import { generateAssessmentPdf } from "./clinic/assessments/generateAssessmentPdf";
import { getAssessmentPack } from "./clinic/assessments/getAssessmentPack";



// ─────────────────────────────
// Intake / decision support
// ─────────────────────────────
import { submitIntakeSession } from "./clinic/intake/submitIntakeSession";
export { computeIntakeSummaryV2 } from "./clinic/intake/computeIntakeSummary";
export * from "./clinic/intake/computeDecisionSupport";
import { createGeneralQuestionnaireLinkFn } from "./intake/createGeneralQuestionnaireLinkFn";
import { resolveIntakeLinkTokenFn } from "./intake/resolveIntakeLinkTokenFn";

// ─────────────────────────────
// Audit exports
// ─────────────────────────────
import { exportClosureOverrideAuditReport } from "./clinic/audit/exportClosureOverrideAuditReport";

// ─────────────────────────────
// Public booking
// ─────────────────────────────
import { bootstrapPublicBookingSettings } from "./clinic/bootstrapPublicBookingSettings";
import { listPublicSlotsFn } from "./public/listPublicSlots";
import {
  getManageContext,
  cancelBookingWithToken,
  rescheduleBookingWithToken,
} from "./public/bookingActions";

// ─────────────────────────────
// Callable exports
// ─────────────────────────────

// Debug / platform
export const getSchemaVersionsFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  async () => ({ ok: true, versions: SCHEMA_VERSIONS })
);

// Clinic
export const clinicCreateFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createClinic
);

export const updateMemberProfileFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updateMemberProfile
);

export const inviteMemberFn = onCall(
  { region: REGION, cors: true, secrets: [BREVO_API_KEY], serviceAccount: RUNTIME_SA },
  inviteMember
);

export const acceptInviteFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  acceptInvite
);

export const updateClinicProfileFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updateClinicProfile
);

export const setMembershipStatusFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  setMembershipStatus
);

export const syncMyDisplayNameFn = onCall(
  { region: REGION, cors: true },
  (req: CallableRequest) => syncMyDisplayName(req)
);

export { updateClinicWeeklyHoursFn } from "./clinic/settings/updateClinicWeeklyHours";


// Staff
export const upsertStaffProfileFn = onCall(
  { region: REGION, cors: true },
  upsertStaffProfile
);

export const setStaffAvailabilityDefaultFn = onCall(
  { region: REGION, cors: true },
  setStaffAvailabilityDefault
);

// Closures
export const createClosureFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createClosure
);

export const deleteClosureFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  deleteClosure
);

// Booking
export const createAppointmentFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createAppointment
);

export const deleteAppointmentFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  deleteAppointment
);

export const updateAppointmentFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updateAppointment
);

export const updateAppointmentStatusFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updateAppointmentStatus
);

// Patients
export const createPatientFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createPatient
);

export const updatePatientFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updatePatient
);

export const mergePatientsFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  mergePatients
);

export const deletePatientFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  deletePatient
);

// Episodes
export const createEpisodeFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createEpisode
);

export const updateEpisodeFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  updateEpisode
);

export const closeEpisodeFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  closeEpisode
);

// Clinical notes
export const createClinicalNoteFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  createClinicalNote
);

export const amendClinicalNoteFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  amendClinicalNote
);

// Registries
export const upsertClinicalTestFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  upsertClinicalTest
);

export const deleteClinicalTestFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  deleteClinicalTest
);

export const upsertOutcomeMeasureFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  upsertOutcomeMeasure
);

export const deleteOutcomeMeasureFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  deleteOutcomeMeasure
);

// Assessments
export const submitAssessmentFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  submitAssessment
);

export const getAssessmentPackFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  getAssessmentPack
);

export const generateAssessmentPdfFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  generateAssessmentPdf
);

// Intake
export const submitIntakeSessionFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  submitIntakeSession
);
export { createGeneralQuestionnaireLinkFn, resolveIntakeLinkTokenFn };

// Audit
export const exportClosureOverrideAuditReportFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  exportClosureOverrideAuditReport
);

// ─────────────────────────────
// Triggers / background
// ─────────────────────────────
export { onBookingRequestCreateV2 } from "./clinic/booking/onBookingRequestCreate";
export { onPublicBookingSettingsWrite } from "./public/onPublicBookingSettingsWrite";
export { onAppointmentWrite_toBusyBlock } from "./availability/onAppointmentWrite_toBusyBlock";
export { mirrorPractitionerToPublic } from "./projections/practitionerPublicMirror";

// ─────────────────────────────
// Public booking (NO AUTH)
// ─────────────────────────────
export { listPublicSlotsFn };
export const getManageContextFn = getManageContext;
export const cancelBookingWithTokenFn = cancelBookingWithToken;
export const rescheduleBookingWithTokenFn = rescheduleBookingWithToken;

export { testCallable } from "./testCallable";
export { onClinicCreatedProvisionDefaults } from "./clinic/settings/provisionClinicDefaults";
export { backfillNotificationsSettings } from "./clinic/settings/backfillNotifications";
export { consumeIntakeInviteFn } from "./intake/consumeIntakeInviteFn";

export const bootstrapPublicBookingSettingsFn = onCall(
  { region: REGION, cors: true, serviceAccount: RUNTIME_SA },
  bootstrapPublicBookingSettings
);
export { createBookingRequestFn } from "./clinic/booking/createBookingRequestFn";
export { intakePdfOnSubmit } from "./preassessment/intakePdfOnSubmit";

export {
  resolveIntakeSessionFromBookingRequestFn,
} from "./preassessment/resolveIntakeSessionFromBookingRequestFn";

export { onClinicCreatedProvisionOwnerMembership } from "./clinic/onClinicCreatedProvisionOwner";
