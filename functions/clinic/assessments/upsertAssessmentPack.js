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
exports.upsertAssessmentPack = upsertAssessmentPack;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const schemaVersions_1 = require("../../schema/schemaVersions");
const audit_1 = require("../audit/audit");
const paths_1 = require("../paths");
async function upsertAssessmentPack(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const packId = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.packId) !== null && _d !== void 0 ? _d : "").trim();
    const name = ((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.name) !== null && _f !== void 0 ? _f : "").trim();
    const description = ((_h = (_g = req.data) === null || _g === void 0 ? void 0 : _g.description) !== null && _h !== void 0 ? _h : "").trim() || null;
    const regions = (_k = (_j = req.data) === null || _j === void 0 ? void 0 : _j.regions) !== null && _k !== void 0 ? _k : null;
    const active = (_m = (_l = req.data) === null || _l === void 0 ? void 0 : _l.active) !== null && _m !== void 0 ? _m : true;
    if (!clinicId || !packId || !name) {
        throw new https_1.HttpsError("invalid-argument", "clinicId, packId, name required.");
    }
    if (!regions || typeof regions !== "object" || Array.isArray(regions)) {
        throw new https_1.HttpsError("invalid-argument", "regions object required.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "settings.write");
    const now = admin.firestore.FieldValue.serverTimestamp();
    const ref = (0, paths_1.assessmentPackRef)(db, clinicId, packId);
    const snap = await ref.get();
    const doc = {
        schemaVersion: (0, schemaVersions_1.schemaVersion)("assessmentPack"),
        name,
        description,
        regions,
        active: active === true,
        updatedAt: now,
        updatedByUid: uid,
    };
    if (!snap.exists) {
        Object.assign(doc, {
            createdAt: now,
            createdByUid: uid,
        });
    }
    await ref.set(doc, { merge: true });
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "assessmentPack.upserted",
        actorUid: uid,
        metadata: { packId, name, active: active === true },
    });
    return { success: true, packId };
}
//# sourceMappingURL=upsertAssessmentPack.js.map