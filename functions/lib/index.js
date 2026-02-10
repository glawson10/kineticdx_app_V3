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
exports.testCallable = exports.rescheduleBookingWithTokenFn = exports.cancelBookingWithTokenFn = exports.getManageContextFn = exports.listPublicSlotsFn = exports.onClinicalNoteWrite = exports.mirrorPractitionerToPublic = exports.onAppointmentWrite_toBusyBlock = exports.onPublicBookingSettingsWrite = exports.onBookingRequestCreateV2 = exports.exportClosureOverrideAuditReportFn = exports.resolveIntakeLinkTokenFn = exports.createGeneralQuestionnaireLinkFn = exports.submitIntakeSessionFn = exports.generateAssessmentPdfFn = exports.getAssessmentPackFn = exports.submitAssessmentFn = exports.deleteOutcomeMeasureFn = exports.upsertOutcomeMeasureFn = exports.deleteClinicalTestFn = exports.upsertClinicalTestFn = exports.amendClinicalNoteFn = exports.createClinicalNoteFn = exports.closeEpisodeFn = exports.updateEpisodeFn = exports.createEpisodeFn = exports.deletePatientFn = exports.mergePatientsFn = exports.updatePatientFn = exports.createPatientFn = exports.updateAppointmentStatusFn = exports.updateAppointmentFn = exports.deleteAppointmentFn = exports.createAppointmentFn = exports.deleteClosureFn = exports.createClosureFn = exports.setStaffAvailabilityDefaultFn = exports.upsertStaffProfileFn = exports.updateClinicWeeklyHoursFn = exports.syncMyDisplayNameFn = exports.updateMemberFn = exports.setMembershipStatusFn = exports.updateClinicProfileFn = exports.acceptInviteFn = exports.inviteMemberFn = exports.updateMemberProfileFn = exports.clinicCreateFn = exports.getSchemaVersionsFn = exports.computeIntakeSummaryV2 = exports.BREVO_API_KEY = void 0;
exports.onClinicCreatedProvisionOwnerMembership = exports.resolveIntakeSessionFromBookingRequestFn = exports.intakePdfOnSubmit = exports.createBookingRequestFn = exports.bootstrapPublicBookingSettingsFn = exports.consumeIntakeInviteFn = exports.backfillNotificationsSettings = exports.onClinicCreatedProvisionDefaults = void 0;
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
const setMembershipStatus_1 = require("./clinic/setMembershipStatus");
const updateMember_1 = require("./clinic/updateMember");
const syncMyDisplayName_1 = require("./clinic/syncMyDisplayName");
const updateMemberProfile_1 = require("./clinic/updateMemberProfile");
const upsertStaffProfile_1 = require("./clinic/staff/upsertStaffProfile");
const setStaffAvailabilityDefault_1 = require("./clinic/staff/setStaffAvailabilityDefault");
// ─────────────────────────────
// Closures
// ─────────────────────────────
const createClosure_1 = require("./clinic/closures/createClosure");
const deleteClosure_1 = require("./clinic/closures/deleteClosure");
// ─────────────────────────────
// Booking / patients / episodes
// ─────────────────────────────
const createAppointment_1 = require("./clinic/createAppointment");
const deleteAppointment_1 = require("./clinic/deleteAppointment");
const updateAppointment_1 = require("./clinic/updateAppointment");
const updateAppointmentStatus_1 = require("./clinic/updateAppointmentStatus");
const createPatient_1 = require("./clinic/patients/createPatient");
const updatePatient_1 = require("./clinic/patients/updatePatient");
const mergePatients_1 = require("./clinic/patients/mergePatients");
const deletePatient_1 = require("./clinic/patients/deletePatient");
const createEpisode_1 = require("./clinic/episode/createEpisode");
const updateEpisode_1 = require("./clinic/episode/updateEpisode");
const closeEpisode_1 = require("./clinic/episode/closeEpisode");
// ─────────────────────────────
// Clinical notes
// ─────────────────────────────
const createClinicalNote_1 = require("./clinic/notes/createClinicalNote");
const amendClinicalNote_1 = require("./clinic/notes/amendClinicalNote");
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
// Intake / decision support
// ─────────────────────────────
const submitIntakeSession_1 = require("./clinic/intake/submitIntakeSession");
var computeIntakeSummary_1 = require("./clinic/intake/computeIntakeSummary");
Object.defineProperty(exports, "computeIntakeSummaryV2", { enumerable: true, get: function () { return computeIntakeSummary_1.computeIntakeSummaryV2; } });
__exportStar(require("./clinic/intake/computeDecisionSupport"), exports);
const createGeneralQuestionnaireLinkFn_1 = require("./intake/createGeneralQuestionnaireLinkFn");
Object.defineProperty(exports, "createGeneralQuestionnaireLinkFn", { enumerable: true, get: function () { return createGeneralQuestionnaireLinkFn_1.createGeneralQuestionnaireLinkFn; } });
const resolveIntakeLinkTokenFn_1 = require("./intake/resolveIntakeLinkTokenFn");
Object.defineProperty(exports, "resolveIntakeLinkTokenFn", { enumerable: true, get: function () { return resolveIntakeLinkTokenFn_1.resolveIntakeLinkTokenFn; } });
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
const bookingActions_1 = require("./public/bookingActions");
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
exports.updateClinicProfileFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateClinicProfile_1.updateClinicProfile);
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
exports.deleteAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteAppointment_1.deleteAppointment);
exports.updateAppointmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointment_1.updateAppointment);
exports.updateAppointmentStatusFn = (0, https_1.onCall)({ region: REGION, cors: true }, updateAppointmentStatus_1.updateAppointmentStatus);
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
// Registries
exports.upsertClinicalTestFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertClinicalTest_1.upsertClinicalTest);
exports.deleteClinicalTestFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteClinicalTest_1.deleteClinicalTest);
exports.upsertOutcomeMeasureFn = (0, https_1.onCall)({ region: REGION, cors: true }, upsertOutcomeMeasure_1.upsertOutcomeMeasure);
exports.deleteOutcomeMeasureFn = (0, https_1.onCall)({ region: REGION, cors: true }, deleteOutcomeMeasure_1.deleteOutcomeMeasure);
// Assessments
exports.submitAssessmentFn = (0, https_1.onCall)({ region: REGION, cors: true }, submitAssessment_1.submitAssessment);
exports.getAssessmentPackFn = (0, https_1.onCall)({ region: REGION, cors: true }, getAssessmentPack_1.getAssessmentPack);
exports.generateAssessmentPdfFn = (0, https_1.onCall)({ region: REGION, cors: true }, generateAssessmentPdf_1.generateAssessmentPdf);
// Intake
exports.submitIntakeSessionFn = (0, https_1.onCall)({ region: REGION, cors: true }, submitIntakeSession_1.submitIntakeSession);
// Audit
exports.exportClosureOverrideAuditReportFn = (0, https_1.onCall)({ region: REGION, cors: true }, exportClosureOverrideAuditReport_1.exportClosureOverrideAuditReport);
// ─────────────────────────────
// Triggers / background
// ─────────────────────────────
var onBookingRequestCreate_1 = require("./clinic/booking/onBookingRequestCreate");
Object.defineProperty(exports, "onBookingRequestCreateV2", { enumerable: true, get: function () { return onBookingRequestCreate_1.onBookingRequestCreateV2; } });
var onPublicBookingSettingsWrite_1 = require("./public/onPublicBookingSettingsWrite");
Object.defineProperty(exports, "onPublicBookingSettingsWrite", { enumerable: true, get: function () { return onPublicBookingSettingsWrite_1.onPublicBookingSettingsWrite; } });
var onAppointmentWrite_toBusyBlock_1 = require("./availability/onAppointmentWrite_toBusyBlock");
Object.defineProperty(exports, "onAppointmentWrite_toBusyBlock", { enumerable: true, get: function () { return onAppointmentWrite_toBusyBlock_1.onAppointmentWrite_toBusyBlock; } });
var practitionerPublicMirror_1 = require("./projections/practitionerPublicMirror");
Object.defineProperty(exports, "mirrorPractitionerToPublic", { enumerable: true, get: function () { return practitionerPublicMirror_1.mirrorPractitionerToPublic; } });
var onClinicalNoteWrite_1 = require("./clinic/notes/onClinicalNoteWrite");
Object.defineProperty(exports, "onClinicalNoteWrite", { enumerable: true, get: function () { return onClinicalNoteWrite_1.onClinicalNoteWrite; } });
exports.getManageContextFn = bookingActions_1.getManageContext;
exports.cancelBookingWithTokenFn = bookingActions_1.cancelBookingWithToken;
exports.rescheduleBookingWithTokenFn = bookingActions_1.rescheduleBookingWithToken;
var testCallable_1 = require("./testCallable");
Object.defineProperty(exports, "testCallable", { enumerable: true, get: function () { return testCallable_1.testCallable; } });
var provisionClinicDefaults_1 = require("./clinic/settings/provisionClinicDefaults");
Object.defineProperty(exports, "onClinicCreatedProvisionDefaults", { enumerable: true, get: function () { return provisionClinicDefaults_1.onClinicCreatedProvisionDefaults; } });
var backfillNotifications_1 = require("./clinic/settings/backfillNotifications");
Object.defineProperty(exports, "backfillNotificationsSettings", { enumerable: true, get: function () { return backfillNotifications_1.backfillNotificationsSettings; } });
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