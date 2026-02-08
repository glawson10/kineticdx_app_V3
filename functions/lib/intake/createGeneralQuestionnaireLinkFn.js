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
exports.createGeneralQuestionnaireLinkFn = void 0;
// functions/src/intake/createGeneralQuestionnaireLinkFn.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const logger_1 = require("firebase-functions/logger");
const crypto = __importStar(require("crypto"));
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
function buildGeneralQuestionnaireUrl(params) {
    const base = normalizeBaseUrl(params.baseUrl);
    const t = encodeURIComponent(params.token);
    const useHash = params.useHashRouting !== false;
    return useHash ? `${base}/#/q/general/${t}` : `${base}/q/general/${t}`;
}
/**
 * ✅ Create a tokenized general questionnaire link.
 * Input: { clinicId, patientId?, email?, expiresInDays? }
 * Output: { url, token, expiresAt }
 */
exports.createGeneralQuestionnaireLinkFn = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a, _b, _c, _d, _e, _f;
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const patientId = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.patientId);
    const emailRaw = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.email).toLowerCase();
    const expiresInDaysRaw = (_d = req.data) === null || _d === void 0 ? void 0 : _d.expiresInDays;
    if (!clinicId) {
        throw new https_1.HttpsError("invalid-argument", "Missing clinicId.");
    }
    const clinicSnap = await db.collection("clinics").doc(clinicId).get();
    if (!clinicSnap.exists) {
        throw new https_1.HttpsError("not-found", "Clinic does not exist.", { clinicId });
    }
    const ttlDays = typeof expiresInDaysRaw === "number" && expiresInDaysRaw > 0
        ? Math.ceil(expiresInDaysRaw)
        : 7;
    const token = randomToken(32);
    const tokenHash = sha256Base64Url(token);
    const linkRef = db.collection(`clinics/${clinicId}/intakeLinks`).doc();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    await linkRef.set({
        schemaVersion: 1,
        clinicId,
        kind: "general",
        tokenHash,
        status: "active",
        expiresAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        usedAt: null,
        intakeSessionId: null,
        // Optional linkage
        patientId: patientId || null,
        patientEmailNorm: emailRaw || null,
        createdByUid: (_f = (_e = req.auth) === null || _e === void 0 ? void 0 : _e.uid) !== null && _f !== void 0 ? _f : null,
    });
    const baseUrl = await readPublicBaseUrl(clinicId);
    const url = buildGeneralQuestionnaireUrl({
        baseUrl,
        token,
        useHashRouting: true,
    });
    logger_1.logger.info("createGeneralQuestionnaireLinkFn ok", {
        clinicId,
        linkId: linkRef.id,
        hasPatientId: !!patientId,
        hasEmail: !!emailRaw,
        expiresAtMs: expiresAt.toMillis(),
    });
    return { url, token, expiresAt };
});
//# sourceMappingURL=createGeneralQuestionnaireLinkFn.js.map