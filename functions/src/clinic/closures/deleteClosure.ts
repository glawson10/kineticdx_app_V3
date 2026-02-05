import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import { requireActiveMemberWithPerm } from "../authz";
import { writeAuditEvent } from "../audit/audit";

type Input = {
  clinicId: string;
  closureId: string;
};

export async function deleteClosure(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const closureId = (req.data?.closureId ?? "").trim();

  if (!clinicId || !closureId) {
    throw new HttpsError("invalid-argument", "clinicId and closureId required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "settings.write");

  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = db.doc(`clinics/${clinicId}/closures/${closureId}`);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new HttpsError("not-found", "Closure not found.");
  }

  await ref.set(
    {
      active: false,
      updatedAt: now,
      updatedByUid: uid,
    },
    { merge: true }
  );

  await writeAuditEvent(db, clinicId, {
    type: "clinic.closure.deleted",
    actorUid: uid,
    metadata: { closureId },
  });

  return { ok: true };
}
