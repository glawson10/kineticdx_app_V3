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
exports.exportClosureOverrideAuditReport = exportClosureOverrideAuditReport;
// functions/src/clinic/audit/exportClosureOverrideAuditReport.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const authz_1 = require("../authz");
const audit_1 = require("./audit");
function csvEscape(v) {
    const s = (v !== null && v !== void 0 ? v : "").toString();
    if (s.includes('"') || s.includes(",") || s.includes("\n") || s.includes("\r")) {
        return `"${s.replace(/"/g, '""')}"`;
    }
    return s;
}
function fmtDateTime(d) {
    return d.toISOString();
}
async function exportClosureOverrideAuditReport(req) {
    var _a, _b, _c, _d, _e, _f;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = ((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId) !== null && _b !== void 0 ? _b : "").trim();
    const format = ((_d = (_c = req.data) === null || _c === void 0 ? void 0 : _c.format) !== null && _d !== void 0 ? _d : "csv");
    const limit = Math.max(1, Math.min(5000, Number((_f = (_e = req.data) === null || _e === void 0 ? void 0 : _e.limit) !== null && _f !== void 0 ? _f : 2000)));
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    if (format !== "csv" && format !== "pdf") {
        throw new https_1.HttpsError("invalid-argument", "format must be csv or pdf.");
    }
    const db = admin.firestore();
    const uid = req.auth.uid;
    await (0, authz_1.requireActiveMemberWithPerm)(db, clinicId, uid, "audit.read");
    const snap = await db
        .collection("clinics")
        .doc(clinicId)
        .collection("audit")
        .where("type", "==", "appointment.closed_override")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();
    const rows = snap.docs.map((d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        const data = d.data() || {};
        const meta = data["metadata"] && typeof data["metadata"] === "object" ? data["metadata"] : {};
        const createdAt = (_c = (_b = (_a = data["createdAt"]) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : null;
        return {
            id: d.id,
            createdAt: createdAt ? fmtDateTime(createdAt) : "",
            actorUid: (_d = data["actorUid"]) !== null && _d !== void 0 ? _d : "",
            actorDisplayName: (_e = data["actorDisplayName"]) !== null && _e !== void 0 ? _e : "",
            appointmentId: (_f = meta["appointmentId"]) !== null && _f !== void 0 ? _f : "",
            startMs: (_g = meta["startMs"]) !== null && _g !== void 0 ? _g : "",
            endMs: (_h = meta["endMs"]) !== null && _h !== void 0 ? _h : "",
            closureIds: Array.isArray(meta["closureIds"]) ? meta["closureIds"].join("|") : "",
            reason: (_j = meta["reason"]) !== null && _j !== void 0 ? _j : "",
        };
    });
    const header = [
        "auditId",
        "createdAt",
        "actorUid",
        "actorDisplayName",
        "appointmentId",
        "startMs",
        "endMs",
        "closureIds",
        "reason",
    ];
    const csv = header.join(",") +
        "\n" +
        rows
            .map((r) => [
            r.id,
            r.createdAt,
            r.actorUid,
            r.actorDisplayName,
            r.appointmentId,
            r.startMs,
            r.endMs,
            r.closureIds,
            r.reason,
        ]
            .map(csvEscape)
            .join(","))
            .join("\n");
    // audit the export action (no PHI)
    await (0, audit_1.writeAuditEvent)(db, clinicId, {
        type: "audit.closureOverride.exported",
        actorUid: uid,
        metadata: { format, count: rows.length, limit },
    });
    if (format === "csv") {
        return { ok: true, csv };
    }
    // For now, generate CSV and return signed URL (pdf can come later)
    const bucket = admin.storage().bucket();
    const filePath = `clinics/${clinicId}/reports/closure-overrides/${Date.now()}_${uid}.csv`;
    const file = bucket.file(filePath);
    await file.save(csv, {
        contentType: "text/csv; charset=utf-8",
        resumable: false,
        metadata: { cacheControl: "no-store" },
    });
    const [url] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 1000 * 60 * 60, // 1 hour
    });
    return { ok: true, url };
}
//# sourceMappingURL=exportClosureOverrideAuditReport.js.map