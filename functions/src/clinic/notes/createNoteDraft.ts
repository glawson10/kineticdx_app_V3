import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { hasPerm } from "../authz";
import { episodeRef, noteDraftRef } from "../paths";

type CreateNoteDraftInput = {
  clinicId: string;
  patientId: string;
  episodeId: string;

  // "initial" | "followup" | "custom"
  noteType: "initial" | "followup" | "custom";

  // Optional links
  appointmentId?: string;
  assessmentId?: string;
  previousNoteId?: string;

  // Draft payload (SOAP object)
  note?: Record<string, any>;
};

function asObj(v: unknown): Record<string, any> | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  return v as Record<string, any>;
}

async function requireCanWriteAnyOrOwn(db: admin.firestore.Firestore, clinicId: string, uid: string) {
  const canOwn = await hasPerm(db, clinicId, uid, "notes.write.own");
  const canAny = await hasPerm(db, clinicId, uid, "notes.write.any");
  if (!canOwn && !canAny) {
    throw new HttpsError("permission-denied", "Missing permission: notes.write.own or notes.write.any");
  }
}

export async function createNoteDraft(req: CallableRequest<CreateNoteDraftInput>) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const clinicId = (req.data?.clinicId ?? "").trim();
  const patientId = (req.data?.patientId ?? "").trim();
  const episodeId = (req.data?.episodeId ?? "").trim();
  const noteType = req.data?.noteType;
  const note = asObj(req.data?.note ?? {}) ?? {};

  if (!clinicId || !patientId || !episodeId || !noteType) {
    throw new HttpsError("invalid-argument", "clinicId, patientId, episodeId, noteType are required.");
  }
  if (noteType !== "initial" && noteType !== "followup" && noteType !== "custom") {
    throw new HttpsError("invalid-argument", "Invalid noteType.");
  }

  const db = admin.firestore();
  const uid = req.auth.uid;

  await requireCanWriteAnyOrOwn(db, clinicId, uid);

  const ep = episodeRef(db, clinicId, patientId, episodeId);
  const epSnap = await ep.get();
  if (!epSnap.exists) throw new HttpsError("not-found", "Episode not found.");

  // Followup requires previousNoteId (optional strictness)
  if (noteType === "followup" && !(req.data?.previousNoteId ?? "").trim()) {
    throw new HttpsError("failed-precondition", "followup drafts require previousNoteId.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const dr = noteDraftRef(db, clinicId, patientId, episodeId, db.collection("_").doc().id);

  // noteDraftRef expects an id; we generated one above.
  const draftId = dr.id;

  await dr.set({
    schemaVersion: 1,

    clinicId,
    patientId,
    episodeId,

    noteType,
    appointmentId: (req.data?.appointmentId ?? null),
    assessmentId: (req.data?.assessmentId ?? null),
    previousNoteId: (req.data?.previousNoteId ?? null),

    authorUid: uid,
    status: "draft", // draft | finalized | abandoned
    version: 1,
    current: note,

    createdAt: now,
    updatedAt: now,
    finalizedAt: null,
    finalizedByUid: null,
    noteId: null, // filled on finalize
  });

  return { success: true, draftId };
}
