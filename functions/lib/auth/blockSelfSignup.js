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
exports.blockSelfSignup = void 0;
// functions/src/auth/blockSelfSignup.ts
const admin = __importStar(require("firebase-admin"));
const identity_1 = require("firebase-functions/v2/identity");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
// Platform-level allowlist
// Collection: /platformAuthAllowlist/{emailLower}
const ALLOWLIST_COLLECTION = "platformAuthAllowlist";
function normEmail(v) {
    return (v !== null && v !== void 0 ? v : "").toString().trim().toLowerCase();
}
function isNotExpiredInvite(inv) {
    try {
        const exp = inv === null || inv === void 0 ? void 0 : inv.expiresAt;
        if (!exp)
            return false;
        const ms = typeof exp.toMillis === "function" ? exp.toMillis() : 0;
        return ms > Date.now();
    }
    catch {
        return false;
    }
}
/**
 * OPTION D: Block all self sign-ups unless:
 *  - email is allowlisted, OR
 *  - email has a pending invite (status=pending and not expired)
 */
exports.blockSelfSignup = (0, identity_1.beforeUserCreated)({ region: "europe-west3" }, async (event) => {
    var _a;
    if (!event.data) {
        throw new Error("SIGNUP_BLOCKED_NO_EVENT_DATA");
    }
    const email = normEmail(event.data.email);
    if (!email) {
        throw new Error("SIGNUP_DISABLED_NO_EMAIL");
    }
    // 1) Allowlist pass
    const allowRef = db.collection(ALLOWLIST_COLLECTION).doc(email);
    const allowSnap = await allowRef.get();
    const allowEnabled = allowSnap.exists && ((_a = allowSnap.data()) === null || _a === void 0 ? void 0 : _a.enabled) === true;
    if (allowEnabled)
        return;
    // 2) Pending invite pass (collectionGroup across clinics/*/invites)
    // NOTE: keep query simple to avoid composite indexes:
    const q = await db
        .collectionGroup("invites")
        .where("email", "==", email)
        .where("status", "==", "pending")
        .limit(10)
        .get();
    const hasValidInvite = q.docs.some((d) => isNotExpiredInvite(d.data()));
    if (hasValidInvite)
        return;
    // Otherwise block
    throw new Error("SIGNUP_DISABLED");
});
//# sourceMappingURL=blockSelfSignup.js.map