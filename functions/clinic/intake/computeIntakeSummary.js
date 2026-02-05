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
exports.computeIntakeSummaryV2 = void 0;
// functions/src/clinic/intake/computeIntakeSummary.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
if (!admin.apps.length) {
    admin.initializeApp();
}
function asString(v) {
    return v == null ? "" : String(v);
}
function nowServer() {
    return admin.firestore.FieldValue.serverTimestamp();
}
function getFlowId(session) {
    var _a, _b, _c, _d, _e;
    return ((_e = (_c = (_b = (_a = session === null || session === void 0 ? void 0 : session.flow) === null || _a === void 0 ? void 0 : _a.flowId) !== null && _b !== void 0 ? _b : session === null || session === void 0 ? void 0 : session.flowId) !== null && _c !== void 0 ? _c : (_d = session === null || session === void 0 ? void 0 : session.regionSelection) === null || _d === void 0 ? void 0 : _d.bodyArea) !== null && _e !== void 0 ? _e : "");
}
/**
 * Phase 3 summary: triage + patient-safe narrative only.
 * No differentials, no tests.
 */
function buildPhase3Summary(session) {
    var _a, _b;
    const flowId = getFlowId(session);
    const triage = (session === null || session === void 0 ? void 0 : session.triage) &&
        typeof session.triage === "object" &&
        typeof session.triage.status === "string"
        ? {
            status: (_a = session.triage.status) !== null && _a !== void 0 ? _a : "green",
            reasons: Array.isArray(session.triage.reasons)
                ? session.triage.reasons.map((x) => asString(x))
                : [],
        }
        : { status: "green", reasons: [] };
    const narrative = typeof ((_b = session === null || session === void 0 ? void 0 : session.summary) === null || _b === void 0 ? void 0 : _b.narrative) === "string"
        ? session.summary.narrative
        : "";
    return {
        status: "ready",
        flowId,
        triage,
        narrative,
        generatedAt: nowServer(),
    };
}
/**
 * Gen2 Callable (v2):
 * - Region pinned here so it remains consistent even if exported via `export *`
 * - If you prefer centralizing region in index.ts, we can instead export a handler function,
 *   but this drop-in keeps your current pattern.
 */
exports.computeIntakeSummaryV2 = (0, https_1.onCall)({ region: "europe-west3", cors: true }, async (req) => {
    var _a, _b, _c, _d;
    try {
        const clinicId = asString((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
        const intakeSessionId = asString((_b = req.data) === null || _b === void 0 ? void 0 : _b.intakeSessionId);
        if (!clinicId || !intakeSessionId) {
            throw new https_1.HttpsError("invalid-argument", "clinicId and intakeSessionId are required", { clinicId, intakeSessionId });
        }
        const ref = admin
            .firestore()
            .collection("clinics")
            .doc(clinicId)
            .collection("intakeSessions")
            .doc(intakeSessionId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new https_1.HttpsError("not-found", "Intake session not found", {
                clinicId,
                intakeSessionId,
            });
        }
        const session = snap.data() || {};
        const flowId = getFlowId(session);
        const summary = buildPhase3Summary(session);
        await ref.set({
            summary,
            summaryStatus: "ready",
            summaryError: admin.firestore.FieldValue.delete(),
            summaryUpdatedAt: nowServer(),
        }, { merge: true });
        return { ok: true, summaryStatus: "ready", flowId };
    }
    catch (err) {
        console.error("computeIntakeSummary crashed", err);
        throw new https_1.HttpsError("internal", (_c = err === null || err === void 0 ? void 0 : err.message) !== null && _c !== void 0 ? _c : "Summary failed", {
            name: err === null || err === void 0 ? void 0 : err.name,
            stack: ((_d = err === null || err === void 0 ? void 0 : err.stack) !== null && _d !== void 0 ? _d : "")
                .toString()
                .split("\n")
                .slice(0, 12)
                .join("\n"),
        });
    }
});
//# sourceMappingURL=computeIntakeSummary.js.map