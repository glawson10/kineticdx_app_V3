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
exports.createClosure = createClosure;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const audit_1 = require("../audit/audit");
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function parseIso(label, v) {
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) {
        throw new https_1.HttpsError("invalid-argument", `Invalid ${label}. Must be ISO8601 string.`);
    }
    return d;
}
// ✅ IMPORTANT: this must be a named export
async function createClosure(req) {
    var _a, _b, _c, _d;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    const fromAtIso = safeStr((_b = req.data) === null || _b === void 0 ? void 0 : _b.fromAt);
    const toAtIso = safeStr((_c = req.data) === null || _c === void 0 ? void 0 : _c.toAt);
    const reason = safeStr((_d = req.data) === null || _d === void 0 ? void 0 : _d.reason);
    if (!clinicId || !fromAtIso || !toAtIso) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, fromAt, toAt are required.");
    }
    const fromAt = parseIso("fromAt", fromAtIso);
    const toAt = parseIso("toAt", toAtIso);
    if (toAt <= fromAt) {
        throw new https_1.HttpsError("invalid-argument", "toAt must be after fromAt.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    // ✅ Closures are scheduling operations
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "schedule.write");
    const now = admin.firestore.FieldValue.serverTimestamp();
    const ref = db.collection("clinics").doc(clinicId).collection("closures").doc();
    await ref.set({
        clinicId,
        active: true,
        fromAt: admin.firestore.Timestamp.fromDate(fromAt),
        toAt: admin.firestore.Timestamp.fromDate(toAt),
        // ✅ TS: strings use .length (not .isEmpty)
        reason: reason.length === 0 ? null : reason,
        createdAt: now,
        createdByUid: uid,
        updatedAt: now,
        updatedByUid: uid,
    });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "clinic.closure.created",
        actorUid: uid,
        metadata: { closureId: ref.id },
    });
    return { ok: true, closureId: ref.id };
}
//# sourceMappingURL=createClosure.js.map