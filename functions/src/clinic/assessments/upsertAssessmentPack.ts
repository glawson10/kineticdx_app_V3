import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireActiveMemberWithPerm } from "../authz";
import { schemaVersion } from "../../schema/schemaVersions";
import { writeAuditEvent } from "../audit/audit";
import { assessmentPackRef } from "../paths";
import { AssessmentPackDoc } from "./types";

type Input = {
  clinicId: string;
  packId: string; // stable id, e.g. "default", "msk-v1"
  name: string;
  description?: string;

  regions: AssessmentPackDoc["regions"];
  active?: boolean;
};

export async function upsertAssessmentPack(req: CallableRequest<Input>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const packId = (req.data?.packId ?? "").trim();
  const name = (req.data?.name ?? "").trim();
  const description = (req.data?.description ?? "").trim() || null;
  const regions = req.data?.regions ?? null;
  const active = req.data?.active ?? true;

  if (!clinicId || !packId || !name) {
    throw new HttpsError("invalid-argument", "clinicId, packId, name required.");
  }
  if (!regions || typeof regions !== "object" || Array.isArray(regions)) {
    throw new HttpsError("invalid-argument", "regions object required.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireActiveMemberWithPerm(db, clinicId, uid, "settings.write");

  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = assessmentPackRef(db, clinicId, packId);
  const snap = await ref.get();

  const doc: Partial<AssessmentPackDoc> = {
    schemaVersion: schemaVersion("assessmentPack"),
    name,
    description,
    regions,
    active: active === true,
    updatedAt: now,
    updatedByUid: uid,
  };

  if (!snap.exists) {
    Object.assign(doc, {
      createdAt: now,
      createdByUid: uid,
    });
  }

  await ref.set(doc, { merge: true });

  await writeAuditEvent(db, clinicId, {
    type: "assessmentPack.upserted",
    actorUid: uid,
    metadata: { packId, name, active: active === true },
  });

  return { success: true, packId };
}
