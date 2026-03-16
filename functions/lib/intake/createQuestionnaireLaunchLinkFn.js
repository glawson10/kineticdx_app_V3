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
Object.defineProperty(exports, "__esModule", { value: true });
exports.createQuestionnaireLaunchLinkFn = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const crypto = __importStar(require("crypto"));
const questionnaireTemplates_1 = require("../clinic/questionnaires/questionnaireTemplates");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const DEFAULT_PUBLIC_APP_BASE_URL = "https://kineticdx-app-v3.web.app";
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function sha256Base64Url(s) {
    return crypto.createHash("sha256").update(s).digest("base64url");
}
function randomToken(bytes = 32) {
    return crypto.randomBytes(bytes).toString("base64url");
}
function normalizeBaseUrl(url) {
    let u = safeStr(url);
    if (!u)
        return DEFAULT_PUBLIC_APP_BASE_URL;
    if (u.endsWith("/"))
        u = u.slice(0, -1);
    return u;
}
async function readPublicBaseUrl(clinicId) {
    const snap = await db.doc(`clinics/${clinicId}/settings/publicBooking`).get();
    const d = snap.exists ? snap.data() : {};
    const url = safeStr(d === null || d === void 0 ? void 0 : d.publicBaseUrl);
    return url || DEFAULT_PUBLIC_APP_BASE_URL;
}
function buildQuestionnaireLaunchUrl(params) {
    const base = normalizeBaseUrl(params.baseUrl);
    const t = encodeURIComponent(params.token);
    const useHash = params.useHashRouting !== false;
    return useHash ? `${base}/#/q/launch/${t}` : `${base}/q/launch/${t}`;
}
exports.createQuestionnaireLaunchLinkFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const templateId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.templateId);
    const bookingRequestId = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.bookingRequestId);
    const patientId = safeStr((_d = req.data) === null || _d === void 0 ? void 0 : _d.patientId);
    const emailRaw = safeStr((_e = req.data) === null || _e === void 0 ? void 0 : _e.email).toLowerCase();
    const expiresInDaysRaw = (_f = req.data) === null || _f === void 0 ? void 0 : _f.expiresInDays;
    const prefillRaw = ((_g = req.data) === null || _g === void 0 ? void 0 : _g.prefillPatient) && typeof req.data.prefillPatient === "object"
        ? req.data.prefillPatient
        : {};
    const prefillPatient = {
        firstName: safeStr(prefillRaw.firstName),
        lastName: safeStr(prefillRaw.lastName),
        dobIso: safeStr(prefillRaw.dobIso),
        phone: safeStr(prefillRaw.phone),
        email: safeStr(prefillRaw.email),
        address: safeStr(prefillRaw.address),
    };
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId.");
    }
    if (!templateId) {
        throw new https_1.HttpsError("invalid-argument", "Missing templateId.");
    }
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
        throw new https_1.HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }
    const template = await (0, questionnaireTemplates_1.loadQuestionnaireTemplateById)(db, clinicId, templateId);
    if (!template || !template.active || !template.patientFacing) {
        throw new https_1.HttpsError("not-found", "Questionnaire template not found.", {
            clinicId,
            templateId,
        });
    }
    if (template.launchKind !== questionnaireTemplates_1.QUESTIONNAIRE_LAUNCH_KIND_INTAKE_LINK) {
        throw new https_1.HttpsError("failed-precondition", "This questionnaire template cannot be launched with an intake link.");
    }
    const ttlDays = typeof expiresInDaysRaw === "number" && expiresInDaysRaw > 0
        ? Math.ceil(expiresInDaysRaw)
        : 7;
    const token = randomToken(32);
    const tokenHash = sha256Base64Url(token);
    const linkRef = db.collection(`clinics/${clinicId}/intakeLinks`).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    await linkRef.set({
        schemaVersion: 2,
        clinicId,
        kind: "questionnaire",
        templateId: template.templateId,
        flowId: (_h = template.flowId) !== null && _h !== void 0 ? _h : null,
        flowVersion: (_j = template.flowVersion) !== null && _j !== void 0 ? _j : 1,
        flowCategory: (_k = template.flowCategory) !== null && _k !== void 0 ? _k : "general",
        flowDefinitionId: (_l = template.flowDefinitionId) !== null && _l !== void 0 ? _l : null,
        clinicalProfileId: (_m = template.clinicalProfileId) !== null && _m !== void 0 ? _m : null,
        tokenHash,
        status: "active",
        expiresAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        usedAt: null,
        intakeSessionId: null,
        patientId: patientId || null,
        patientEmailNorm: emailRaw || null,
        bookingRequestId: bookingRequestId || null,
        prefillPatient,
        createdByUid: (_p = (_o = req.auth) === null || _o === void 0 ? void 0 : _o.uid) !== null && _p !== void 0 ? _p : null,
    });
    const baseUrl = await readPublicBaseUrl(clinicId);
    const url = buildQuestionnaireLaunchUrl({
        baseUrl,
        token,
        useHashRouting: true,
    });
    logger_1.logger.info("createQuestionnaireLaunchLinkFn ok", {
        clinicId,
        templateId,
        linkId: linkRef.id,
        hasPatientId: !!patientId,
        hasEmail: !!emailRaw,
        expiresAtMs: expiresAt.toMillis(),
    });
    return { url, token, expiresAt, templateId };
});
//# sourceMappingURL=createQuestionnaireLaunchLinkFn.js.map