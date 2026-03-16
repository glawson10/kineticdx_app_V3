// functions/src/index.ts
import * as admin from "firebase-admin";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
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
import { upsertLocation } from "./clinic/settings/upsertLocation";
import { setLocationActive } from "./clinic/settings/setLocationActive";
import { updateLocationWeeklyHours } from "./clinic/settings/updateLocationWeeklyHours";
import { upsertAppointmentType } from "./clinic/settings/upsertAppointmentType";
import { setAppointmentTypeActive } from "./clinic/settings/setAppointmentTypeActive";
import { updateCalendarDisplayConfig } from "./clinic/settings/updateCalendarDisplayConfig";
import { getCalendarDisplayConfig } from "./clinic/settings/getCalendarDisplayConfig";
import { getClinicProfile } from "./clinic/settings/getClinicProfile";
import { getClosures } from "./clinic/settings/getClosures";
import { getMembership } from "./clinic/settings/getMembership";
import { listMembers } from "./clinic/settings/listMembers";
import { listLocations } from "./clinic/settings/listLocations";
import { listAppointmentTypes } from "./clinic/settings/listAppointmentTypes";
import { getPublicBookingConfig } from "./clinic/settings/getPublicBookingConfig";
import { getCommunicationSettings } from "./clinic/settings/getCommunicationSettings";
import { updatePublicBookingConfig } from "./clinic/settings/updatePublicBookingConfig";
import { updateOnlineBookingEnablement } from "./clinic/settings/updateOnlineBookingEnablement";
import { updateLocationDisplayOrder } from "./clinic/settings/updateLocationDisplayOrder";
import { updateCommunicationSettings } from "./clinic/settings/updateCommunicationSettings";
import { upsertPractitionerAvailability } from "./clinic/settings/upsertPractitionerAvailability";
import { deletePractitionerAvailability } from "./clinic/settings/deletePractitionerAvailability";
import { upsertPractitionerOverride } from "./clinic/settings/upsertPractitionerOverride";
import { deletePractitionerOverride } from "./clinic/settings/deletePractitionerOverride";
import { setMembershipStatus } from "./clinic/setMembershipStatus";
import { updateMember } from "./clinic/updateMember";
import { syncMyDisplayName } from "./clinic/syncMyDisplayName";
import { updateMemberProfile } from "./clinic/updateMemberProfile";
import { upsertStaffProfile } from "./clinic/staff/upsertStaffProfile";
import { setStaffAvailabilityDefault } from "./clinic/staff/setStaffAvailabilityDefault";
import { upsertPractitionerBookingMeta } from "./clinic/staff/upsertPractitionerBookingMeta";

// ─────────────────────────────
// Closures
// ─────────────────────────────
import { createClosure } from "./clinic/closures/createClosure";
import { deleteClosure } from "./clinic/closures/deleteClosure";

// ─────────────────────────────
// Booking / patients / episodes
// ─────────────────────────────
import { createAppointment } from "./clinic/createAppointment";
import { createAppointmentSeries } from "./clinic/appointments/createAppointmentSeries";
import { cancelAppointment } from "./clinic/cancelAppointment";
import { deleteAppointment } from "./clinic/deleteAppointment";
import { updateAppointment } from "./clinic/updateAppointment";
import { updateAppointmentOccurrence } from "./clinic/appointments/updateAppointmentOccurrence";
import { updateAppointmentSeries } from "./clinic/appointments/updateAppointmentSeries";
import { splitAppointmentSeries } from "./clinic/appointments/splitAppointmentSeries";
import { updateAppointmentStatus } from "./clinic/updateAppointmentStatus";

import { createPatient } from "./clinic/patients/createPatient";
import { updatePatient } from "./clinic/patients/updatePatient";
import { mergePatients } from "./clinic/patients/mergePatients";
import { deletePatient } from "./clinic/patients/deletePatient";
import { listPatientsForBookingFn } from "./clinic/patients/listPatientsForBooking";

import { createEpisode } from "./clinic/episode/createEpisode";
import { updateEpisode } from "./clinic/episode/updateEpisode";
import { closeEpisode } from "./clinic/episode/closeEpisode";

// ─────────────────────────────
// Clinical notes
// ─────────────────────────────
import { createClinicalNote } from "./clinic/notes/createClinicalNote";
import { amendClinicalNote } from "./clinic/notes/amendClinicalNote";
import { finalizeSoapNote, unfinalizeSoapNote } from "./clinic/notes/finalizeSoapNote";

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
// Billing
// ─────────────────────────────
import { createCharge } from "./clinic/billing/createCharge";
import { createInvoiceDraft } from "./clinic/billing/createInvoiceDraft";
import { createInvoice } from "./clinic/billing/createInvoice";
import { updateInvoice } from "./clinic/billing/updateInvoice";
import { createInvoiceFromAppointment } from "./clinic/billing/createInvoiceFromAppointment";
import { issueInvoice } from "./clinic/billing/issueInvoice";
import { recordManualPayment } from "./clinic/billing/recordManualPayment";
import { recordPayment } from "./clinic/billing/recordPayment";
import { issueCreditNote } from "./clinic/billing/issueCreditNote";
import { refundPayment } from "./clinic/billing/refundPayment";
import { updateBillingSettings } from "./clinic/billing/updateBillingSettings";
import { createStripePaymentIntent } from "./clinic/billing/createStripePaymentIntent";
import { handleStripeWebhook } from "./clinic/billing/stripeWebhook";
import { generateInvoicePdf, getInvoicePdfDownloadUrl } from "./clinic/billing/generateInvoicePdf";
import { upsertTax } from "./clinic/billing/upsertTax";
import { upsertPaymentType } from "./clinic/billing/upsertPaymentType";
import { upsertBillableItem } from "./clinic/billing/upsertBillableItem";
import { upsertProduct } from "./clinic/billing/upsertProduct";
import { createInvoicePaymentLink } from "./clinic/billing/createInvoicePaymentLink";
import { getBillingSummary } from "./clinic/billing/getBillingSummary";
import { getBillingJurisdiction } from "./clinic/billing/getBillingJurisdiction";
import { getAgedReceivables } from "./clinic/billing/getAgedReceivables";
import { updatePricingSettings } from "./clinic/billing/updatePricingSettings";
import { resolvePricingForAppointment } from "./clinic/billing/resolvePricingForAppointment";



// ─────────────────────────────
// Intake / decision support
// ─────────────────────────────
import { submitIntakeSession } from "./clinic/intake/submitIntakeSession";
export { computeIntakeSummaryV2 } from "./clinic/intake/computeIntakeSummary";
export * from "./clinic/intake/computeDecisionSupport";
import { createGeneralQuestionnaireLinkFn } from "./intake/createGeneralQuestionnaireLinkFn";
import { createQuestionnaireLaunchLinkFn } from "./intake/createQuestionnaireLaunchLinkFn";
import { resolveIntakeLinkTokenFn } from "./intake/resolveIntakeLinkTokenFn";
import {
  listQuestionnaireTemplatesFn,
  updateQuestionnaireTemplateFn,
} from "./clinic/questionnaires/listQuestionnaireTemplatesFn";

// ─────────────────────────────
// Audit exports
// ─────────────────────────────
import { exportClosureOverrideAuditReport } from "./clinic/audit/exportClosureOverrideAuditReport";

// ─────────────────────────────
// Public booking
// ─────────────────────────────
import { bootstrapPublicBookingSettings } from "./clinic/bootstrapPublicBookingSettings";
import {
  listPublicSlotsFn,
  getPublicMonthAvailabilityFn,
  getPublicBookingPractitionersFn,
  getPublicBookingLocationsFn,
  getPublicBookingAppointmentTypesFn,
  getPublicBookingDiagnosticsFn,
} from "./public/listPublicSlots";
import {
  getManageContext,
  cancelBookingWithToken,
  rescheduleBookingWithToken,
} from "./public/bookingActions";
import { runPublicBookingMirrorForClinic, onPractitionerWritten } from "./public/mirrorPublicBooking";

// ─────────────────────────────
// Callable exports
// ─────────────────────────────

// Debug / platform
export const getSchemaVersionsFn = onCall(
  { region: REGION, cors: true },
  async () => ({ ok: true, versions: SCHEMA_VERSIONS })
);

// Clinic
export const clinicCreateFn = onCall(
  { region: REGION, cors: true },
  createClinic
);

export const updateMemberProfileFn = onCall(
  { region: REGION, cors: true },
  updateMemberProfile
);

export const inviteMemberFn = onCall(
  { region: REGION, cors: true, secrets: [BREVO_API_KEY] },
  inviteMember
);

export const acceptInviteFn = onCall(
  { region: REGION, cors: true },
  acceptInvite
);

// Commit 04: settings.* callable naming (filterable in logs)
export const settingsUpdateClinicProfile = onCall(
  { region: REGION, cors: true },
  updateClinicProfile
);
// Legacy alias for backward compatibility
export const updateClinicProfileFn = onCall(
  { region: REGION, cors: true },
  updateClinicProfile
);

export const settingsUpsertLocation = onCall(
  { region: REGION, cors: true },
  upsertLocation
);
export const settingsSetLocationActive = onCall(
  { region: REGION, cors: true },
  setLocationActive
);
export const settingsUpdateLocationWeeklyHours = onCall(
  { region: REGION, cors: true },
  updateLocationWeeklyHours
);
export const settingsUpsertAppointmentType = onCall(
  { region: REGION, cors: true },
  upsertAppointmentType
);
export const settingsSetAppointmentTypeActive = onCall(
  { region: REGION, cors: true },
  setAppointmentTypeActive
);
export const settingsUpdateCalendarDisplayConfig = onCall(
  { region: REGION, cors: true },
  updateCalendarDisplayConfig
);
export const settingsGetCalendarDisplayConfig = onCall(
  { region: REGION, cors: true },
  getCalendarDisplayConfig
);
export const settingsGetClinicProfile = onCall(
  { region: REGION, cors: true },
  getClinicProfile
);
export const settingsGetMembership = onCall(
  { region: REGION, cors: true },
  getMembership
);
export const settingsGetClosures = onCall(
  { region: REGION, cors: true },
  getClosures
);
export const settingsListMembers = onCall(
  { region: REGION, cors: true },
  listMembers
);
export const settingsListLocations = onCall(
  { region: REGION, cors: true },
  listLocations
);
export const settingsListAppointmentTypes = onCall(
  { region: REGION, cors: true },
  listAppointmentTypes
);
export const settingsGetPublicBookingConfig = onCall(
  { region: REGION, cors: true },
  getPublicBookingConfig
);
export const settingsGetCommunicationSettings = onCall(
  { region: REGION, cors: true },
  getCommunicationSettings
);
export const settingsUpdatePublicBookingConfig = onCall(
  { region: REGION, cors: true },
  updatePublicBookingConfig
);
export const settingsUpdateOnlineBookingEnablement = onCall(
  { region: REGION, cors: true },
  updateOnlineBookingEnablement
);
export const settingsUpdateLocationDisplayOrder = onCall(
  { region: REGION, cors: true },
  updateLocationDisplayOrder
);
/** Rebuild public booking mirror (practitioners, locations, appointment types). Requires settings.write. */
export const rebuildPublicBookingMirrorFn = onCall(
  { region: REGION, cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = String((request.data as any)?.clinicId ?? "").trim();
    if (!clinicId) {
      throw new HttpsError("invalid-argument", "clinicId is required.");
    }
    const { requireClinicPermission } = await import("./clinic/permissions");
    await requireClinicPermission(admin.firestore(), clinicId, request.auth.uid, "settings.write");
    await runPublicBookingMirrorForClinic(clinicId);
    return { ok: true, clinicId };
  }
);
export const settingsUpdateCommunicationSettings = onCall(
  { region: REGION, cors: true },
  updateCommunicationSettings
);
export const settingsUpsertPractitionerAvailability = onCall(
  { region: REGION, cors: true },
  upsertPractitionerAvailability
);
export const settingsDeletePractitionerAvailability = onCall(
  { region: REGION, cors: true },
  deletePractitionerAvailability
);
export const settingsUpsertPractitionerOverride = onCall(
  { region: REGION, cors: true },
  upsertPractitionerOverride
);
export const settingsDeletePractitionerOverride = onCall(
  { region: REGION, cors: true },
  deletePractitionerOverride
);

export const upsertPractitionerBookingMetaFn = onCall(
  { region: REGION, cors: true },
  upsertPractitionerBookingMeta
);

export const setMembershipStatusFn = onCall(
  { region: REGION, cors: true },
  setMembershipStatus
);

export const updateMemberFn = onCall(
  { region: REGION, cors: true },
  updateMember
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
  { region: REGION, cors: true },
  createClosure
);

export const deleteClosureFn = onCall(
  { region: REGION, cors: true },
  deleteClosure
);

// Booking
export const createAppointmentFn = onCall(
  { region: REGION, cors: true },
  createAppointment
);

export const createAppointmentSeriesFn = onCall(
  { region: REGION, cors: true },
  createAppointmentSeries
);

export const deleteAppointmentFn = onCall(
  { region: REGION, cors: true },
  deleteAppointment
);

export const updateAppointmentFn = onCall(
  { region: REGION, cors: true },
  updateAppointment
);

export const updateAppointmentOccurrenceFn = onCall(
  { region: REGION, cors: true },
  updateAppointmentOccurrence
);

export const updateAppointmentSeriesFn = onCall(
  { region: REGION, cors: true },
  updateAppointmentSeries
);

export const splitAppointmentSeriesFn = onCall(
  { region: REGION, cors: true },
  splitAppointmentSeries
);

export const updateAppointmentStatusFn = onCall(
  { region: REGION, cors: true },
  updateAppointmentStatus
);

export const cancelAppointmentFn = onCall(
  { region: REGION, cors: true },
  cancelAppointment
);

// Patients
export const createPatientFn = onCall(
  { region: REGION, cors: true },
  createPatient
);

export const updatePatientFn = onCall(
  { region: REGION, cors: true },
  updatePatient
);

export const mergePatientsFn = onCall(
  { region: REGION, cors: true },
  mergePatients
);

export const deletePatientFn = onCall(
  { region: REGION, cors: true },
  deletePatient
);

export { listPatientsForBookingFn };

// Episodes
export const createEpisodeFn = onCall(
  { region: REGION, cors: true },
  createEpisode
);

export const updateEpisodeFn = onCall(
  { region: REGION, cors: true },
  updateEpisode
);

export const closeEpisodeFn = onCall(
  { region: REGION, cors: true },
  closeEpisode
);

// Clinical notes
export const createClinicalNoteFn = onCall(
  { region: REGION, cors: true },
  createClinicalNote
);

export const amendClinicalNoteFn = onCall(
  { region: REGION, cors: true },
  amendClinicalNote
);

export const finalizeSoapNoteFn = onCall(
  { region: REGION, cors: true },
  finalizeSoapNote
);

export const unfinalizeSoapNoteFn = onCall(
  { region: REGION, cors: true },
  unfinalizeSoapNote
);

// Registries
export const upsertClinicalTestFn = onCall(
  { region: REGION, cors: true },
  upsertClinicalTest
);

export const deleteClinicalTestFn = onCall(
  { region: REGION, cors: true },
  deleteClinicalTest
);

export const upsertOutcomeMeasureFn = onCall(
  { region: REGION, cors: true },
  upsertOutcomeMeasure
);

export const deleteOutcomeMeasureFn = onCall(
  { region: REGION, cors: true },
  deleteOutcomeMeasure
);

// Assessments
export const submitAssessmentFn = onCall(
  { region: REGION, cors: true },
  submitAssessment
);

export const getAssessmentPackFn = onCall(
  { region: REGION, cors: true },
  getAssessmentPack
);

export const generateAssessmentPdfFn = onCall(
  { region: REGION, cors: true },
  generateAssessmentPdf
);

// Billing
export const billingCreateChargeFn = onCall(
  { region: REGION, cors: true },
  createCharge
);

export const billingCreateInvoiceDraftFn = onCall(
  { region: REGION, cors: true },
  createInvoiceDraft
);

export const billingCreateInvoiceFn = onCall(
  { region: REGION, cors: true },
  createInvoice
);

export const billingUpdateInvoiceFn = onCall(
  { region: REGION, cors: true },
  updateInvoice
);

export const billingCreateInvoiceFromAppointmentFn = onCall(
  { region: REGION, cors: true },
  createInvoiceFromAppointment
);

export const billingIssueInvoiceFn = onCall(
  { region: REGION, cors: true },
  issueInvoice
);

export const billingRecordManualPaymentFn = onCall(
  { region: REGION, cors: true },
  recordManualPayment
);

export const billingRecordPaymentFn = onCall(
  { region: REGION, cors: true },
  recordPayment
);

export const billingIssueCreditNoteFn = onCall(
  { region: REGION, cors: true },
  issueCreditNote
);

export const billingRefundPaymentFn = onCall(
  { region: REGION, cors: true },
  refundPayment
);

export const billingUpdateSettingsFn = onCall(
  { region: REGION, cors: true },
  updateBillingSettings
);

export const billingUpdatePricingSettingsFn = onCall(
  { region: REGION, cors: true },
  updatePricingSettings
);

export const billingResolvePricingForAppointmentFn = onCall(
  { region: REGION, cors: true },
  resolvePricingForAppointment
);

export const settingsUpsertTax = onCall(
  { region: REGION, cors: true },
  upsertTax
);

export const settingsUpsertPaymentType = onCall(
  { region: REGION, cors: true },
  upsertPaymentType
);

export const settingsUpsertBillableItem = onCall(
  { region: REGION, cors: true },
  upsertBillableItem
);

export const settingsUpsertProduct = onCall(
  { region: REGION, cors: true },
  upsertProduct
);

export const billingCreateStripePaymentIntentFn = onCall(
  { region: REGION, cors: true },
  createStripePaymentIntent
);

export const billingCreateInvoicePaymentLinkFn = onCall(
  { region: REGION, cors: true },
  createInvoicePaymentLink
);

export const billingGenerateInvoicePdfFn = onCall(
  { region: REGION, cors: true, memory: "2GiB" as const, timeoutSeconds: 120 },
  generateInvoicePdf
);

export const billingGetInvoicePdfDownloadUrlFn = onCall(
  { region: REGION, cors: true },
  getInvoicePdfDownloadUrl
);

export const billingGetSummaryFn = onCall(
  { region: REGION, cors: true },
  getBillingSummary
);

export const billingGetJurisdictionFn = onCall(
  { region: REGION, cors: true },
  getBillingJurisdiction
);

export const billingGetAgedReceivablesFn = onCall(
  { region: REGION, cors: true },
  getAgedReceivables
);

// Stripe webhook (HTTP function, not callable)
// Note: Stripe webhooks require raw body for signature verification
// May need to configure body parsing in Firebase Functions settings
export const billingStripeWebhookFn = onRequest(
  { 
    region: REGION, 
    cors: true,
    // Raw body needed for Stripe signature verification
    // Note: May need to configure in Firebase Console or use express middleware
  },
  async (req, res) => {
    await handleStripeWebhook(req, res);
  }
);

// Intake
export const submitIntakeSessionFn = onCall(
  { region: REGION, cors: true },
  submitIntakeSession
);
export {
  createGeneralQuestionnaireLinkFn,
  createQuestionnaireLaunchLinkFn,
  resolveIntakeLinkTokenFn,
  listQuestionnaireTemplatesFn,
  updateQuestionnaireTemplateFn,
};

// Audit
export const exportClosureOverrideAuditReportFn = onCall(
  { region: REGION, cors: true },
  exportClosureOverrideAuditReport
);

// ─────────────────────────────
// Triggers / background
// ─────────────────────────────
export { onBookingRequestCreateV2 } from "./clinic/booking/onBookingRequestCreate";
export { onPractitionerWritten } from "./public/mirrorPublicBooking";
export { onPublicBookingConfigMirror } from "./public/onPublicBookingConfigMirror";
export {
  onPublicBookingSettingsWriteProjection,
  onLocationWritePublicBookingConfigProjection,
  projectionsRebuildPublicBookingConfig,
} from "./clinic/projections/publicBookingProjection";
export { onAppointmentWrite_toBusyBlock } from "./availability/onAppointmentWrite_toBusyBlock";
export { mirrorPractitionerToPublic } from "./projections/practitionerPublicMirror";
export { onClinicalNoteWrite } from "./clinic/notes/onClinicalNoteWrite";
export { onSoapNoteWrite } from "./clinic/notes/onSoapNoteWrite";

// ─────────────────────────────
// Public booking (NO AUTH)
// ─────────────────────────────
export {
  listPublicSlotsFn,
  getPublicMonthAvailabilityFn,
  getPublicBookingPractitionersFn,
  getPublicBookingLocationsFn,
  getPublicBookingAppointmentTypesFn,
  getPublicBookingDiagnosticsFn,
};
export const getManageContextFn = getManageContext;
export const cancelBookingWithTokenFn = cancelBookingWithToken;
export const rescheduleBookingWithTokenFn = rescheduleBookingWithToken;

export { testCallable } from "./testCallable";
export { onClinicCreatedProvisionDefaults } from "./clinic/settings/provisionClinicDefaults";
export { backfillNotificationsSettings } from "./clinic/settings/backfillNotifications";
export { backfillRoles } from "./clinic/settings/backfillRoles";
export { backfillMemberPermissions } from "./clinic/settings/backfillMemberPermissions";
export { consumeIntakeInviteFn } from "./intake/consumeIntakeInviteFn";

export const bootstrapPublicBookingSettingsFn = onCall(
  { region: REGION, cors: true },
  bootstrapPublicBookingSettings
);
export { createBookingRequestFn } from "./clinic/booking/createBookingRequestFn";
export { intakePdfOnSubmit } from "./preassessment/intakePdfOnSubmit";

export {
  resolveIntakeSessionFromBookingRequestFn,
} from "./preassessment/resolveIntakeSessionFromBookingRequestFn";

export { onClinicCreatedProvisionOwnerMembership } from "./clinic/onClinicCreatedProvisionOwner";
