import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { hasPerm } from "../authz";
import { episodeRef, noteDraftRef } from "../paths";

type UpdateNoteDraftInput = {
  clinicId: string;
  patientId: string;
  episodeId: string;
  draftId: string;

  // draft payload patch (SOAP object) — stored as full replacement of `current`
  note: Record<string, any>;
};

function asObj(v: unknown): Record<string, any> | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  return v as Record<string, any>;
}

export async function updateNoteDraft(req: CallableRequest<UpdateNoteDraftInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();
  const draftId = (req.data?.draftId ?? "").trim();
  const note = asObj(req.data?.note);

  if (!clinicId || !patientId || !episodeId || !draftId) {
    throw new HttpsError("invalid-argument", "clinicId, patientId, episodeId, draftId required.");
  }
  if (!note) throw new HttpsError("invalid-argument", "note must be an object.");

  const db = admin.firestore();
  const uid = req.auth.uid;

  const epRef = episodeRef(db, clinicId, patientId, episodeId);
  const drRef = noteDraftRef(db, clinicId, patientId, episodeId, draftId);

  await db.runTransaction(async (tx) => {
    const epSnap = await tx.get(epRef);
    if (!epSnap.exists) throw new HttpsError("not-found", "Episode not found.");

    const drSnap = await tx.get(drRef);
    if (!drSnap.exists) throw new HttpsError("not-found", "Draft not found.");

    const draft = drSnap.data() as any;
    if (draft.status !== "draft") {
      throw new HttpsError("failed-precondition", "Draft is not editable.");
    }

    const authorUid = (draft.authorUid ?? "").toString();
    const isAuthor = authorUid === uid;

    const canWriteOwn = await hasPerm(db, clinicId, uid, "notes.write.own");
    const canWriteAny = await hasPerm(db, clinicId, uid, "notes.write.any");

    if (isAuthor) {
      if (!canWriteOwn && !canWriteAny) {
        throw new HttpsError("permission-denied", "Missing permission: notes.write.own");
      }
    } else {
      if (!canWriteAny) {
        throw new HttpsError("permission-denied", "Only managers can edit others' drafts.");
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.update(drRef, {
      current: note,
      updatedAt: now,
      version: admin.firestore.FieldValue.increment(1),
    });
  });

  return { success: true, draftId };
}
