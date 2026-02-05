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
exports.syncMyDisplayName = syncMyDisplayName;
// functions/src/clinic/syncMyDisplayName.ts
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("firebase-functions/logger");
if (!admin.apps.length)
    admin.initializeApp();
function safeStr(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim();
}
function normEmail(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim().toLowerCase();
}
function fallbackNameFromEmail(emailLower) {
    var _a;
    const local = ((_a = emailLower.split("@")[0]) !== null && _a !== void 0 ? _a : "").trim();
    return local || "User";
}
function looksLikeEmailLocal(displayName, emailLower) {
    const d = safeStr(displayName).toLowerCase();
    if (!d)
        return false;
    const local = safeStr(emailLower.split("@")[0]).toLowerCase();
    if (!local)
        return false;
    return d === local;
}
function pickFirstNonEmpty(...vals) {
    for (const v of vals) {
        const s = safeStr(v);
        if (s)
            return s;
    }
    return "";
}
async function syncMyDisplayName(req) {
    var _a, _b, _c, _d, _e;
    if (!req.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    const clinicId = safeStr((_a = req.data) === null || _a === void 0 ? void 0 : _a.clinicId);
    if (!clinicId)
        throw new https_1.HttpsError("invalid-argument", "clinicId required.");
    const uid = req.auth.uid;
    const emailLower = normEmail((_b = req.auth.token) === null || _b === void 0 ? void 0 : _b.email);
    const db = admin.firestore();
    // ✅ Membership docs (canonical + legacy)
    const canonRef = db.collection("clinics").doc(clinicId).collection("memberships").doc(uid);
    const legacyRef = db.collection("clinics").doc(clinicId).collection("members").doc(uid);
    const [canonSnap, legacySnap] = await Promise.all([canonRef.get(), legacyRef.get()]);
    if (!canonSnap.exists && !legacySnap.exists) {
        throw new https_1.HttpsError("permission-denied", "Not a member of this clinic.");
    }
    const canon = (_c = (canonSnap.exists ? canonSnap.data() : null)) !== null && _c !== void 0 ? _c : {};
    const legacy = (_d = (legacySnap.exists ? legacySnap.data() : null)) !== null && _d !== void 0 ? _d : {};
    // ✅ Try to preserve an existing "real" name in membership docs
    const existingMembershipName = pickFirstNonEmpty(canon.displayName, canon.fullName, legacy.displayName, legacy.fullName);
    // ✅ Resolve Auth displayName (if set)
    let authDisplayName = "";
    try {
        const user = await admin.auth().getUser(uid);
        authDisplayName = safeStr(user.displayName);
    }
    catch (e) {
        logger_1.logger.warn("syncMyDisplayName: admin.auth().getUser failed", {
            uid,
            clinicId,
            err: safeStr(e === null || e === void 0 ? void 0 : e.message) || String(e),
        });
    }
    // Optional: allow client override later (disabled-by-default)
    const override = safeStr((_e = req.data) === null || _e === void 0 ? void 0 : _e.displayNameOverride);
    // ✅ Decide final displayName:
    // Priority:
    // 1) Existing membership name (IF it doesn't look like email local-part)
    // 2) Auth displayName
    // 3) Override (only if you later decide to trust it)
    // 4) Email local-part fallback
    // 5) "User"
    let displayName = "";
    const existingLooksLikeLocal = existingMembershipName && emailLower
        ? looksLikeEmailLocal(existingMembershipName, emailLower)
        : false;
    if (existingMembershipName && !existingLooksLikeLocal) {
        displayName = existingMembershipName;
    }
    else if (authDisplayName) {
        displayName = authDisplayName;
    }
    else if (override) {
        displayName = override;
    }
    else if (emailLower) {
        displayName = fallbackNameFromEmail(emailLower);
    }
    else {
        displayName = "User";
    }
    // ✅ If we’re about to "set" the same value as already stored, skip writes.
    const canonCurrent = pickFirstNonEmpty(canon.displayName, canon.fullName);
    const legacyCurrent = pickFirstNonEmpty(legacy.displayName, legacy.fullName);
    const canonNeedsWrite = canonSnap.exists && canonCurrent !== displayName;
    const legacyNeedsWrite = legacySnap.exists && legacyCurrent !== displayName;
    logger_1.logger.info("syncMyDisplayName: resolved", {
        clinicId,
        uid,
        emailLocal: emailLower ? fallbackNameFromEmail(emailLower) : "",
        existingMembershipName,
        existingLooksLikeLocal,
        authDisplayName,
        overrideUsed: !!override && !authDisplayName && !existingMembershipName,
        finalDisplayName: displayName,
        canonExists: canonSnap.exists,
        legacyExists: legacySnap.exists,
        canonNeedsWrite,
        legacyNeedsWrite,
    });
    if (!canonNeedsWrite && !legacyNeedsWrite) {
        return { ok: true, displayName, skipped: true };
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch = {
        displayName,
        fullName: displayName, // ✅ helps older UI keys
        updatedAt: now,
        updatedByUid: uid,
    };
    const batch = db.batch();
    if (canonNeedsWrite)
        batch.set(canonRef, patch, { merge: true });
    if (legacyNeedsWrite)
        batch.set(legacyRef, patch, { merge: true });
    await batch.commit();
    logger_1.logger.info("syncMyDisplayName: updated", {
        clinicId,
        uid,
        displayName,
        wroteCanon: canonNeedsWrite,
        wroteLegacy: legacyNeedsWrite,
    });
    return { ok: true, displayName };
}
//# sourceMappingURL=syncMyDisplayName.js.map