"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateAppointmentStatusFn = exports.splitAppointmentSeriesFn = exports.updateAppointmentSeriesFn = exports.updateAppointmentOccurrenceFn = exports.updateAppointmentFn = exports.deleteAppointmentFn = exports.createAppointmentSeriesFn = exports.createAppointmentFn = exports.deleteClosureFn = exports.createClosureFn = exports.setStaffAvailabilityDefaultFn = exports.upsertStaffProfileFn = exports.updateClinicWeeklyHoursFn = exports.syncMyDisplayNameFn = exports.updateMemberFn = exports.setMembershipStatusFn = exports.upsertPractitionerBookingMetaFn = exports.settingsDeletePractitionerOverride = exports.settingsUpsertPractitionerOverride = exports.settingsDeletePractitionerAvailability = exports.settingsUpsertPractitionerAvailability = exports.settingsUpdateCommunicationSettings = exports.rebuildPublicBookingMirrorFn = exports.settingsUpdateLocationDisplayOrder = exports.settingsUpdateOnlineBookingEnablement = exports.settingsUpdatePublicBookingConfig = exports.settingsGetCommunicationSettings = exports.settingsGetPublicBookingConfig = exports.settingsListAppointmentTypes = exports.settingsListLocations = exports.settingsListMembers = exports.settingsGetClosures = exports.settingsGetMembership = exports.settingsGetClinicProfile = exports.settingsGetCalendarDisplayConfig = exports.settingsUpdateCalendarDisplayConfig = exports.settingsSetAppointmentTypeActive = exports.settingsUpsertAppointmentType = exports.settingsUpdateLocationWeeklyHours = exports.settingsSetLocationActive = exports.settingsUpsertLocation = exports.updateClinicProfileFn = exports.settingsUpdateClinicProfile = exports.acceptInviteFn = exports.inviteMemberFn = exports.updateMemberProfileFn = exports.clinicCreateFn = exports.getSchemaVersionsFn = exports.computeIntakeSummaryV2 = exports.BREVO_API_KEY = void 0;
exports.listQuestionnaireTemplatesFn = exports.resolveIntakeLinkTokenFn = exports.createQuestionnaireLaunchLinkFn = exports.createGeneralQuestionnaireLinkFn = exports.submitIntakeSessionFn = exports.billingStripeWebhookFn = exports.billingGetAgedReceivablesFn = exports.billingGetJurisdictionFn = exports.billingGetSummaryFn = exports.billingGetInvoicePdfDownloadUrlFn = exports.billingGenerateInvoicePdfFn = exports.billingCreateInvoicePaymentLinkFn = exports.billingCreateStripePaymentIntentFn = exports.settingsUpsertProduct = exports.settingsUpsertBillableItem = exports.settingsUpsertPaymentType = exports.settingsUpsertTax = exports.billingResolvePricingForAppointmentFn = exports.billingUpdatePricingSettingsFn = exports.billingUpdateSettingsFn = exports.billingRefundPaymentFn = exports.billingIssueCreditNoteFn = exports.billingRecordPaymentFn = exports.billingRecordManualPaymentFn = exports.billingIssueInvoiceFn = exports.billingCreateInvoiceFromAppointmentFn = exports.billingUpdateInvoiceFn = exports.billingCreateInvoiceFn = exports.billingCreateInvoiceDraftFn = exports.billingCreateChargeFn = exports.generateAssessmentPdfFn = exports.getAssessmentPackFn = exports.submitAssessmentFn = exports.deleteOutcomeMeasureFn = exports.upsertOutcomeMeasureFn = exports.deleteClinicalTestFn = exports.upsertClinicalTestFn = exports.unfinalizeSoapNoteFn = exports.finalizeSoapNoteFn = exports.amendClinicalNoteFn = exports.createClinicalNoteFn = exports.closeEpisodeFn = exports.updateEpisodeFn = exports.createEpisodeFn = exports.listPatientsForBookingFn = exports.deletePatientFn = exports.mergePatientsFn = exports.updatePatientFn = exports.createPatientFn = exports.cancelAppointmentFn = void 0;
exports.onClinicCreatedProvisionOwnerMembership = exports.resolveIntakeSessionFromBookingRequestFn = exports.intakePdfOnSubmit = exports.createBookingRequestFn = exports.bootstrapPublicBookingSettingsFn = exports.consumeIntakeInviteFn = exports.backfillMemberPermissions = exports.backfillRoles = exports.backfillNotificationsSettings = exports.onClinicCreatedProvisionDefaults = exports.testCallable = exports.rescheduleBookingWithTokenFn = exports.cancelBookingWithTokenFn = exports.getManageContextFn = exports.getPublicBookingDiagnosticsFn = exports.getPublicBookingAppointmentTypesFn = exports.getPublicBookingLocationsFn = exports.getPublicBookingPractitionersFn = exports.getPublicMonthAvailabilityFn = exports.listPublicSlotsFn = exports.onSoapNoteWrite = exports.onClinicalNoteWrite = exports.mirrorPractitionerToPublic = exports.onAppointmentWrite_toBusyBlock = exports.projectionsRebuildPublicBookingConfig = exports.onLocationWritePublicBookingConfigProjection = exports.onPublicBookingSettingsWriteProjection = exports.onPublicBookingConfigMirror = exports.onPractitionerWritten = exports.onBookingRequestCreateV2 = exports.exportClosureOverrideAuditReportFn = exports.updateQuestionnaireTemplateFn = void 0;
// functions/src/index.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
// ─────────────────────────────
// Firebase init (ONLY ONCE)
// ─────────────────────────────
if (!admin.apps.length)
    admin.initializeApp();
// ─────────────────────────────
// Region (single source of truth)
// ─────────────────────────────
const REGION = "europe-west3";
// ─────────────────────────────
// Secrets (MUST be declared in index for v2 analysis)
// ─────────────────────────────
exports.BREVO_API_KEY = (0, params_1.defineSecret)("BREVO_API_KEY");
// ─────────────────────────────
// Schema versions
// ─────────────────────────────
const schemaVersions_1 = require("./schema/schemaVersions");
// ─────────────────────────────
// Clinic / membership
// ─────────────────────────────
const createClinic_1 = require("./clinic/createClinic");
const inviteMember_1 = require("./clinic/inviteMember");
const acceptInvite_1 = require("./clinic/acceptInvite");
const updateClinicProfile_1 = require("./clinic/updateClinicProfile");
const upsertLocation_1 = require("./clinic/settings/upsertLocation");
const setLocationActive_1 = require("./clinic/settings/setLocationActive");
const updateLocationWeeklyHours_1 = require("./clinic/settings/updateLocationWeeklyHours");
const upsertAppointmentType_1 = require("./clinic/settings/upsertAppointmentType");
const setAppointmentTypeActive_1 = require("./clinic/settings/setAppointmentTypeActive");
const updateCalendarDisplayConfig_1 = require("./clinic/settings/updateCalendarDisplayConfig");
const getCalendarDisplayConfig_1 = require("./clinic/settings/getCalendarDisplayConfig");
const getClinicProfile_1 = require("./clinic/settings/getClinicProfile");
const getClosures_1 = require("./clinic/settings/getClosures");
const getMembership_1 = require("./clinic/settings/getMembership");
const listMembers_1 = require("./clinic/settings/listMembers");
const listLocations_1 = require("./clinic/settings/listLocations");
const listAppointmentTypes_1 = require("./clinic/settings/listAppointmentTypes");
const getPublicBookingConfig_1 = require("./clinic/settings/getPublicBookingConfig");
const getCommunicationSettings_1 = require("./clinic/settings/getCommunicationSettings");
const updatePublicBookingConfig_1 = require("./clinic/settings/updatePublicBookingConfig");
const updateOnlineBookingEnablement_1 = require("./clinic/settings/updateOnlineBookingEnablement");
const updateLocationDisplayOrder_1 = require("./clinic/settings/updateLocationDisplayOrder");
const updateCommunicationSettings_1 = require("./clinic/settings/updateCommunicationSettings");
const upsertPractitionerAvailability_1 = require("./clinic/settings/upsertPractitionerAvailability");
const deletePractitionerAvailability_1 = require("./clinic/settings/deletePractitionerAvailability");
const upsertPractitionerOverride_1 = require("./clinic/settings/upsertPractitionerOverride");
const deletePractitionerOverride_1 = require("./clinic/settings/deletePractitionerOverride");
const setMembershipStatus_1 = require("./clinic/setMembershipStatus");
const updateMember_1 = require("./clinic/updateMember");
const syncMyDisplayName_1 = require("./clinic/syncMyDisplayName");
const updateMemberProfile_1 = require("./clinic/updateMemberProfile");
const upsertStaffProfile_1 = require("./clinic/staff/upsertStaffProfile");
const setStaffAvailabilityDefault_1 = require("./clinic/staff/setStaffAvailabilityDefault");
const upsertPractitionerBookingMeta_1 = require("./clinic/staff/upsertPractitionerBookingMeta");
// ─────────────────────────────
// Closures
// ─────────────────────────────
const createClosure_1 = require("./clinic/closures/createClosure");
const deleteClosure_1 = require("./clinic/closures/deleteClosure");
// ─────────────────────────────
// Booking / patients / episodes
// ─────────────────────────────
const createAppointment_1 = require("./clinic/createAppointment");
const createAppointmentSeries_1 = require("./clinic/appointments/createAppointmentSeries");
const cancelAppointment_1 = require("./clinic/cancelAppointment");
const deleteAppointment_1 = require("./clinic/deleteAppointment");
const updateAppointment_1 = require("./clinic/updateAppointment");
const updateAppointmentOccurrence_1 = require("./clinic/appointments/updateAppointmentOccurrence");
const updateAppointmentSeries_1 = require("./clinic/appointments/updateAppointmentSeries");
const splitAppointmentSeries_1 = require("./clinic/appointments/splitAppointmentSeries");
const updateAppointmentStatus_1 = require("./clinic/updateAppointmentStatus");
const createPatient_1 = require("./clinic/patients/createPatient");
const updatePatient_1 = require("./clinic/patients/updatePatient");
const mergePatients_1 = require("./clinic/patients/mergePatients");
const deletePatient_1 = require("./clinic/patients/deletePatient");
const listPatientsForBooking_1 = require("./clinic/patients/listPatientsForBooking");
Object.defineProperty(exports, "listPatientsForBookingFn", { enumerable: true, get: function () { return listPatientsForBooking_1.listPatientsForBookingFn; } });
const createEpisode_1 = require("./clinic/episode/createEpisode");
const updateEpisode_1 = require("./clinic/episode/updateEpisode");
const closeEpisode_1 = require("./clinic/episode/closeEpisode");
// ─────────────────────────────
// Clinical notes
// ─────────────────────────────
const createClinicalNote_1 = require("./clinic/notes/createClinicalNote");
const amendClinicalNote_1 = require("./clinic/notes/amendClinicalNote");
const finalizeSoapNote_1 = require("./clinic/notes/finalizeSoapNote");
// ─────────────────────────────
// Registries
// ─────────────────────────────
const upsertClinicalTest_1 = require("./clinic/registries/upsertClinicalTest");
const deleteClinicalTest_1 = require("./clinic/registries/deleteClinicalTest");
const upsertOutcomeMeasure_1 = require("./clinic/registries/upsertOutcomeMeasure");
const deleteOutcomeMeasure_1 = require("./clinic/registries/deleteOutcomeMeasure");
// ─────────────────────────────
// Assessments
// ─────────────────────────────
const submitAssessment_1 = require("./clinic/assessments/submitAssessment");
const generateAssessmentPdf_1 = require("./clinic/assessments/generateAssessmentPdf");
const getAssessmentPack_1 = require("./clinic/assessments/getAssessmentPack");
// ─────────────────────────────
// Billing
// ─────────────────────────────
const createCharge_1 = require("./clinic/billing/createCharge");
const createInvoiceDraft_1 = require("./clinic/billing/createInvoiceDraft");
const createInvoice_1 = require("./clinic/billing/createInvoice");
const updateInvoice_1 = require("./clinic/billing/updateInvoice");
const createInvoiceFromAppointment_1 = require("./clinic/billing/createInvoiceFromAppointment");
const issueInvoice_1 = require("./clinic/billing/issueInvoice");
const recordManualPayment_1 = require("./clinic/billing/recordManualPayment");
const recordPayment_1 = require("./clinic/billing/recordPayment");
const issueCreditNote_1 = require("./clinic/billing/issueCreditNote");
const refundPayment_1 = require("./clinic/billing/refundPayment");
const updateBillingSettings_1 = require("./clinic/billing/updateBillingSettings");
const createStripePaymentIntent_1 = require("./clinic/billing/createStripePaymentIntent");
const stripeWebhook_1 = require("./clinic/billing/stripeWebhook");
const generateInvoicePdf_1 = require("./clinic/billing/generateInvoicePdf");
const upsertTax_1 = require("./clinic/billing/upsertTax");
const upsertPaymentType_1 = require("./clinic/billing/upsertPaymentType");
const upsertBillableItem_1 = require("./clinic/billing/upsertBillableItem");
const upsertProduct_1 = require("./clinic/billing/upsertProduct");
const createInvoicePaymentLink_1 = require("./clinic/billing/createInvoicePaymentLink");
const getBillingSummary_1 = require("./clinic/billing/getBillingSummary");
const getBillingJurisdiction_1 = require("./clinic/billing/getBillingJurisdiction");
const getAgedReceivables_1 = require("./clinic/billing/getAgedReceivables");
const updatePricingSettings_1 = require("./clinic/billing/updatePricingSettings");
const resolvePricingForAppointment_1 = require("./clinic/billing/resolvePricingForAppointment");
// ─────────────────────────────
// Intake / decision support
// ─────────────────────────────
const submitIntakeSession_1 = require("./clinic/intake/submitIntakeSession");
var computeIntakeSummary_1 = require("./clinic/intake/computeIntakeSummary");
Object.defineProperty(exports, "computeIntakeSummaryV2", { enumerable: true, get: function () { return computeIntakeSummary_1.computeIntakeSummaryV2; } });
__exportStar(require("./clinic/intake/computeDecisionSupport"), exports);
const createGeneralQuestionnaireLinkFn_1 = require("./intake/createGeneralQuestionnaireLinkFn");
Object.defineProperty(exports, "createGeneralQuestionnaireLinkFn", { enumerable: true, get: function () { return createGeneralQuestionnaireLinkFn_1.createGeneralQuestionnaireLinkFn; } });
const createQuestionnaireLaunchLinkFn_1 = require("./intake/createQuestionnaireLaunchLinkFn");
Object.defineProperty(exports, "createQuestionnaireLaunchLinkFn", { enumerable: true, get: function () { return createQuestionnaireLaunchLinkFn_1.createQuestionnaireLaunchLinkFn; } });
const resolveIntakeLinkTokenFn_1 = require("./intake/resolveIntakeLinkTokenFn");
Object.defineProperty(exports, "resolveIntakeLinkTokenFn", { enumerable: true, get: function () { return resolveIntakeLinkTokenFn_1.resolveIntakeLinkTokenFn; } });
const listQuestionnaireTemplatesFn_1 = require("./clinic/questionnaires/listQuestionnaireTemplatesFn");
Object.defineProperty(exports, "listQuestionnaireTemplatesFn", { enumerable: true, get: function () { return listQuestionnaireTemplatesFn_1.listQuestionnaireTemplatesFn; } });
Object.defineProperty(exports, "updateQuestionnaireTemplateFn", { enumerable: true, get: function () { return listQuestionnaireTemplatesFn_1.updateQuestionnaireTemplateFn; } });
// ─────────────────────────────
// Audit exports
// ─────────────────────────────
const exportClosureOverrideAuditReport_1 = require("./clinic/audit/exportClosureOverrideAuditReport");
// ─────────────────────────────
// Public booking
// ─────────────────────────────
const bootstrapPublicBookingSettings_1 = require("./clinic/bootstrapPublicBookingSettings");
const listPublicSlots_1 = require("./public/listPublicSlots");
Object.defineProperty(exports, "listPublicSlotsFn", { enumerable: true, get: function () { return listPublicSlots_1.listPublicSlotsFn; } });
Object.defineProperty(exports, "getPublicMonthAvailabilityFn", { enumerable: true, get: function () { return listPublicSlots_1.getPublicMonthAvailabilityFn; } });
Object.defineProperty(exports, "getPublicBookingPractitionersFn", { enumerable: true, get: function () { return listPublicSlots_1.getPublicBookingPractitionersFn; } });
Object.defineProperty(exports, "getPublicBookingLocationsFn", { enumerable: true, get: function () { return listPublicSlots_1.getPublicBookingLocationsFn; } });
Object.defineProperty(exports, "getPublicBookingAppointmentTypesFn", { enumerable: true, get: function () { return listPublicSlots_1.getPublicBookingAppointmentTypesFn; } });
Object.defineProperty(exports, "getPublicBookingDiagnosticsFn", { enumerable: true, get: function () { return listPublicSlots_1.getPublicBookingDiagnosticsFn; } });
const bookingActions_1 = require("./public/bookingActions");
const mirrorPublicBooking_1 = require("./public/mirrorPublicBooking");
// ─────────────────────────────
// Callable exports
// ─────────────────────────────
// Debug / platform
exports.getSchemaVersionsFn = (0, https_1.onCall)({ region: REGION, cors: true }, async () => ({ ok: true, versions: schemaVersions_1.SCHEMA_VERSIONS }));
// Clinic
exports.clinicCreateFn = (0, https_1.onCall)({ region: REGION, cors: true }, createClinic_1.createClinic);
exports.updateMemberProfileFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateMemberProfile_1.updateMemberProfile);
exports.inviteMemberFn = (0, https_1.onCall)({ region: REGION, cors: true, secrets: [exports.BREVO_API_KEY] }, inviteMember_1.inviteMember);
exports.acceptInviteFn = (0, https_1.onCall)({ region: REGION, cors: true }, acceptInvite_1.acceptInvite);
// Commit 04: settings.* callable naming (filterable in logs)
exports.settingsUpdateClinicProfile = (0, https_1.onCall)({ region: REGION, cors: true }, updateClinicProfile_1.updateClinicProfile);
// Legacy alias for backward compatibility
exports.updateClinicProfileFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateClinicProfile_1.updateClinicProfile);
exports.settingsUpsertLocation = (0, https_1.onCall)({ region: REGION, cors: true }, upsertLocation_1.upsertLocation);
exports.settingsSetLocationActive = (0, https_1.onCall)({ region: REGION, cors: true }, setLocationActive_1.setLocationActive);
exports.settingsUpdateLocationWeeklyHours = (0, https_1.onCall)({ region: REGION, cors: true }, updateLocationWeeklyHours_1.updateLocationWeeklyHours);
exports.settingsUpsertAppointmentType = (0, https_1.onCall)({ region: REGION, cors: true }, upsertAppointmentType_1.upsertAppointmentType);
exports.settingsSetAppointmentTypeActive = (0, https_1.onCall)({ region: REGION, cors: true }, setAppointmentTypeActive_1.setAppointmentTypeActive);
exports.settingsUpdateCalendarDisplayConfig = (0, https_1.onCall)({ region: REGION, cors: true }, updateCalendarDisplayConfig_1.updateCalendarDisplayConfig);
exports.settingsGetCalendarDisplayConfig = (0, https_1.onCall)({ region: REGION, cors: true }, getCalendarDisplayConfig_1.getCalendarDisplayConfig);
exports.settingsGetClinicProfile = (0, https_1.onCall)({ region: REGION, cors: true }, getClinicProfile_1.getClinicProfile);
exports.settingsGetMembership = (0, https_1.onCall)({ region: REGION, cors: true }, getMembership_1.getMembership);
exports.settingsGetClosures = (0, https_1.onCall)({ region: REGION, cors: true }, getClosures_1.getClosures);
exports.settingsListMembers = (0, https_1.onCall)({ region: REGION, cors: true }, listMembers_1.listMembers);
exports.settingsListLocations = (0, https_1.onCall)({ region: REGION, cors: true }, listLocations_1.listLocations);
exports.settingsListAppointmentTypes = (0, https_1.onCall)({ region: REGION, cors: true }, listAppointmentTypes_1.listAppointmentTypes);
exports.settingsGetPublicBookingConfig = (0, https_1.onCall)({ region: REGION, cors: true }, getPublicBookingConfig_1.getPublicBookingConfig);
exports.settingsGetCommunicationSettings = (0, https_1.onCall)({ region: REGION, cors: true }, getCommunicationSettings_1.getCommunicationSettings);
exports.settingsUpdatePublicBookingConfig = (0, https_1.onCall)({ region: REGION, cors: true }, updatePublicBookingConfig_1.updatePublicBookingConfig);
exports.settingsUpdateOnlineBookingEnablement = (0, https_1.onCall)({ region: REGION, cors: true }, updateOnlineBookingEnablement_1.updateOnlineBookingEnablement);
exports.settingsUpdateLocationDisplayOrder = (0, https_1.onCall)({ region: REGION, cors: true }, updateLocationDisplayOrder_1.updateLocationDisplayOrder);
/** Rebuild public booking mirror (practitioners, locations, appointment types). Requires settings.write. */
exports.rebuildPublicBookingMirrorFn = (0, https_1.onCall)({ region: REGION, cors: true }, async (request) => {
    var _a, _b, _c;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid)) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const clinicId = String((_c = (_b = request.data) === null || _b === void 0 ? void 0 : _b.clinicId) !== null && _c !== void 0 ? _c : "").trim();
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    }
    const { requireClinicPermission } = await Promise.resolve().then(() => __importStar(require("./clinic/permissions")));
    await requireClinicPermission(admin.firestore(), clinicId, request.auth.uid, "settings.write");
    await (0, mirrorPublicBooking_1.runPublicBookingMirrorForClinic)(clinicId);
    return { ok: true, clinicId };
});
exports.settingsUpdateCommunicationSettings = (0, https_1.onCall)({ region: REGION, cors: true }, updateCommunicationSettings_1.updateCommunicationSettings);
exports.settingsUpsertPractitionerAvailability = (0, https_1.onCall)({ region: REGION, cors: true }, upsertPractitionerAvailability_1.upsertPractitionerAvailability);
exports.settingsDeletePractitionerAvailability = (0, https_1.onCall)({ region: REGION, cors: true }, deletePractitionerAvailability_1.deletePractitionerAvailability);
exports.settingsUpsertPractitionerOverride = (0, https_1.onCall)({ region: REGION, cors: true }, upsertPractitionerOverride_1.upsertPractitionerOverride);
exports.settingsDeletePractitionerOverride = (0, https_1.onCall)({ region: REGION, cors: true }, deletePractitionerOverride_1.deletePractitionerOverride);
exports.upsertPractitionerBookingMetaFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertPractitionerBookingMeta_1.upsertPractitionerBookingMeta);
exports.setMembershipStatusFn = (0, https_1.onCall)({ region: REGION, cors: true }, setMembershipStatus_1.setMembershipStatus);
exports.updateMemberFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateMember_1.updateMember);
exports.syncMyDisplayNameFn = (0, https_1.onCall)({ region: REGION, cors: true }, (req) => (0, syncMyDisplayName_1.syncMyDisplayName)(req));
var updateClinicWeeklyHours_1 = require("./clinic/settings/updateClinicWeeklyHours");
Object.defineProperty(exports, "updateClinicWeeklyHoursFn", { enumerable: true, get: function () { return updateClinicWeeklyHours_1.updateClinicWeeklyHoursFn; } });
// Staff
exports.upsertStaffProfileFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertStaffProfile_1.upsertStaffProfile);
exports.setStaffAvailabilityDefaultFn = (0, https_1.onCall)({ region: REGION, cors: true }, setStaffAvailabilityDefault_1.setStaffAvailabilityDefault);
// Closures
exports.createClosureFn = (0, https_1.onCall)({ region: REGION, cors: true }, createClosure_1.createClosure);
exports.deleteClosureFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteClosure_1.deleteClosure);
// Booking
exports.createAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, createAppointment_1.createAppointment);
exports.createAppointmentSeriesFn = (0, https_1.onCall)({ region: REGION, cors: true }, createAppointmentSeries_1.createAppointmentSeries);
exports.deleteAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteAppointment_1.deleteAppointment);
exports.updateAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointment_1.updateAppointment);
exports.updateAppointmentOccurrenceFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointmentOccurrence_1.updateAppointmentOccurrence);
exports.updateAppointmentSeriesFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointmentSeries_1.updateAppointmentSeries);
exports.splitAppointmentSeriesFn = (0, https_1.onCall)({ region: REGION, cors: true }, splitAppointmentSeries_1.splitAppointmentSeries);
exports.updateAppointmentStatusFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointmentStatus_1.updateAppointmentStatus);
exports.cancelAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, cancelAppointment_1.cancelAppointment);
// Patients
exports.createPatientFn = (0, https_1.onCall)({ region: REGION, cors: true }, createPatient_1.createPatient);
exports.updatePatientFn = (0, https_1.onCall)({ region: REGION, cors: true }, updatePatient_1.updatePatient);
exports.mergePatientsFn = (0, https_1.onCall)({ region: REGION, cors: true }, mergePatients_1.mergePatients);
exports.deletePatientFn = (0, https_1.onCall)({ region: REGION, cors: true }, deletePatient_1.deletePatient);
// Episodes
exports.createEpisodeFn = (0, https_1.onCall)({ region: REGION, cors: true }, createEpisode_1.createEpisode);
exports.updateEpisodeFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateEpisode_1.updateEpisode);
exports.closeEpisodeFn = (0, https_1.onCall)({ region: REGION, cors: true }, closeEpisode_1.closeEpisode);
// Clinical notes
exports.createClinicalNoteFn = (0, https_1.onCall)({ region: REGION, cors: true }, createClinicalNote_1.createClinicalNote);
exports.amendClinicalNoteFn = (0, https_1.onCall)({ region: REGION, cors: true }, amendClinicalNote_1.amendClinicalNote);
exports.finalizeSoapNoteFn = (0, https_1.onCall)({ region: REGION, cors: true }, finalizeSoapNote_1.finalizeSoapNote);
exports.unfinalizeSoapNoteFn = (0, https_1.onCall)({ region: REGION, cors: true }, finalizeSoapNote_1.unfinalizeSoapNote);
// Registries
exports.upsertClinicalTestFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertClinicalTest_1.upsertClinicalTest);
exports.deleteClinicalTestFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteClinicalTest_1.deleteClinicalTest);
exports.upsertOutcomeMeasureFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertOutcomeMeasure_1.upsertOutcomeMeasure);
exports.deleteOutcomeMeasureFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteOutcomeMeasure_1.deleteOutcomeMeasure);
// Assessments
exports.submitAssessmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, submitAssessment_1.submitAssessment);
exports.getAssessmentPackFn = (0, https_1.onCall)({ region: REGION, cors: true }, getAssessmentPack_1.getAssessmentPack);
exports.generateAssessmentPdfFn = (0, https_1.onCall)({ region: REGION, cors: true }, generateAssessmentPdf_1.generateAssessmentPdf);
// Billing
exports.billingCreateChargeFn = (0, https_1.onCall)({ region: REGION, cors: true }, createCharge_1.createCharge);
exports.billingCreateInvoiceDraftFn = (0, https_1.onCall)({ region: REGION, cors: true }, createInvoiceDraft_1.createInvoiceDraft);
exports.billingCreateInvoiceFn = (0, https_1.onCall)({ region: REGION, cors: true }, createInvoice_1.createInvoice);
exports.billingUpdateInvoiceFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateInvoice_1.updateInvoice);
exports.billingCreateInvoiceFromAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, createInvoiceFromAppointment_1.createInvoiceFromAppointment);
exports.billingIssueInvoiceFn = (0, https_1.onCall)({ region: REGION, cors: true }, issueInvoice_1.issueInvoice);
exports.billingRecordManualPaymentFn = (0, https_1.onCall)({ region: REGION, cors: true }, recordManualPayment_1.recordManualPayment);
exports.billingRecordPaymentFn = (0, https_1.onCall)({ region: REGION, cors: true }, recordPayment_1.recordPayment);
exports.billingIssueCreditNoteFn = (0, https_1.onCall)({ region: REGION, cors: true }, issueCreditNote_1.issueCreditNote);
exports.billingRefundPaymentFn = (0, https_1.onCall)({ region: REGION, cors: true }, refundPayment_1.refundPayment);
exports.billingUpdateSettingsFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateBillingSettings_1.updateBillingSettings);
exports.billingUpdatePricingSettingsFn = (0, https_1.onCall)({ region: REGION, cors: true }, updatePricingSettings_1.updatePricingSettings);
exports.billingResolvePricingForAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, resolvePricingForAppointment_1.resolvePricingForAppointment);
exports.settingsUpsertTax = (0, https_1.onCall)({ region: REGION, cors: true }, upsertTax_1.upsertTax);
exports.settingsUpsertPaymentType = (0, https_1.onCall)({ region: REGION, cors: true }, upsertPaymentType_1.upsertPaymentType);
exports.settingsUpsertBillableItem = (0, https_1.onCall)({ region: REGION, cors: true }, upsertBillableItem_1.upsertBillableItem);
exports.settingsUpsertProduct = (0, https_1.onCall)({ region: REGION, cors: true }, upsertProduct_1.upsertProduct);
exports.billingCreateStripePaymentIntentFn = (0, https_1.onCall)({ region: REGION, cors: true }, createStripePaymentIntent_1.createStripePaymentIntent);
exports.billingCreateInvoicePaymentLinkFn = (0, https_1.onCall)({ region: REGION, cors: true }, createInvoicePaymentLink_1.createInvoicePaymentLink);
exports.billingGenerateInvoicePdfFn = (0, https_1.onCall)({ region: REGION, cors: true, memory: "2GiB", timeoutSeconds: 120 }, generateInvoicePdf_1.generateInvoicePdf);
exports.billingGetInvoicePdfDownloadUrlFn = (0, https_1.onCall)({ region: REGION, cors: true }, generateInvoicePdf_1.getInvoicePdfDownloadUrl);
exports.billingGetSummaryFn = (0, https_1.onCall)({ region: REGION, cors: true }, getBillingSummary_1.getBillingSummary);
exports.billingGetJurisdictionFn = (0, https_1.onCall)({ region: REGION, cors: true }, getBillingJurisdiction_1.getBillingJurisdiction);
exports.billingGetAgedReceivablesFn = (0, https_1.onCall)({ region: REGION, cors: true }, getAgedReceivables_1.getAgedReceivables);
// Stripe webhook (HTTP function, not callable)
// Note: Stripe webhooks require raw body for signature verification
// May need to configure body parsing in Firebase Functions settings
exports.billingStripeWebhookFn = (0, https_1.onRequest)({
    region: REGION,
    cors: true,
    // Raw body needed for Stripe signature verification
    // Note: May need to configure in Firebase Console or use express middleware
}, async (req, res) => {
    await (0, stripeWebhook_1.handleStripeWebhook)(req, res);
});
// Intake
exports.submitIntakeSessionFn = (0, https_1.onCall)({ region: REGION, cors: true }, submitIntakeSession_1.submitIntakeSession);
// Audit
exports.exportClosureOverrideAuditReportFn = (0, https_1.onCall)({ region: REGION, cors: true }, exportClosureOverrideAuditReport_1.exportClosureOverrideAuditReport);
// ─────────────────────────────
// Triggers / background
// ─────────────────────────────
var onBookingRequestCreate_1 = require("./clinic/booking/onBookingRequestCreate");
Object.defineProperty(exports, "onBookingRequestCreateV2", { enumerable: true, get: function () { return onBookingRequestCreate_1.onBookingRequestCreateV2; } });
var mirrorPublicBooking_2 = require("./public/mirrorPublicBooking");
Object.defineProperty(exports, "onPractitionerWritten", { enumerable: true, get: function () { return mirrorPublicBooking_2.onPractitionerWritten; } });
var onPublicBookingConfigMirror_1 = require("./public/onPublicBookingConfigMirror");
Object.defineProperty(exports, "onPublicBookingConfigMirror", { enumerable: true, get: function () { return onPublicBookingConfigMirror_1.onPublicBookingConfigMirror; } });
var publicBookingProjection_1 = require("./clinic/projections/publicBookingProjection");
Object.defineProperty(exports, "onPublicBookingSettingsWriteProjection", { enumerable: true, get: function () { return publicBookingProjection_1.onPublicBookingSettingsWriteProjection; } });
Object.defineProperty(exports, "onLocationWritePublicBookingConfigProjection", { enumerable: true, get: function () { return publicBookingProjection_1.onLocationWritePublicBookingConfigProjection; } });
Object.defineProperty(exports, "projectionsRebuildPublicBookingConfig", { enumerable: true, get: function () { return publicBookingProjection_1.projectionsRebuildPublicBookingConfig; } });
var onAppointmentWrite_toBusyBlock_1 = require("./availability/onAppointmentWrite_toBusyBlock");
Object.defineProperty(exports, "onAppointmentWrite_toBusyBlock", { enumerable: true, get: function () { return onAppointmentWrite_toBusyBlock_1.onAppointmentWrite_toBusyBlock; } });
var practitionerPublicMirror_1 = require("./projections/practitionerPublicMirror");
Object.defineProperty(exports, "mirrorPractitionerToPublic", { enumerable: true, get: function () { return practitionerPublicMirror_1.mirrorPractitionerToPublic; } });
var onClinicalNoteWrite_1 = require("./clinic/notes/onClinicalNoteWrite");
Object.defineProperty(exports, "onClinicalNoteWrite", { enumerable: true, get: function () { return onClinicalNoteWrite_1.onClinicalNoteWrite; } });
var onSoapNoteWrite_1 = require("./clinic/notes/onSoapNoteWrite");
Object.defineProperty(exports, "onSoapNoteWrite", { enumerable: true, get: function () { return onSoapNoteWrite_1.onSoapNoteWrite; } });
exports.getManageContextFn = bookingActions_1.getManageContext;
exports.cancelBookingWithTokenFn = bookingActions_1.cancelBookingWithToken;
exports.rescheduleBookingWithTokenFn = bookingActions_1.rescheduleBookingWithToken;
var testCallable_1 = require("./testCallable");
Object.defineProperty(exports, "testCallable", { enumerable: true, get: function () { return testCallable_1.testCallable; } });
var provisionClinicDefaults_1 = require("./clinic/settings/provisionClinicDefaults");
Object.defineProperty(exports, "onClinicCreatedProvisionDefaults", { enumerable: true, get: function () { return provisionClinicDefaults_1.onClinicCreatedProvisionDefaults; } });
var backfillNotifications_1 = require("./clinic/settings/backfillNotifications");
Object.defineProperty(exports, "backfillNotificationsSettings", { enumerable: true, get: function () { return backfillNotifications_1.backfillNotificationsSettings; } });
var backfillRoles_1 = require("./clinic/settings/backfillRoles");
Object.defineProperty(exports, "backfillRoles", { enumerable: true, get: function () { return backfillRoles_1.backfillRoles; } });
var backfillMemberPermissions_1 = require("./clinic/settings/backfillMemberPermissions");
Object.defineProperty(exports, "backfillMemberPermissions", { enumerable: true, get: function () { return backfillMemberPermissions_1.backfillMemberPermissions; } });
var consumeIntakeInviteFn_1 = require("./intake/consumeIntakeInviteFn");
Object.defineProperty(exports, "consumeIntakeInviteFn", { enumerable: true, get: function () { return consumeIntakeInviteFn_1.consumeIntakeInviteFn; } });
exports.bootstrapPublicBookingSettingsFn = (0, https_1.onCall)({ region: REGION, cors: true }, bootstrapPublicBookingSettings_1.bootstrapPublicBookingSettings);
var createBookingRequestFn_1 = require("./clinic/booking/createBookingRequestFn");
Object.defineProperty(exports, "createBookingRequestFn", { enumerable: true, get: function () { return createBookingRequestFn_1.createBookingRequestFn; } });
var intakePdfOnSubmit_1 = require("./preassessment/intakePdfOnSubmit");
Object.defineProperty(exports, "intakePdfOnSubmit", { enumerable: true, get: function () { return intakePdfOnSubmit_1.intakePdfOnSubmit; } });
var resolveIntakeSessionFromBookingRequestFn_1 = require("./preassessment/resolveIntakeSessionFromBookingRequestFn");
Object.defineProperty(exports, "resolveIntakeSessionFromBookingRequestFn", { enumerable: true, get: function () { return resolveIntakeSessionFromBookingRequestFn_1.resolveIntakeSessionFromBookingRequestFn; } });
var onClinicCreatedProvisionOwner_1 = require("./clinic/onClinicCreatedProvisionOwner");
Object.defineProperty(exports, "onClinicCreatedProvisionOwnerMembership", { enumerable: true, get: function () { return onClinicCreatedProvisionOwner_1.onClinicCreatedProvisionOwnerMembership; } });
//# sourceMappingURL=index.js.map