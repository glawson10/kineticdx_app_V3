import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "./authz";

type Input = { clinicId: string };

export async function backfillScheduleWrite(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").toString().trim();
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  // ✅ requester must be active + members.manage
  await requireActiveMemberWithPerm(db, clinicId, uid, "members.manage");

  // ✅ canonical memberships
  const canonSnap = await db
    .collection("clinics")
    .doc(clinicId)
    .collection("memberships")
    .get();

  const batch = db.batch();
  let count = 0;
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const doc of canonSnap.docs) {
    const data = doc.data() as any;
    const perms = (data.permissions ?? {}) as Record<string, any>;

    if (perms["schedule.read"] === true && perms["schedule.write"] !== true) {
      batch.update(doc.ref, {
        "permissions.schedule.write": true,
        updatedAt: now,
      });
      count++;
    }
  }

  // Optional: keep legacy in sync during migration
  const legacySnap = await db
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .get();

  for (const doc of legacySnap.docs) {
    const data = doc.data() as any;
    const perms = (data.permissions ?? {}) as Record<string, any>;

    if (perms["schedule.read"] === true && perms["schedule.write"] !== true) {
      batch.update(doc.ref, {
        "permissions.schedule.write": true,
        updatedAt: now,
      });
      // don't double count if same UID exists in both
      // (count tracks canonical primarily)
    }
  }

  if (count === 0 && legacySnap.empty) return { success: true, updated: 0 };

  await batch.commit();
  return { success: true, updated: count };
}
