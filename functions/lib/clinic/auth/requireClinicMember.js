"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireClinicMember = requireClinicMember;
// functions/src/clinic/auth/requireClinicMember.ts
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
/**
 * Ensures the caller is authenticated AND is an ACTIVE member of the clinic.
 * Canonical membership doc:
 *   clinics/{clinicId}/memberships/{uid}
 *
 * Back-compat:
 * - If canonical membership is missing but legacy exists at /members/{uid}, we accept it.
 * - Treat missing "active" as active (mirrors Firestore rules behavior).
 * - Also supports status: "active"|"invited"|"suspended" if present.
 */
async function requireClinicMember(auth, clinicId) {
    if (!(auth === null || auth === void 0 ? void 0 : auth.uid)) {
        throw new https_1.HttpsError("unauthenticated", "You must be signed in.");
    }
    const c = (clinicId !== null && clinicId !== void 0 ? clinicId : "").trim();
    if (!c) {
        throw new https_1.HttpsError("invalid-argument", "clinicId is required.");
    }
    const uid = auth.uid;
    const db = (0, firestore_1.getFirestore)();
    const canonicalRef = db.doc(`clinics/${c}/memberships/${uid}`);
    const legacyRef = db.doc(`clinics/${c}/members/${uid}`);
    // Prefer canonical
    const canonicalSnap = await canonicalRef.get();
    if (canonicalSnap.exists) {
        const data = canonicalSnap.data() || {};
        const status = data.status;
        if (status === "suspended") {
            throw new https_1.HttpsError("permission-denied", "Your membership is suspended for this clinic.");
        }
        if (status === "invited") {
            throw new https_1.HttpsError("permission-denied", "Invite not accepted for this clinic.");
        }
        // Back-compat: missing active => active
        if ("active" in data && data.active === false) {
            throw new https_1.HttpsError("permission-denied", "Your membership is inactive for this clinic.");
        }
        return { uid, membershipPath: canonicalRef.path };
    }
    // Back-compat: legacy member doc
    const legacySnap = await legacyRef.get();
    if (legacySnap.exists) {
        const data = legacySnap.data() || {};
        if (data.active === false) {
            throw new https_1.HttpsError("permission-denied", "Your membership is inactive for this clinic.");
        }
        return { uid, membershipPath: legacyRef.path };
    }
    throw new https_1.HttpsError("permission-denied", "You are not a member of this clinic.");
}
//# sourceMappingURL=requireClinicMember.js.map