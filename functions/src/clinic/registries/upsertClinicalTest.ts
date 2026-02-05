import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";

type UpsertClinicalTestInput = {
  clinicId: string;
  testId: string; // stable key
  data: Record<string, any>;
};

function asObj(v: unknown): Record<string, any> | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  return v as Record<string, any>;
}

export async function upsertClinicalTest(req: CallableRequest<UpsertClinicalTestInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const testId = (req.data?.testId ?? "").trim();
  const data = asObj(req.data?.data);

  if (!clinicId || !testId) {
    throw new HttpsError("invalid-argument", "clinicId and testId required.");
  }
  if (!data) throw new HttpsError("invalid-argument", "data object required.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "registries.manage");

  const now = admin.firestore.FieldValue.serverTimestamp();

  // ✅ Matches Firestore rules:
  // clinics/{clinicId}/clinicalTestRegistry/{testId}
  const ref = db
    .collection("clinics")
    .doc(clinicId)
    .collection("clinicalTestRegistry")
    .doc(testId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    if (!snap.exists) {
      tx.set(
        ref,
        {
          ...data,
          schemaVersion: 1,
          createdAt: now,
          createdByUid: uid,
          updatedAt: now,
          updatedByUid: uid,
        },
        { merge: true }
      );
      return;
    }

    tx.set(
      ref,
      {
        ...data,
        updatedAt: now,
        updatedByUid: uid,
      },
      { merge: true }
    );
  });

  return { success: true };
}
