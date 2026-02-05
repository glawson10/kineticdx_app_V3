"use strict";
// functions/src/preassessment/intakePdfOnSubmit.ts
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.intakePdfOnSubmit = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const logger_1 = require("firebase-functions/logger");
const generalVisitV1KeyAnswers_1 = require("./keyAnswers/generalVisitV1KeyAnswers");
const generalVisitV1Renderer_1 = require("./../preassessment/renderers/generalVisitV1Renderer");
const htmlToPdfBuffer_1 = require("../preassessment/pdf/htmlToPdfBuffer");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();
/**
 * Trigger: when an intake session transitions to submitted.
 *
 * Contract:
 * - Phase 3 creates immutable patient-reported snapshot PDFs.
 * - Writes are backend-authoritative and clinic-scoped.
 */
exports.intakePdfOnSubmit = (0, firestore_1.onDocumentWritten)({
    document: "clinics/{clinicId}/intakeSessions/{sessionId}",
    region: "europe-west3",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u;
    const clinicId = event.params.clinicId;
    const sessionId = event.params.sessionId;
    const afterSnap = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    if (!(afterSnap === null || afterSnap === void 0 ? void 0 : afterSnap.exists))
        return;
    const after = afterSnap.data();
    // Only on submit/lock
    const status = ((_b = after.status) !== null && _b !== void 0 ? _b : "").toString();
    if (status !== "submitted" && status !== "locked")
        return;
    // Optional: ensure it was a status transition (reduces accidental writes)
    const before = ((_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.before) === null || _d === void 0 ? void 0 : _d.exists) ? event.data.before.data() : null;
    const beforeStatus = ((_e = before === null || before === void 0 ? void 0 : before.status) !== null && _e !== void 0 ? _e : "").toString();
    // If status didn't actually change and we already have outputs, bail.
    if (before && beforeStatus === status) {
        if (after.pdfSnapshotPath)
            return;
        if (after.keyAnswersVersion === "generalVisit.v1" && after.keyAnswers)
            return;
    }
    // Flow identification
    const flowId = ((_f = after.flowId) !== null && _f !== void 0 ? _f : "").toString(); // "generalVisit"
    const flowVersion = Number((_g = after.flowVersion) !== null && _g !== void 0 ? _g : 0); // 1
    if (flowId !== "generalVisit" || flowVersion !== 1) {
        // Not our flow; branch here for other flows later.
        return;
    }
    const answers = ((_h = after.answers) !== null && _h !== void 0 ? _h : {});
    // ─────────────────────────────────────────────
    // 1) keyAnswers extraction (fast clinician lists)
    // ─────────────────────────────────────────────
    if (!(after.keyAnswersVersion === "generalVisit.v1" && after.keyAnswers)) {
        try {
            const extracted = (0, generalVisitV1KeyAnswers_1.extractGeneralVisitV1KeyAnswers)(answers);
            await db.doc(`clinics/${clinicId}/intakeSessions/${sessionId}`).set({
                keyAnswers: extracted.keyAnswers,
                keyAnswersVersion: extracted.keyAnswersVersion, // "generalVisit.v1"
                summaryPreview: extracted.summaryPreview,
                keyAnswersGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            logger_1.logger.info("Extracted keyAnswers", {
                clinicId,
                sessionId,
                keyAnswersVersion: extracted.keyAnswersVersion,
            });
        }
        catch (e) {
            logger_1.logger.error("Failed to extract keyAnswers", { clinicId, sessionId, error: e });
            // Do not throw: we still want PDF generation to proceed if possible.
        }
    }
    else {
        logger_1.logger.info("keyAnswers already exist; skipping", { clinicId, sessionId });
    }
    // ─────────────────────────────────────────────
    // 2) PDF snapshot generation (immutable)
    // ─────────────────────────────────────────────
    // Guard: do not regenerate if already generated (medico-legal stability)
    if (after.pdfSnapshotPath) {
        logger_1.logger.info("PDF already exists; skipping", { clinicId, sessionId });
        return;
    }
    // Pull patient details either from blocks or answers — prefer blocks if you have them.
    const patientDetails = (_j = after.patientDetails) !== null && _j !== void 0 ? _j : {};
    const clinicProfile = await db.doc(`clinics/${clinicId}`).get();
    const clinicName = ((_l = (_k = clinicProfile.data()) === null || _k === void 0 ? void 0 : _k.name) !== null && _l !== void 0 ? _l : "Clinic").toString();
    const submittedAt = (_s = (_p = (_o = (_m = after.submittedAt) === null || _m === void 0 ? void 0 : _m.toDate) === null || _o === void 0 ? void 0 : _o.call(_m)) !== null && _p !== void 0 ? _p : (_r = (_q = after.completedAt) === null || _q === void 0 ? void 0 : _q.toDate) === null || _r === void 0 ? void 0 : _r.call(_q)) !== null && _s !== void 0 ? _s : new Date();
    // Render HTML
    const html = (0, generalVisitV1Renderer_1.renderGeneralVisitV1Html)({
        clinicId,
        clinicName,
        sessionId,
        submittedAt,
        schemaVersion: Number((_t = after.schemaVersion) !== null && _t !== void 0 ? _t : 1),
        clinicLogoUrl: (_u = after.clinicLogoUrl) !== null && _u !== void 0 ? _u : "", // optional convenience field
        patient: {
            fullName: patientFullName(patientDetails, answers),
            email: patientEmail(patientDetails, answers),
            phone: patientPhone(patientDetails, answers),
        },
        answers,
    });
    // Convert HTML -> PDF buffer
    const pdfBuffer = await (0, htmlToPdfBuffer_1.htmlToPdfBuffer)(html);
    // Storage path (clinic-scoped, private)
    const bucket = storage.bucket();
    const pdfPath = `clinics/${clinicId}/private/intakeSnapshots/${sessionId}.pdf`;
    await bucket.file(pdfPath).save(pdfBuffer, {
        contentType: "application/pdf",
        resumable: false,
        metadata: {
            cacheControl: "private, max-age=0, no-store",
        },
    });
    // Writeback to intake session
    await db.doc(`clinics/${clinicId}/intakeSessions/${sessionId}`).set({
        pdfSnapshotPath: pdfPath,
        pdfGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    logger_1.logger.info("Generated intake PDF snapshot", { clinicId, sessionId, pdfPath });
});
// --------------------
// Patient detail fallbacks
// --------------------
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function readTextAnswer(answers, qid) {
    const a = answers[qid];
    if (a && typeof a === "object" && a.t === "text")
        return safeStr(a.v);
    return "";
}
function patientFullName(patientDetails, answers) {
    const fromBlock = safeStr(patientDetails.fullName);
    if (fromBlock)
        return fromBlock;
    const first = readTextAnswer(answers, "patient.firstName");
    const last = readTextAnswer(answers, "patient.lastName");
    const combined = safeStr(`${first} ${last}`);
    return combined || "—";
}
function patientEmail(patientDetails, answers) {
    const fromBlock = safeStr(patientDetails.email);
    if (fromBlock)
        return fromBlock;
    return readTextAnswer(answers, "patient.email") || "—";
}
function patientPhone(patientDetails, answers) {
    const fromBlock = safeStr(patientDetails.phone);
    if (fromBlock)
        return fromBlock;
    return readTextAnswer(answers, "patient.phone") || "—";
}
//# sourceMappingURL=intakePdfOnSubmit.js.map