// functions/src/clinic/auth/requireClinicMember.ts
import { HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

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
export async function requireClinicMember(
  auth: { uid: string } | undefined | null,
  clinicId: string
): Promise<{ uid: string; membershipPath: string }> {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const c = (clinicId ?? "").trim();
  if (!c) {
    throw new HttpsError("invalid-argument", "clinicId is required.");
  }

  const uid = auth.uid;
  const db = getFirestore();

  const canonicalRef = db.doc(`clinics/${c}/memberships/${uid}`);
  const legacyRef = db.doc(`clinics/${c}/members/${uid}`);

  // Prefer canonical
  const canonicalSnap = await canonicalRef.get();
  if (canonicalSnap.exists) {
    const data = canonicalSnap.data() || {};
    const status = (data as any).status;

    if (status === "suspended") {
      throw new HttpsError(
        "permission-denied",
        "Your membership is suspended for this clinic."
      );
    }
    if (status === "invited") {
      throw new HttpsError(
        "permission-denied",
        "Invite not accepted for this clinic."
      );
    }

    // Back-compat: missing active => active
    if ("active" in data && (data as any).active === false) {
      throw new HttpsError(
        "permission-denied",
        "Your membership is inactive for this clinic."
      );
    }

    return { uid, membershipPath: canonicalRef.path };
  }

  // Back-compat: legacy member doc
  const legacySnap = await legacyRef.get();
  if (legacySnap.exists) {
    const data = legacySnap.data() || {};
    if ((data as any).active === false) {
      throw new HttpsError(
        "permission-denied",
        "Your membership is inactive for this clinic."
      );
    }
    return { uid, membershipPath: legacyRef.path };
  }

  throw new HttpsError("permission-denied", "You are not a member of this clinic.");
}
