// functions/src/auth/blockSelfSignup.ts
import * as admin from "firebase-admin";
import { beforeUserCreated } from "firebase-functions/v2/identity";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Platform-level allowlist
// Collection: /platformAuthAllowlist/{emailLower}
const ALLOWLIST_COLLECTION = "platformAuthAllowlist";

function normEmail(v: unknown): string {
  return (v ?? "").toString().trim().toLowerCase();
}

function isNotExpiredInvite(inv: any): boolean {
  try {
    const exp = inv?.expiresAt;
    if (!exp) return false;
    const ms = typeof exp.toMillis === "function" ? exp.toMillis() : 0;
    return ms > Date.now();
  } catch {
    return false;
  }
}

/**
 * OPTION D: Block all self sign-ups unless:
 *  - email is allowlisted, OR
 *  - email has a pending invite (status=pending and not expired)
 */
export const blockSelfSignup = beforeUserCreated(
  { region: "europe-west3" },
  async (event) => {
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
    const allowEnabled = allowSnap.exists && allowSnap.data()?.enabled === true;
    if (allowEnabled) return;

    // 2) Pending invite pass (collectionGroup across clinics/*/invites)
    // NOTE: keep query simple to avoid composite indexes:
    const q = await db
      .collectionGroup("invites")
      .where("email", "==", email)
      .where("status", "==", "pending")
      .limit(10)
      .get();

    const hasValidInvite = q.docs.some((d) => isNotExpiredInvite(d.data()));
    if (hasValidInvite) return;

    // Otherwise block
    throw new Error("SIGNUP_DISABLED");
  }
);
