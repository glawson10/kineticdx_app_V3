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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.enforceRateLimit = enforceRateLimit;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const crypto_1 = __importDefault(require("crypto"));
function safeStr(v) {
    return typeof v === "string" ? v.trim() : "";
}
function sha256Hex(input) {
    return crypto_1.default.createHash("sha256").update(input).digest("hex");
}
function getClientIp(req) {
    var _a, _b, _c, _d;
    const headers = (_a = req === null || req === void 0 ? void 0 : req.headers) !== null && _a !== void 0 ? _a : {};
    // Express will often provide these; Cloud Run / proxies usually set x-forwarded-for
    const xf = safeStr((_b = headers["x-forwarded-for"]) !== null && _b !== void 0 ? _b : headers["X-Forwarded-For"]);
    const ipFromXf = (xf.split(",")[0] || "").trim();
    const direct = safeStr(req === null || req === void 0 ? void 0 : req.ip) ||
        safeStr((_c = req === null || req === void 0 ? void 0 : req.socket) === null || _c === void 0 ? void 0 : _c.remoteAddress) ||
        safeStr((_d = req === null || req === void 0 ? void 0 : req.connection) === null || _d === void 0 ? void 0 : _d.remoteAddress);
    return (ipFromXf || direct || "unknown").trim();
}
async function enforceRateLimit(params) {
    const { db, clinicId, req, cfg } = params;
    const ip = getClientIp(req);
    const keyRaw = `${cfg.name}|${clinicId}|${ip}`;
    const key = sha256Hex(keyRaw);
    const ref = db.collection("publicRateLimits").doc(key);
    const nowMs = Date.now();
    const windowMs = Math.max(1, cfg.windowSeconds) * 1000;
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        let count = 0;
        let windowStartMs = nowMs;
        if (snap.exists) {
            const d = snap.data();
            count = typeof d.count === "number" ? d.count : 0;
            windowStartMs = typeof d.windowStartMs === "number" ? d.windowStartMs : nowMs;
        }
        // Reset window if expired
        if (nowMs - windowStartMs >= windowMs) {
            count = 0;
            windowStartMs = nowMs;
        }
        if (count >= cfg.max) {
            throw new https_1.HttpsError("resource-exhausted", "Too many requests. Please try again shortly.");
        }
        // Optional: enable TTL on expiresAt in Firestore later
        const expiresAt = admin.firestore.Timestamp.fromMillis(windowStartMs + windowMs + 60000);
        tx.set(ref, {
            name: cfg.name,
            clinicId,
            ip,
            count: count + 1,
            windowStartMs,
            expiresAt,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
//# sourceMappingURL=rateLimit.js.map