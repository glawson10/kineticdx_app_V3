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
exports.generateAssessmentPdf = generateAssessmentPdf;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const audit_1 = require("../audit/audit");
async function generateAssessmentPdf(req) {
    var _a, _b, _c, _d, _e, _f;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const assessmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.assessmentId) !== null && _d !== void 0 ? _d : "").trim();
    if (!clinicId || !assessmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId and assessmentId are required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "clinical.read");
    const ref = db.collection("clinics").doc(clinicId).collection("assessments").doc(assessmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Assessment not found.");
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "assessment.pdf.requested",
        actorUid: uid,
        metadata: { assessmentId, format: (_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.format) !== null && _f !== void 0 ? _f : "pdf" },
    });
    return {
        success: false,
        status: "not_implemented",
        message: "PDF generation pipeline not implemented yet. Contract is in place; implement later via Storage + renderer.",
    };
}
//# sourceMappingURL=generateAssessmentPdf.js.map