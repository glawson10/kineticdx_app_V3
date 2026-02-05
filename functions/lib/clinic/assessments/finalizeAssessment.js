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
exports.finalizeAssessment = finalizeAssessment;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const paths_1 = require("../paths");
const audit_1 = require("../audit/audit");
async function finalizeAssessment(req) {
    var _a, _b, _c, _d, _e, _f;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const assessmentId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.assessmentId) !== null && _d !== void 0 ? _d : "").trim();
    const triageStatus = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.triageStatus) !== null && _f !== void 0 ? _f : "").trim();
    if (!clinicId || !assessmentId) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, assessmentId required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "clinical.write");
    const ref = (0, paths_1.assessmentRef)(db, clinicId, assessmentId);
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e;
        const snap = await tx.get(ref);
        if (!snap.exists)
            throw new https_1.HttpsError("not-found", "Assessment not found.");
        const data = snap.data();
        if (((_a = data.status) !== null && _a !== void 0 ? _a : "draft") !== "draft") {
            throw new https_1.HttpsError("failed-precondition", "Assessment is not a draft.");
        }
        if (data.consentGiven !== true) {
            throw new https_1.HttpsError("failed-precondition", "Consent must be true before finalizing.");
        }
        const patch = {
            status: "finalized",
            submittedAt: now,
            finalizedAt: now,
            updatedAt: now,
            updatedByUid: uid,
            pdf: {
                status: "queued",
                storagePath: (_c = (_b = data.pdf) === null || _b === void 0 ? void 0 : _b.storagePath) !== null && _c !== void 0 ? _c : null,
                url: (_e = (_d = data.pdf) === null || _d === void 0 ? void 0 : _d.url) !== null && _e !== void 0 ? _e : null,
                updatedAt: now,
            },
        };
        if (triageStatus === "green" || triageStatus === "amber" || triageStatus === "red") {
            patch.triageStatus = triageStatus;
        }
        tx.update(ref, patch);
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "assessment.finalized",
        actorUid: uid,
        metadata: { assessmentId },
    });
    return { success: true };
}
//# sourceMappingURL=finalizeAssessment.js.map